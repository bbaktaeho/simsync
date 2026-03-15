import 'package:flutter/material.dart';

import '../settings/app_settings_controller.dart';
import '../services/note_service.dart';
import '../storage/note_storage.dart';
import '../storage/github/github_sync_engine.dart';
import '../storage/github/repo_cache.dart';
import '../theme/app_colors.dart';
import 'calendar_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final Future<void> Function() onLogout;
  final NoteStorage storage;
  final NoteStorage? localStorage;
  final NoteService noteService;
  final ValueNotifier<int> refreshSignal;
  final String? avatarUrl;
  final RepoEntry? activeRepo;
  final AppSettingsController settingsController;
  final GitHubSyncEngine? syncEngine;
  final void Function(bool enabled) onSyncEnabledChanged;

  const HomeScreen({
    super.key,
    required this.onLogout,
    required this.storage,
    this.localStorage,
    required this.noteService,
    required this.refreshSignal,
    this.avatarUrl,
    this.activeRepo,
    required this.settingsController,
    this.syncEngine,
    required this.onSyncEnabledChanged,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          CalendarScreen(
            storage: widget.storage,
            localStorage: widget.localStorage,
            noteService: widget.noteService,
            refreshSignal: widget.refreshSignal,
            avatarUrl: widget.avatarUrl,
            settingsController: widget.settingsController,
            syncEngine: widget.syncEngine,
          ),
          SearchScreen(
            storage: widget.storage,
            localStorage: widget.localStorage,
            settingsController: widget.settingsController,
            refreshSignal: widget.refreshSignal,
          ),
          SettingsScreen(
            onLogout: widget.onLogout,
            avatarUrl: widget.avatarUrl,
            activeRepo: widget.activeRepo,
            settingsController: widget.settingsController,
            syncEngine: widget.syncEngine,
            onSyncEnabledChanged: widget.onSyncEnabledChanged,
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        selectedItemColor: c.accent,
        unselectedItemColor: c.textSecondary,
        backgroundColor: c.surface,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_month_outlined),
            activeIcon: Icon(Icons.calendar_month),
            label: '노트',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.search_outlined),
            activeIcon: Icon(Icons.search),
            label: '검색',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: '설정',
          ),
        ],
      ),
    );
  }
}
