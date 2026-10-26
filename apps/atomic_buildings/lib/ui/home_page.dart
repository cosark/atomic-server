import 'package:atomic_store/atomic_store.dart';
import 'package:flutter/material.dart';

import '../src/repository.dart';
import 'common.dart';
import 'plan_view.dart';
import 'questions_view.dart';
import 'sources_view.dart';

class HomePage extends StatefulWidget {
  const HomePage(this.repo, this.home, {super.key});
  final BuildingRepository repo;
  final Resource home;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final (repo, home) = (widget.repo, widget.home);
    return Scaffold(
      appBar: AppBar(title: Text(home.name ?? 'Home')),
      body: [
        PlanView(repo, home),
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
