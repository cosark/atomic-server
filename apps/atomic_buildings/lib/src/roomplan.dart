import 'dart:convert';
import 'dart:math' as math;

import 'package:atomic_store/atomic_store.dart';

import 'geometry.dart';
import 'repository.dart';

/// A room scan as the native RoomPlan plugin returns it (JSON contract).
///
/// ```
/// {
///   "name": "Living room",          // optional
///   "storeyHeight": 2.6,            // optional, metres
///   "surfaces": [{
///     "category": "wall",           // wall|door|window|opening|floor|ceiling
///     "id": "UUID",
///     "transform": [16 floats],     // column-major simd_float4x4, ARKit world
///     "dimensions": [w, h, d],      // metres, in the surface's local axes
///     "confidence": "high",         // low|medium|high
///     "parentId": "UUID"            // optional: the wall that hosts it
///   }],
///   "objects": [{ "category": "table", "id": "UUID", "transform": [...],
///                 "dimensions": [w, h, d], "confidence": "medium" }]
/// }
/// ```
///
/// ARKit world space is Y up, right-handed, metres. A transform's translation
/// (elements 12..14) is the item's centre; its local X axis is elements 0..2.
/// Walls run along local X for `w`; `h` is up (local Y); `d` is thickness.
class ScannedRoom {
  const ScannedRoom({
    this.name,
    this.storeyHeight,
    this.surfaces = const [],
    this.objects = const [],
  });

  factory ScannedRoom.fromJson(Map json) => ScannedRoom(
        name: json['name'] as String?,
        storeyHeight: (json['storeyHeight'] as num?)?.toDouble(),
        surfaces: [
          for (final s in (json['surfaces'] as List? ?? const []))
            ScannedItem.fromJson(s as Map, surface: true),
        ],
        objects: [
          for (final o in (json['objects'] as List? ?? const []))
            ScannedItem.fromJson(o as Map),
        ],
      );

  /// Parses the JSON string the plugin returns. Throws [FormatException].
  factory ScannedRoom.parse(String source) {
    try {
      return ScannedRoom.fromJson(jsonDecode(source) as Map);
    } on TypeError catch (e) {
      throw FormatException('Not a room scan: $e');
    }
  }

  final String? name;
  final double? storeyHeight;
  final List<ScannedItem> surfaces;
  final List<ScannedItem> objects;
}

/// A surface or an object of a [ScannedRoom].
class ScannedItem {
  const ScannedItem({
    required this.category,
    required this.id,
    required this.transform,
    required this.dimensions,
    this.confidence = 'low',
    this.parentId,
  });

  static const surfaceCategories = [
    'wall',
    'door',
    'window',
    'opening',
    'floor',
    'ceiling'
  ];

  factory ScannedItem.fromJson(Map json, {bool surface = false}) {
    final category = json['category'] as String;
    if (surface && !surfaceCategories.contains(category)) {
      throw FormatException('Unknown surface category "$category"');
    }
    final t = [
      for (final n in json['transform'] as List) (n as num).toDouble()
    ];
    final d = [
      for (final n in json['dimensions'] as List) (n as num).toDouble()
    ];
    if (t.length != 16) {
      throw const FormatException('transform needs 16 floats');
    }
    if (d.length != 3) throw const FormatException('dimensions needs 3 floats');
    return ScannedItem(
      category: category,
      id: json['id'] as String,
      transform: t,
      dimensions: d,
      confidence: json['confidence'] as String? ?? 'low',
      parentId: json['parentId'] as String?,
    );
  }

  final String category, id, confidence;
  final String? parentId;
  final List<double> transform, dimensions;

  /// The centre on the plan: ARKit (x, y up, z) becomes (x, -z).
  Pt get centre => Pt(transform[12], -transform[14]);

  /// Height of the centre above the ARKit origin.
  double get centreY => transform[13];

  /// The local X axis on the plan, unit length (ARKit (x, z) becomes (x, -z)).
  Pt get axisX {
    final (x, y) = (transform[0], -transform[2]);
    final n = math.sqrt(x * x + y * y);
    return n < 1e-9 ? const Pt(1, 0) : Pt(x / n, y / n);
  }

  double get confidenceValue =>
      const {'low': 0.3, 'medium': 0.6, 'high': 0.9}[confidence] ?? 0.3;
}

extension on Pt {
  Pt operator +(Pt o) => Pt(x + o.x, y + o.y);
  Pt operator -(Pt o) => Pt(x - o.x, y - o.y);
  Pt operator *(double k) => Pt(x * k, y * k);
  double dot(Pt o) => x * o.x + y * o.y;
}

/// The area of a polygon (shoelace), always positive.
double polygonArea(List<Pt> p) {
  var a = 0.0;
  for (var i = 0; i < p.length; i++) {
    final (q, r) = (p[i], p[(i + 1) % p.length]);
    a += q.x * r.y - r.x * q.y;
  }
  return a.abs() / 2;
}

/// The outline of [walls]: their end points, nearby ones merged (scans leave
/// gaps at corners), ordered by angle around the centroid. Right for convex
/// and most rectilinear rooms; an L-shaped room is approximated.
List<Pt> footprint(List<WallAxis> walls, {double merge = 0.25}) {
  final pts = <Pt>[];
  for (final w in walls) {
    for (final p in [w.start, w.end]) {
      final i = pts.indexWhere((q) => q.distanceTo(p) < merge);
      if (i < 0) {
        pts.add(p);
      } else {
        pts[i] = Pt((pts[i].x + p.x) / 2, (pts[i].y + p.y) / 2);
      }
    }
  }
  if (pts.length < 3) return const [];
  final c = Pt(pts.map((p) => p.x).reduce((a, b) => a + b) / pts.length,
      pts.map((p) => p.y).reduce((a, b) => a + b) / pts.length);
  double angle(Pt p) => math.atan2(p.y - c.y, p.x - c.x);
  return pts..sort((a, b) => angle(a).compareTo(angle(b)));
}

