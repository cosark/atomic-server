# AtomicBuildings

A Flutter app that holds a digital twin of a house on Atomic Data: storeys,
rooms and walls on a 2D plan, the sources the twin came from (photos, floor
plans, notes), and the questions an AI asks when it is unsure. Atomic is the
storage and the engine; the AI is just another agent writing commits with
`origin = ai`, and a person confirms or rejects what it proposes.

The design is in the schema proposal (`atomic-buildings/schema-proposal.md`).

## Layout

- `lib/src/terms.g.dart`: generated constants for the `building-*` classes and
  `bldg-*` properties (`BuildingClass.space`, `Bldg.storey`). Regenerate with
  `dart run tool/gen_terms.dart [path/to/atomic-plugins/ontology]` (default
  `../../../atomic-plugins/ontology`, a sibling checkout of atomic-server).
- `lib/src/geometry.dart`: the geometry JSON (`wallAxis`, `extrusion`,
  `opening`, `mesh`), validated in Dart.
- `lib/src/repository.dart`: `BuildingRepository`, pure Dart over a `Store`.
  Every resource except a Home has the Home as `parent` (the permission
  anchor); containment is a `bldg-*` link, never the parent.
- `lib/src/roomplan.dart`, `lib/src/room_scanner.dart`: the room-scan JSON
  contract, its import into the twin, and the scanner interface.
- `lib/ui/`: Homes list, then per Home a Plan, Sources and Questions tab. The
  widgets take a `BuildingRepository`, so tests run on `InMemoryBackend`.

## Run

```
cd apps/atomic_buildings
flutter pub get
flutter test && flutter analyze
flutter run -d macos      # or an Android device or emulator, or iOS
```

The first build compiles the Rust node (`atomic_lib`) through the
`atomic_store_flutter` plugin, about 10 minutes cold; it needs a Rust toolchain
via rustup, and on Android the NDK. macOS needs Apple Silicon and macOS 12. The
platform folders already carry the settings that plugin asks for (see its
README): deployment targets, the Podfiles and the network entitlements. For a
stable keychain identity across debug builds set a development team in Xcode.
iOS and macOS have only been configured, not built or run.

## Scanning rooms (iPhone Pro)

Apple RoomPlan scans a room with LiDAR and returns parametric walls, doors,
windows, openings and objects. The Plan tab shows a **Scan room** button when
the device supports it; the result becomes proposals on the selected storey.

Requirements: an iPhone or iPad Pro with LiDAR, iOS 16 or later (the iOS
deployment target is 16.0), and a camera permission (`NSCameraUsageDescription`
is set). The native side is `ios/Runner/RoomScanPlugin.swift`, a method channel
`io.ontola.atomic_buildings/roomscan` with `isSupported` and `scan`; `scan`
returns this JSON as a string, or null when cancelled:

```
{ "name": "Living room",            // optional
  "storeyHeight": 2.6,              // optional, metres; else the tallest wall
  "surfaces": [{ "category": "wall|door|window|opening|floor|ceiling",
                 "id": "UUID",
                 "transform": [16 floats],   // column-major, ARKit world, Y up, metres
                 "dimensions": [w, h, d],    // metres, local axes
                 "confidence": "low|medium|high",
                 "parentId": "UUID" }],      // optional, the hosting wall
  "objects": [{ "category": "table", "id": "UUID", "transform": [16 floats],
                "dimensions": [w, h, d], "confidence": "medium" }] }
```

`importScannedRoom` maps it to a Source (`mediaKind` `scan`), a completed
AnalysisRun (`RoomPlan`), one Space (usage `other`, boundary from the wall end
points) and Elements, all `origin = import`, `reviewState = proposed`,
confidence 0.3 / 0.6 / 0.9, with Evidence on the Source. Coordinates: ARKit
(x, y up, z) becomes plan (x, -z); a wall's axis is its centre line along its
local X axis, `w` long. A door or window is hosted by its `parentId` wall, else
the nearest wall; its offset is measured along that wall, its sill is its lower
edge above the lowest wall edge of the scan (the floor). Objects become
`IfcFurnishingElement` footprints. Floors and ceilings are not stored. Several
scans go into the same storey, each with its own Space; their ARKit origins
differ, so rooms are not aligned with each other yet.

Unverified: the Swift plugin and the Xcode project edit were written without a
Mac and have never been compiled or run, so the RoomPlan API use (session
delegate, `RoomBuilder`, `parentIdentifier`, `floors`) and the real transform
conventions of RoomPlan output are untested. The Dart side is tested against a
synthetic room only. `scan` as a `bldg-media-kind` and the run status
`completed` should be checked against the ontology enum descriptions (`scan` is
not listed there yet).

## Ontology status

The classes and properties come from the `ontology-kit` release v2 in
[atomic-plugins](https://github.com/ontola/atomic-plugins). That release is not
published yet: it lands with its open PR. Until it merges, the subjects in
`terms.g.dart` do not resolve over HTTP. The app does not need them to
resolve, because the local store accepts properties and classes it does not
know, but other apps will not see labels or datatypes for them. When the PR
merges, rerun the generator and check that `git diff` on `terms.g.dart` is
empty (`test/terms_test.dart` does this when the checkout is present).
