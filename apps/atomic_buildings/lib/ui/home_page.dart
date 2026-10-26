import 'package:atomic_store/atomic_store.dart';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../src/gltf_export.dart';
import '../src/repository.dart';
import '../src/room_scanner.dart';
import 'common.dart';
import 'plan_view.dart';
import 'questions_view.dart';
import 'sources_view.dart';

class HomePage extends StatefulWidget {
  const HomePage(this.repo, this.home,
      {super.key, this.scanner, this.writeExport = _writeToDocuments});
  final BuildingRepository repo;
  final Resource home;

  /// Null means the platform scanner (RoomPlan on iOS).
  final RoomScanner? scanner;

  /// Stores an exported GLB under [name] and returns where it went; tests
  /// inject their own. The default writes to the app documents directory.
  final Future<String> Function(String name, Uint8List glb) writeExport;

  @override
  State<HomePage> createState() => _HomePageState();
}

Future<String> _writeToDocuments(String name, Uint8List glb) async {
  final file = File('${(await getApplicationDocumentsDirectory()).path}/$name');
  await file.writeAsBytes(glb);
  return file.path;
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;

  Future<void> _export() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final glb = await exportHomeGlb(widget.repo, widget.home.subject);
      final name = '${widget.home.name ?? 'home'}.glb'.replaceAll('/', '-');
      final path = await widget.writeExport(name, glb);
      messenger
          .showSnackBar(SnackBar(content: Text('3D model saved to $path')));
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final (repo, home) = (widget.repo, widget.home);
    return Scaffold(
      appBar: AppBar(
        title: Text(home.name ?? 'Home'),
        actions: [
          if (_tab == 0)
            IconButton(
              tooltip: 'Export 3D model',
              icon: const Icon(Icons.view_in_ar_outlined),
              onPressed: _export,
            ),
        ],
      ),
      body: [
        PlanView(repo, home, scanner: widget.scanner ?? PlatformRoomScanner()),
        SourcesView(repo, home),
        QuestionsView(repo, home),
      ][_tab],
      floatingActionButton: _tab != 1
          ? null
          : FloatingActionButton(
              tooltip: 'Add note',
              onPressed: () async {
                final text = await askText(context, 'Note');
                if (text != null) {
                  await repo.addSource(home, text, MediaKind.note);
                }
              },
              child: const Icon(Icons.note_add),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.map), label: 'Plan'),
          const NavigationDestination(
              icon: Icon(Icons.photo_library), label: 'Sources'),
          NavigationDestination(
            label: 'Questions',
            icon: Watch(
              stream: () => repo.watchOpenQuestions(home),
              builder: (_, open) => Badge(
                isLabelVisible: open.isNotEmpty,
                label: Text('${open.length}'),
                child: const Icon(Icons.help),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