const _ifc = {
  'wall': 'IfcWall',
  'door': 'IfcDoor',
  'window': 'IfcWindow',
  'opening': 'IfcBuildingElementProxy',
};

String _label(String category) =>
    category[0].toUpperCase() + category.substring(1);

/// Writes [room] into [storey] as proposals: a Source (`scan`), a completed
/// AnalysisRun (`RoomPlan`), one Space, a wall Element per wall, openings
/// hosted by the nearest wall and objects as furnishing footprints, each with
/// Evidence on the Source. Returns the proposed Spaces and Elements. Rooms of
/// several scans all go into the same storey; their ARKit origins differ, so
/// they are not aligned with each other.
Future<List<Resource>> importScannedRoom(
  BuildingRepository repo,
  Resource storey,
  ScannedRoom room, {
  String? sourceFileSubject,
}) async {
  final home = await repo.store.getResource(storey.parent!);
  final name = room.name ?? 'Scanned room';
  final source = await repo.addSource(home, name, MediaKind.scan,
      file: sourceFileSubject, status: 'processed');
  final run = await repo.addAnalysisRun(
      home, 'RoomPlan scan: $name', 'RoomPlan',
      inputs: [source]);
  final created = <Resource>[];

  Future<Resource> track(Resource r, double confidence) async {
    await repo.addEvidence(home, source, r, confidence: confidence, run: run);
    created.add(r);
    return r;
  }

  const origin = Origin.import;
  final walls = room.surfaces.where((s) => s.category == 'wall').toList();
  // The floor of the scan: its lowest wall edge, so sills are above the floor.
  final floorY = walls.isEmpty
      ? 0.0
      : walls.map((w) => w.centreY - w.dimensions[1] / 2).reduce(math.min);

  final placed = <(ScannedItem, Resource, WallAxis)>[];
  for (final w in walls) {
    final half = w.axisX * (w.dimensions[0] / 2);
    final axis = WallAxis(
      start: w.centre - half,
      end: w.centre + half,
      height: w.dimensions[1],
      thickness: w.dimensions[2] > 0.01 ? w.dimensions[2] : 0.1,
    );
    final r = await repo.createElement(
        storey, 'Wall ${placed.length + 1}', _ifc['wall']!, axis,
        origin: origin, confidence: w.confidenceValue, run: run);
    placed.add((w, await track(r, w.confidenceValue), axis));
  }

  if (placed.isNotEmpty) {
    final outline = footprint([for (final (_, _, a) in placed) a]);
    if (outline.length >= 3) {
      final height =
          room.storeyHeight ?? placed.map((p) => p.$3.height).reduce(math.max);
      const c = 0.6;
      await track(
          await repo.createSpace(storey, name, 'other', outline,
              origin: origin, confidence: c, height: height, run: run),
          c);
    }
  }

  final counts = <String, int>{};
  for (final s in room.surfaces) {
    if (!const ['door', 'window', 'opening'].contains(s.category)) continue;
    final host = _hostOf(s, placed);
    if (host == null) continue; // nothing to hang it on
    final (_, hostRes, axis) = host;
    final u = (axis.end - axis.start) * (1 / axis.length);
    final along = (s.centre - axis.start).dot(u);
    final w = s.dimensions[0], h = s.dimensions[1];
    final opening = Opening(
      offset: math.max(0, math.min(along - w / 2, axis.length - w)),
      width: w,
      height: h,
      sill:
          s.category == 'window' ? math.max(0, s.centreY - h / 2 - floorY) : 0,
    );
    final n = counts.update(s.category, (n) => n + 1, ifAbsent: () => 1);
    await track(
        await repo.createElement(
            storey, '${_label(s.category)} $n', _ifc[s.category]!, opening,
            hostedBy: hostRes,
            origin: origin,
            confidence: s.confidenceValue,
            run: run),
        s.confidenceValue);
  }

  for (final o in room.objects) {
    final (x, z) = (o.axisX, Pt(-o.axisX.y, o.axisX.x));
    final (hw, hd) = (o.dimensions[0] / 2, o.dimensions[2] / 2);
    final c = o.centre;
    final n = counts.update(o.category, (n) => n + 1, ifAbsent: () => 1);
    await track(
        await repo.createElement(
            storey,
            '${_label(o.category)} $n',
            'IfcFurnishingElement',
            Extrusion(polygon: [
              c - x * hw - z * hd,
              c + x * hw - z * hd,
              c + x * hw + z * hd,
              c - x * hw + z * hd,
            ], depth: math.max(o.dimensions[1], 0.01)),
            origin: origin,
            confidence: o.confidenceValue,
            run: run),
        o.confidenceValue);
  }
  return created;
}

/// The wall named by `parentId`, else the wall whose axis is nearest.
(ScannedItem, Resource, WallAxis)? _hostOf(
  ScannedItem s,
  List<(ScannedItem, Resource, WallAxis)> walls,
) {
  final named = walls.where((w) => w.$1.id == s.parentId).firstOrNull;
  if (named != null) return named;
  (ScannedItem, Resource, WallAxis)? best;
  var bestD = double.infinity;
  for (final w in walls) {
    final a = w.$3;
    final ab = a.end - a.start;
    final t = ((s.centre - a.start).dot(ab) / ab.dot(ab)).clamp(0.0, 1.0);
    final d = s.centre.distanceTo(a.start + ab * t);
    if (d < bestD) (best, bestD) = (w, d);
  }
  return best;
}
