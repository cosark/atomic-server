import Flutter
import RoomPlan
import UIKit
import simd

/// Apple RoomPlan scanning for the Dart `PlatformRoomScanner`.
/// Channel `io.ontola.atomic_buildings/roomscan`:
///   isSupported -> Bool
///   scan        -> String (JSON of the contract in lib/src/roomplan.dart) or nil on cancel
/// Written without a Mac to compile on; see README "Scanning rooms".
final class RoomScanPlugin: NSObject, FlutterPlugin {
  private var pending: FlutterResult?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "io.ontola.atomic_buildings/roomscan", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(RoomScanPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isSupported":
      result(RoomCaptureSession.isSupported)
    case "scan":
      guard RoomCaptureSession.isSupported else {
        return result(FlutterError(code: "unsupported", message: "RoomPlan needs a LiDAR device", details: nil))
      }
      guard pending == nil, let presenter = RoomScanPlugin.topViewController() else {
        return result(FlutterError(code: "busy", message: "No view controller, or a scan is running", details: nil))
      }
      pending = result
      let scanner = RoomScanViewController { [weak self] json, error in
        guard let self = self, let reply = self.pending else { return }
        self.pending = nil
        if let error = error {
          reply(FlutterError(code: "scan_failed", message: error.localizedDescription, details: nil))
        } else {
          reply(json)  // nil when cancelled
        }
      }
      scanner.modalPresentationStyle = .fullScreen
      presenter.present(scanner, animated: true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func topViewController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
    var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }
}

/// Full-screen RoomCaptureView with Start and Done (and Cancel) buttons.
final class RoomScanViewController: UIViewController, RoomCaptureSessionDelegate {
  private let finish: (String?, Error?) -> Void
  private let captureView = RoomCaptureView(frame: .zero)
  private let primary = UIButton(type: .system)
  private let cancel = UIButton(type: .system)
  private var running = false
  private var finished = false

  init(finish: @escaping (String?, Error?) -> Void) {
    self.finish = finish
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { fatalError("not used") }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    captureView.frame = view.bounds
    captureView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    captureView.captureSession.delegate = self
    view.addSubview(captureView)

    primary.setTitle("Start", for: .normal)
    primary.addTarget(self, action: #selector(primaryTapped), for: .touchUpInside)
    cancel.setTitle("Cancel", for: .normal)
    cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
    for b in [primary, cancel] {
      b.translatesAutoresizingMaskIntoConstraints = false
      b.backgroundColor = UIColor.black.withAlphaComponent(0.6)
      b.setTitleColor(.white, for: .normal)
      b.titleLabel?.font = .preferredFont(forTextStyle: .headline)
      b.layer.cornerRadius = 12
      b.contentEdgeInsets = UIEdgeInsets(top: 12, left: 24, bottom: 12, right: 24)
      view.addSubview(b)
    }
    NSLayoutConstraint.activate([
      primary.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      primary.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
      cancel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
      cancel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
    ])
  }

  @objc private func primaryTapped() {
    if running {
      primary.isEnabled = false
      primary.setTitle("Processing...", for: .normal)
      captureView.captureSession.stop()  // didEndWith follows
    } else {
      running = true
      primary.setTitle("Done", for: .normal)
      captureView.captureSession.run(configuration: RoomCaptureSession.Configuration())
    }
  }

  @objc private func cancelTapped() {
    finished = true
    if running { captureView.captureSession.stop() }
    dismiss(animated: true) { self.finish(nil, nil) }
  }

  // MARK: RoomCaptureSessionDelegate

  func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: Error?) {
    if finished { return }
    finished = true
    Task { @MainActor in
      do {
        if let error = error { throw error }
        let room = try await RoomBuilder(options: [.beautifyObjects]).capturedRoom(from: data)
        let json = try RoomScanViewController.serialize(room)
        self.dismiss(animated: true) { self.finish(json, nil) }
      } catch {
        self.dismiss(animated: true) { self.finish(nil, error) }
      }
    }
  }

  // MARK: JSON contract

  private static func serialize(_ room: CapturedRoom) throws -> String {
    var surfaces: [[String: Any]] = []
    func add(_ list: [CapturedRoom.Surface], _ category: String) {
      for s in list {
        var d = item(s.identifier, category, s.transform, s.dimensions, s.confidence)
        if #available(iOS 17.0, *), let parent = s.parentIdentifier {
          d["parentId"] = parent.uuidString
        }
        surfaces.append(d)
      }
    }
    add(room.walls, "wall")
    add(room.doors, "door")
    add(room.windows, "window")
    add(room.openings, "opening")
    if #available(iOS 17.0, *) { add(room.floors, "floor") }

    let objects = room.objects.map {
      item($0.identifier, name($0.category), $0.transform, $0.dimensions, $0.confidence)
    }
    let json: [String: Any] = ["surfaces": surfaces, "objects": objects]
    let data = try JSONSerialization.data(withJSONObject: json)
    return String(decoding: data, as: UTF8.self)
  }

  private static func item(
    _ id: UUID, _ category: String, _ t: simd_float4x4, _ dims: simd_float3,
    _ confidence: CapturedRoom.Confidence
  ) -> [String: Any] {
    // Column-major, as the contract in lib/src/roomplan.dart says.
    var matrix: [Double] = []
    for column in [t.columns.0, t.columns.1, t.columns.2, t.columns.3] {
      matrix.append(Double(column.x))
      matrix.append(Double(column.y))
      matrix.append(Double(column.z))
      matrix.append(Double(column.w))
    }
    let level: String
    switch confidence {
    case .high: level = "high"
    case .medium: level = "medium"
    default: level = "low"
    }
    return [
      "category": category,
      "id": id.uuidString,
      "transform": matrix,
      "dimensions": [Double(dims.x), Double(dims.y), Double(dims.z)] as [Double],
      "confidence": level,
    ]
  }

  private static func name(_ c: CapturedRoom.Object.Category) -> String {
    switch c {
    case .storage: return "storage"
    case .refrigerator: return "refrigerator"
    case .stove: return "stove"
    case .bed: return "bed"
    case .sink: return "sink"
    case .washerDryer: return "washerDryer"
    case .toilet: return "toilet"
    case .bathtub: return "bathtub"
    case .oven: return "oven"
    case .dishwasher: return "dishwasher"
    case .table: return "table"
    case .sofa: return "sofa"
    case .chair: return "chair"
    case .fireplace: return "fireplace"
    case .television: return "television"
    case .stairs: return "stairs"
    default: return "object"
    }
  }
}
