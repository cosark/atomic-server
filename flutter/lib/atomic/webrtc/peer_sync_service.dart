/// Chooses which of this device's drives meet their peers over WebRTC, and
/// keeps one [WebRtcPeerMesh] per chosen drive. The choice is the web's
/// (`discoverPeerDrives`, `browser/data-browser/src/helpers/browserPeerSync.ts`):
///
/// - a drive reaches its peers through the signalling service it names (its
///   `signalingUrl` property), else the hosted portal's `/webrtc-signal`;
/// - a drive that a Cloud Server already carries to every member is skipped:
///   peers add nothing there and only spend connections;
/// - the room is a hash of the drive, so the service never learns the drive.
///
/// Discovery is not authorization. A stranger who finds the room still has to
/// authenticate, and gets nothing the drive's rights do not allow.
library;

import 'dart:async';

import 'flutter_webrtc_connection.dart';
import 'peer_connection.dart';
import 'peer_identity.dart';
import 'peer_link_backend.dart';
import 'peer_mesh.dart';
import 'signaling_client.dart';

class WebRtcPeerSyncService {
  WebRtcPeerSyncService({
    required this.backend,
    required this.listDrives,
    required this.driveSignalingUrl,
    required this.usesCloudServer,
    this.portalUrl,
    PeerConnectionFactory? connect,
    this.signaling,
    this.onStatus,
  }) : _connect = connect ?? FlutterWebRtcConnection.create;

  final PeerLinkBackend backend;

  /// The drives on this device.
  final Future<List<String>> Function() listDrives;

  /// The `signalingUrl` a drive names, or null.
  final Future<String?> Function(String drive) driveSignalingUrl;

  /// True when a Cloud Server carries this drive to its members.
  final Future<bool> Function(String drive) usesCloudServer;

  /// The portal whose `/webrtc-signal` serves drives that name no service.
  final String? portalUrl;
  final PeerConnectionFactory _connect;
  final SignalingConnector? signaling;
  final void Function(String drive, String status)? onStatus;

  final _meshes = <String, WebRtcPeerMesh>{};
  final _statuses = <String, String>{};
  bool _stopped = true;
  Future<void>? _scan;

  /// The latest status line of each drive's room.
  Map<String, String> get statuses => Map.unmodifiable(_statuses);

  /// Drives that have a room open.
  Iterable<String> get drives => _meshes.keys;

  /// Starts, and again later to pick up drives created or removed since.
  Future<void> start() {
    _stopped = false;
    // One scan at a time; a call that arrives during one waits for it, then runs.
    final previous = _scan ?? Future<void>.value();
    return _scan = previous.then((_) => _scanDrives()).whenComplete(() {});
  }

  Future<void> _scanDrives() async {
    if (_stopped) return;
    final List<String> drives;
    try {
      drives = (await listDrives())
          .where(isPeerDrive)
          .map(canonicalDrive)
          .toSet()
          .toList();
    } catch (_) {
      return;
    }
    for (final drive in drives) {
      if (_stopped) return;
      if (_meshes.containsKey(drive)) continue;
      try {
        if (await usesCloudServer(drive)) continue;
        final url = peerSignalingUrl(
          driveSignalingUrl: await driveSignalingUrl(drive),
          portalUrl: portalUrl,
        );
        if (url == null || _stopped) continue;
        _meshes[drive] = WebRtcPeerMesh(
          drive: drive,
          signalingUrl: url,
          backend: backend,
          connect: _connect,
          signaling: signaling,
          onStatus: (status) {
            _statuses[drive] = status;
            onStatus?.call(drive, status);
          },
        )..start();
      } catch (_) {
        // Retried at the next scan.
      }
    }
    // A drive that left the device, or went to a Cloud Server, leaves its room.
    for (final gone
        in _meshes.keys.where((d) => !drives.contains(d)).toList()) {
      await _meshes.remove(gone)?.close();
      _statuses.remove(gone);
    }
  }

  /// Leaves every room: the app went to the background or signed out.
  Future<void> stop() async {
    _stopped = true;
    await _scan?.catchError((Object _) {});
    final meshes = _meshes.values.toList();
    _meshes.clear();
    _statuses.clear();
    for (final mesh in meshes) {
      await mesh.close();
    }
  }
}
