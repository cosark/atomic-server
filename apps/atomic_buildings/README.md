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

## Ontology status

The classes and properties come from the `ontology-kit` release v2 in
[atomic-plugins](https://github.com/ontola/atomic-plugins). That release is not
published yet: it lands with its open PR. Until it merges, the subjects in
`terms.g.dart` do not resolve over HTTP. The app does not need them to
resolve, because the local store accepts properties and classes it does not
know, but other apps will not see labels or datatypes for them. When the PR
merges, rerun the generator and check that `git diff` on `terms.g.dart` is
empty (`test/terms_test.dart` does this when the checkout is present).
