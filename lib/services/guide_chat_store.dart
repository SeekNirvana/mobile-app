import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'guide_model_manager.dart';

enum GuideChatMessageRole { user, guide }

@immutable
class GuideChatMessage {
  final String id;
  final GuideChatMessageRole role;
  final String text;
  final DateTime timestamp;

  const GuideChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.timestamp,
  });

  bool get fromGuide => role == GuideChatMessageRole.guide;
}

@immutable
class GuideChatSession {
  final String id;
  final GuideKind guide;
  final String title;
  final bool userNamed;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<GuideChatMessage> messages;

  const GuideChatSession({
    required this.id,
    required this.guide,
    required this.title,
    required this.userNamed,
    required this.createdAt,
    required this.updatedAt,
    required this.messages,
  });

  GuideChatSession copyWith({
    String? id,
    GuideKind? guide,
    String? title,
    bool? userNamed,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<GuideChatMessage>? messages,
  }) {
    return GuideChatSession(
      id: id ?? this.id,
      guide: guide ?? this.guide,
      title: title ?? this.title,
      userNamed: userNamed ?? this.userNamed,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      messages: messages ?? this.messages,
    );
  }

  factory GuideChatSession.fromLegacyMap(Map<String, dynamic> map) {
    return GuideChatSession(
      id: map['id'] as String,
      guide: GuideKind.nova,
      title: map['title'] as String? ?? 'New chat',
      userNamed: (map['title'] as String? ?? 'New chat') != 'New chat',
      createdAt:
          DateTime.tryParse(map['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(map['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      messages: ((map['messages'] as List?) ?? const []).whereType<Map>().map((
        item,
      ) {
        final message = Map<String, dynamic>.from(item);
        return GuideChatMessage(
          id: message['id'] as String,
          role: (message['role'] as String?) == 'guide'
              ? GuideChatMessageRole.guide
              : GuideChatMessageRole.user,
          text: message['text'] as String? ?? '',
          timestamp:
              DateTime.tryParse(message['timestamp'] as String? ?? '') ??
              DateTime.now(),
        );
      }).toList(),
    );
  }
}

class GuideChatStore extends ChangeNotifier {
  static const _selectedSessionIdKey = 'guide_chat_selected_session_id_v2';
  static const _legacySelectedSessionIdKey =
      'guide_chat_selected_session_id_v1';
  static const _legacySessionsKey = 'guide_chat_sessions_v1';

  final GuideModelManager _modelManager;

  Database? _database;
  Future<void>? _initFuture;
  String? _databasePath;
  String? _observedStorageRoot;
  final List<GuideChatSession> _sessions = [];
  GuideKind _selectedGuide = GuideKind.nova;
  String? _selectedSessionId;

  GuideChatStore({required GuideModelManager modelManager})
    : _modelManager = modelManager {
    _modelManager.addListener(_handleModelStorageChanged);
  }

  List<GuideChatSession> get sessions => List.unmodifiable(_sessions);

  GuideKind get selectedGuide => _selectedGuide;

  String? get selectedSessionId => _selectedSessionId;

  GuideChatSession? get currentSession {
    final id = _selectedSessionId;
    if (id == null) return null;
    for (final session in _sessions) {
      if (session.id == id && session.guide == _selectedGuide) return session;
    }
    // If no session for current guide, return null to trigger creation
    return null;
  }

  Future<void> init() => _initFuture ??= _initialize();

  Future<void> _initialize() async {
    try {
      // Don't auto-init manager here - let the provider handle it
      // This prevents circular initialization issues
      if (_modelManager.storageDirectoryPath == null) {
        await _modelManager.init();
      }

      final prefs = await SharedPreferences.getInstance();
      _selectedSessionId =
          prefs.getString(_selectedSessionIdKey) ??
          prefs.getString(_legacySelectedSessionIdKey);

      await _openDatabaseForCurrentStorage();
      await _maybeMigrateLegacyPrefs(prefs);
      await _loadSessionsFromDatabase();

      if (_sessions.isEmpty) {
        // Don't auto-create session - let UI handle it
        _ensureValidSelection();
      } else {
        _ensureValidSelection();
      }
    } catch (e, stack) {
      debugPrint('GuideChatStore initialization error: $e\n$stack');
      // Still notify listeners so UI shows error state instead of infinite loading
    }
    try {
      notifyListeners();
    } catch (_) {
      // Ignore if disposed
    }
  }

  List<GuideChatSession> sessionsForGuide(GuideKind guide) {
    final filtered = _sessions.where((s) => s.guide == guide).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return filtered;
  }

  void selectGuide(GuideKind guide) {
    if (_selectedGuide == guide) return;
    _selectedGuide = guide;

    // Filter sessions for this guide and select the most recent one
    final guideSessions = sessionsForGuide(guide);
    if (guideSessions.isNotEmpty) {
      _selectedSessionId = guideSessions.first.id;
    } else {
      // No session for this guide - clear selection
      // UI will show "download model" or "start chat" prompt
      _selectedSessionId = null;
    }
    notifyListeners();
  }

  void selectSession(String sessionId) {
    final session = _sessions.cast<GuideChatSession?>().firstWhere(
      (item) => item?.id == sessionId,
      orElse: () => null,
    );
    if (session == null) return;
    _selectedSessionId = session.id;
    unawaited(_saveSelection());
    notifyListeners();
  }

  Future<GuideChatSession> startNewSession({GuideKind? guide}) async {
    await init();
    final targetGuide = guide ?? _selectedGuide;
    final session = _createSeedSession(targetGuide);

    await _database!.transaction((txn) async {
      await _insertSession(txn, session);
      for (var index = 0; index < session.messages.length; index++) {
        await _insertMessage(txn, session.id, session.messages[index], index);
      }
    });

    _sessions.add(session);
    _selectedSessionId = session.id;
    await _saveSelection();
    notifyListeners();
    return session;
  }

  Future<void> renameSession({
    required String sessionId,
    required String title,
  }) async {
    await init();
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;

    final session = _sessionById(sessionId);
    if (session == null) return;

    final updatedSession = session.copyWith(
      title: trimmed,
      userNamed: true,
      updatedAt: DateTime.now(),
    );

    await _database!.transaction((txn) async {
      await _updateSession(txn, updatedSession);
    });

    _replaceSession(updatedSession);
    notifyListeners();
  }

  Future<void> deleteSession(String sessionId) async {
    await init();
    final session = _sessionById(sessionId);
    if (session == null) return;

    await _database!.transaction((txn) async {
      await txn.delete('sessions', where: 'id = ?', whereArgs: [sessionId]);
    });

    _sessions.removeWhere((item) => item.id == sessionId);
    if (_selectedSessionId == sessionId) {
      final guideSessions = sessionsForGuide(session.guide);
      _selectedSessionId = guideSessions.isNotEmpty
          ? guideSessions.first.id
          : null;
    }
    _ensureValidSelection();
    await _saveSelection();
    notifyListeners();
  }

  Future<void> clearSessions({GuideKind? guide}) async {
    await init();
    final targetGuide = guide;

    await _database!.transaction((txn) async {
      if (targetGuide == null) {
        await txn.delete('sessions');
      } else {
        await txn.delete(
          'sessions',
          where: 'guide = ?',
          whereArgs: [targetGuide.name],
        );
      }
    });

    if (targetGuide == null) {
      _sessions.clear();
    } else {
      _sessions.removeWhere((session) => session.guide == targetGuide);
    }

    _selectedSessionId = null;
    _ensureValidSelection();
    await _saveSelection();
    notifyListeners();
  }

  @override
  void dispose() {
    _modelManager.removeListener(_handleModelStorageChanged);
    unawaited(_database?.close());
    super.dispose();
  }

  Future<void> _handleModelStorageChanged() async {
    final nextRoot = _modelManager.storageDirectoryPath;
    if (nextRoot == _observedStorageRoot) return;

    try {
      await _openDatabaseForCurrentStorage();
      await _loadSessionsFromDatabase();
      if (_sessions.isEmpty) {
        await startNewSession();
      } else {
        _ensureValidSelection();
        notifyListeners();
      }
    } catch (_) {
      notifyListeners();
    }
  }

  Future<void> _openDatabaseForCurrentStorage() async {
    await _modelManager.init();
    final targetPath = _modelManager.chatDatabasePath;
    if (targetPath == null || targetPath.isEmpty) {
      throw StateError('Chat database path is not available yet.');
    }

    if (_database != null && _databasePath == targetPath) {
      _observedStorageRoot = _modelManager.storageDirectoryPath;
      return;
    }

    await Directory(p.dirname(targetPath)).create(recursive: true);

    final previousDbPath = _databasePath;
    if (previousDbPath != null &&
        previousDbPath != targetPath &&
        await File(previousDbPath).exists() &&
        !await File(targetPath).exists()) {
      await File(previousDbPath).copy(targetPath);
    }

    await _database?.close();
    _database = await openDatabase(
      targetPath,
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE sessions (
            id TEXT PRIMARY KEY,
            guide TEXT NOT NULL,
            title TEXT NOT NULL,
            user_named INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE messages (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            role TEXT NOT NULL,
            text TEXT NOT NULL,
            created_at TEXT NOT NULL,
            sort_order INTEGER NOT NULL,
            FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE
          )
        ''');
        await db.execute(
          'CREATE INDEX messages_session_order_idx ON messages(session_id, sort_order)',
        );
        await db.execute(
          'CREATE INDEX sessions_updated_idx ON sessions(updated_at DESC)',
        );
      },
    );
    _databasePath = targetPath;
    _observedStorageRoot = _modelManager.storageDirectoryPath;
  }

  Future<void> _loadSessionsFromDatabase() async {
    final db = _database;
    if (db == null) return;

    final sessionRows = await db.query('sessions', orderBy: 'updated_at DESC');
    final loadedSessions = <GuideChatSession>[];

    for (final row in sessionRows) {
      final sessionId = row['id'] as String;
      final messageRows = await db.query(
        'messages',
        where: 'session_id = ?',
        whereArgs: [sessionId],
        orderBy: 'sort_order ASC',
      );
      final messages = messageRows.map(_messageFromRow).toList();
      loadedSessions.add(
        GuideChatSession(
          id: sessionId,
          guide: _parseGuideKind(row['guide'] as String?),
          title: row['title'] as String? ?? 'New chat',
          userNamed: ((row['user_named'] as int?) ?? 0) == 1,
          createdAt:
              DateTime.tryParse(row['created_at'] as String? ?? '') ??
              DateTime.now(),
          updatedAt:
              DateTime.tryParse(row['updated_at'] as String? ?? '') ??
              DateTime.now(),
          messages: messages,
        ),
      );
    }

    _sessions
      ..clear()
      ..addAll(loadedSessions);
    _ensureValidSelection();
  }

  Future<void> _maybeMigrateLegacyPrefs(SharedPreferences prefs) async {
    final legacyJson = prefs.getString(_legacySessionsKey);
    if (legacyJson == null || legacyJson.isEmpty || _database == null) return;

    final existing = await _database!.query(
      'sessions',
      columns: ['id'],
      limit: 1,
    );
    if (existing.isNotEmpty) return;

    final decoded = jsonDecode(legacyJson);
    if (decoded is! List) return;

    final legacySessions = decoded
        .whereType<Map>()
        .map(
          (item) =>
              GuideChatSession.fromLegacyMap(Map<String, dynamic>.from(item)),
        )
        .toList();

    await _database!.transaction((txn) async {
      for (final session in legacySessions) {
        await _insertSession(txn, session);
        for (var index = 0; index < session.messages.length; index++) {
          await _insertMessage(txn, session.id, session.messages[index], index);
        }
      }
    });
  }

  Future<void> _insertSession(
    DatabaseExecutor db,
    GuideChatSession session,
  ) async {
    await db.insert('sessions', {
      'id': session.id,
      'guide': session.guide.name,
      'title': session.title,
      'user_named': session.userNamed ? 1 : 0,
      'created_at': session.createdAt.toIso8601String(),
      'updated_at': session.updatedAt.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _insertMessage(
    DatabaseExecutor db,
    String sessionId,
    GuideChatMessage message,
    int sortOrder,
  ) async {
    await db.insert('messages', {
      'id': message.id,
      'session_id': sessionId,
      'role': message.role.name,
      'text': message.text,
      'created_at': message.timestamp.toIso8601String(),
      'sort_order': sortOrder,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _updateSession(
    DatabaseExecutor db,
    GuideChatSession session,
  ) async {
    await db.update(
      'sessions',
      {
        'guide': session.guide.name,
        'title': session.title,
        'user_named': session.userNamed ? 1 : 0,
        'created_at': session.createdAt.toIso8601String(),
        'updated_at': session.updatedAt.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [session.id],
    );
  }

  GuideChatMessage _messageFromRow(Map<String, Object?> row) {
    return GuideChatMessage(
      id: row['id'] as String,
      role: (row['role'] as String) == GuideChatMessageRole.guide.name
          ? GuideChatMessageRole.guide
          : GuideChatMessageRole.user,
      text: row['text'] as String? ?? '',
      timestamp:
          DateTime.tryParse(row['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  GuideChatSession _createSeedSession(GuideKind guide) {
    final persona = guidePersonaDefinitions[guide]!;
    final now = DateTime.now();
    return GuideChatSession(
      id: _newId('session'),
      guide: guide,
      title: 'New chat',
      userNamed: false,
      createdAt: now,
      updatedAt: now,
      messages: [
        GuideChatMessage(
          id: _newId('message'),
          role: GuideChatMessageRole.guide,
          text: persona.starterMessage,
          timestamp: now,
        ),
      ],
    );
  }

  void _ensureValidSelection() {
    final current = currentSession;
    if (current != null) return;

    // Try to find a session for the current guide
    final guideSessions = sessionsForGuide(_selectedGuide);
    if (guideSessions.isNotEmpty) {
      _selectedSessionId = guideSessions.first.id;
    } else if (_sessions.isNotEmpty) {
      // Fallback to any session (for migration/upgrade scenarios)
      _selectedSessionId = _sessions.first.id;
    } else {
      _selectedSessionId = null;
    }
  }

  GuideChatSession? _sessionById(String sessionId) {
    for (final session in _sessions) {
      if (session.id == sessionId) return session;
    }
    return null;
  }

  GuideChatSession? _sessionContainingMessage(String messageId) {
    for (final session in _sessions) {
      if (session.messages.any((message) => message.id == messageId)) {
        return session;
      }
    }
    return null;
  }

  void _replaceSession(GuideChatSession updatedSession) {
    final index = _sessions.indexWhere((item) => item.id == updatedSession.id);
    if (index >= 0) {
      _sessions[index] = updatedSession;
    } else {
      _sessions.add(updatedSession);
    }
    _sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<void> _saveSelection() async {
    final prefs = await SharedPreferences.getInstance();
    if (_selectedSessionId != null) {
      await prefs.setString(_selectedSessionIdKey, _selectedSessionId!);
    } else {
      await prefs.remove(_selectedSessionIdKey);
    }
  }

  String _newId(String prefix) {
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}';
  }

  /// Send a message in the current session
  Future<void> sendMessage(String text) async {
    final session = currentSession;
    if (session == null || text.trim().isEmpty) return;

    await init();

    final now = DateTime.now();
    final userMessage = GuideChatMessage(
      id: _newId('message'),
      role: GuideChatMessageRole.user,
      text: text.trim(),
      timestamp: now,
    );

    // Add user message to session
    final updatedMessages = [...session.messages, userMessage];
    final shouldGenerateTitle =
        !session.userNamed &&
        !session.messages.any(
          (message) => message.role == GuideChatMessageRole.user,
        );
    final updatedSession = session.copyWith(
      title: shouldGenerateTitle
          ? _deriveSessionTitle(userMessage.text)
          : session.title,
      messages: updatedMessages,
      updatedAt: now,
    );

    await _database!.transaction((txn) async {
      await _insertMessage(
        txn,
        session.id,
        userMessage,
        updatedMessages.length - 1,
      );
      await _updateSession(txn, updatedSession);
    });

    _replaceSession(updatedSession);
    notifyListeners();
  }

  String _deriveSessionTitle(String text) {
    final singleLine = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (singleLine.isEmpty) {
      return 'New chat';
    }

    const maxLength = 42;
    if (singleLine.length <= maxLength) {
      return singleLine;
    }

    return '${singleLine.substring(0, maxLength - 1).trimRight()}…';
  }

  /// Add a guide response to the current session
  Future<void> addGuideResponse(String text) async {
    final session = currentSession;
    if (session == null || text.trim().isEmpty) return;

    await init();

    final now = DateTime.now();
    final guideMessage = GuideChatMessage(
      id: _newId('message'),
      role: GuideChatMessageRole.guide,
      text: text.trim(),
      timestamp: now,
    );

    final updatedMessages = [...session.messages, guideMessage];
    final updatedSession = session.copyWith(
      messages: updatedMessages,
      updatedAt: now,
    );

    await _database!.transaction((txn) async {
      await _insertMessage(
        txn,
        session.id,
        guideMessage,
        updatedMessages.length - 1,
      );
      await _updateSession(txn, updatedSession);
    });

    _replaceSession(updatedSession);
    notifyListeners();
  }

  Future<String?> beginGuideResponseDraft() async {
    final session = currentSession;
    if (session == null) return null;

    await init();

    final now = DateTime.now();
    final guideMessage = GuideChatMessage(
      id: _newId('message'),
      role: GuideChatMessageRole.guide,
      text: '',
      timestamp: now,
    );

    final updatedMessages = [...session.messages, guideMessage];
    final updatedSession = session.copyWith(
      messages: updatedMessages,
      updatedAt: now,
    );

    await _database!.transaction((txn) async {
      await _insertMessage(
        txn,
        session.id,
        guideMessage,
        updatedMessages.length - 1,
      );
      await _updateSession(txn, updatedSession);
    });

    _replaceSession(updatedSession);
    notifyListeners();
    return guideMessage.id;
  }

  Future<void> updateGuideResponseDraft(
    String messageId,
    String text, {
    bool persist = false,
  }) async {
    await init();

    final session = _sessionContainingMessage(messageId);
    if (session == null) return;

    final messageIndex = session.messages.indexWhere((m) => m.id == messageId);
    if (messageIndex < 0) return;

    final existingMessage = session.messages[messageIndex];
    final updatedMessage = GuideChatMessage(
      id: existingMessage.id,
      role: existingMessage.role,
      text: text,
      timestamp: existingMessage.timestamp,
    );

    final updatedMessages = [...session.messages];
    updatedMessages[messageIndex] = updatedMessage;

    final updatedSession = session.copyWith(
      messages: updatedMessages,
      updatedAt: DateTime.now(),
    );

    if (persist) {
      await _database!.transaction((txn) async {
        await txn.update(
          'messages',
          {'text': text},
          where: 'id = ?',
          whereArgs: [messageId],
        );
        await _updateSession(txn, updatedSession);
      });
    }

    _replaceSession(updatedSession);
    notifyListeners();
  }

  Future<void> completeGuideResponseDraft(String messageId, String text) async {
    await updateGuideResponseDraft(messageId, text, persist: true);
  }

  Future<void> removeGuideResponseDraft(String messageId) async {
    await init();

    final session = _sessionContainingMessage(messageId);
    if (session == null) return;

    final messageIndex = session.messages.indexWhere((m) => m.id == messageId);
    if (messageIndex < 0) return;

    final updatedMessages = [...session.messages]..removeAt(messageIndex);
    final updatedSession = session.copyWith(
      messages: updatedMessages,
      updatedAt: DateTime.now(),
    );

    await _database!.transaction((txn) async {
      await txn.delete('messages', where: 'id = ?', whereArgs: [messageId]);
      await _updateSession(txn, updatedSession);
    });

    _replaceSession(updatedSession);
    notifyListeners();
  }
}

final guideChatStoreProvider = ChangeNotifierProvider<GuideChatStore>((ref) {
  // Use read (not watch) to avoid provider invalidation when manager notifies
  final manager = ref.read(guideModelManagerProvider);
  final store = GuideChatStore(modelManager: manager);
  // Initialize after provider setup to avoid disposal during init
  Future.microtask(() => store.init());
  ref.onDispose(() {
    try {
      store.dispose();
    } catch (_) {
      // Ignore disposal errors
    }
  });
  return store;
});

GuideKind _parseGuideKind(String? raw) {
  if (raw == null || raw.isEmpty) {
    return GuideKind.nova;
  }

  for (final kind in GuideKind.values) {
    if (kind.name == raw) {
      return kind;
    }
  }

  return GuideKind.nova;
}
