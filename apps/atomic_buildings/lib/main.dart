import 'package:atomic_store_flutter/atomic_store_flutter.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'src/repository.dart';
import 'ui/homes_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Loads the Rust library; on iOS and macOS it uses `nativeLibrary()`, which
  // knows the plugin's framework path, so no extra argument is needed.
  await AtomicFlutter.init();
  final dir = await getApplicationSupportDirectory();
  final node = await AtomicFlutter.open(
    path: '${dir.path}/atomic_buildings',
    agentName: 'Me',
  );
  runApp(BuildingsApp(
    BuildingRepository(node.store),
    actions: [AtomicAccountButton(node: node)],
  ));
}

class BuildingsApp extends StatelessWidget {
  const BuildingsApp(this.repo, {super.key, this.actions = const []});
  final BuildingRepository repo;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'AtomicBuildings',
        theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
        home: HomesPage(repo, actions: actions),
      );
}
