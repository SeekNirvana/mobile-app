import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum JournalEntryType { dream, reflection, idea }

@immutable
class JournalEntry {
  final String id;
  final JournalEntryType type;
  final String title;
  final String content;
  final List<String> tags;
  final String? novaAnalysis;
  final DateTime? novaAnalysisUpdatedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const JournalEntry({
    required this.id,
    required this.type,
    required this.title,
    required this.content,
    required this.tags,
    this.novaAnalysis,
    this.novaAnalysisUpdatedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  JournalEntry copyWith({
    String? id,
    JournalEntryType? type,
    String? title,
    String? content,
    List<String>? tags,
    String? novaAnalysis,
    DateTime? novaAnalysisUpdatedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return JournalEntry(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      content: content ?? this.content,
      tags: tags ?? this.tags,
      novaAnalysis: novaAnalysis ?? this.novaAnalysis,
      novaAnalysisUpdatedAt:
          novaAnalysisUpdatedAt ?? this.novaAnalysisUpdatedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'type': type.name,
    'title': title,
    'content': content,
    'tags': tags,
    'novaAnalysis': novaAnalysis,
    'novaAnalysisUpdatedAt': novaAnalysisUpdatedAt?.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory JournalEntry.fromMap(Map<String, dynamic> map) {
    final typeName = map['type'] as String? ?? JournalEntryType.reflection.name;
    return JournalEntry(
      id: map['id'] as String? ?? '',
      type: JournalEntryType.values.firstWhere(
        (value) => value.name == typeName,
        orElse: () => JournalEntryType.reflection,
      ),
      title: map['title'] as String? ?? '',
      content: map['content'] as String? ?? '',
      tags: ((map['tags'] as List?) ?? const [])
          .whereType<Object?>()
          .map((value) => value.toString())
          .where((value) => value.trim().isNotEmpty)
          .toList(),
      novaAnalysis: map['novaAnalysis'] as String?,
      novaAnalysisUpdatedAt: DateTime.tryParse(
        map['novaAnalysisUpdatedAt'] as String? ?? '',
      ),
      createdAt:
          DateTime.tryParse(map['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(map['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class JournalService extends ChangeNotifier {
  static const _entriesKey = 'journal_entries_v1';

  Future<void>? _initFuture;
  final List<JournalEntry> _entries = [];

  List<JournalEntry> get entries => List.unmodifiable(_entries);

  Future<void> init() {
    return _initFuture ??= _initialize();
  }

  Future<void> _initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_entriesKey);
    if (raw == null || raw.isEmpty) {
      notifyListeners();
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        _entries
          ..clear()
          ..addAll(
            decoded.whereType<Map>().map(
              (item) => JournalEntry.fromMap(Map<String, dynamic>.from(item)),
            ),
          )
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      }
    } catch (error) {
      debugPrint('[JournalService] Failed to decode entries: $error');
    }
    notifyListeners();
  }

  Future<JournalEntry> saveEntry({
    String? id,
    required JournalEntryType type,
    required String title,
    required String content,
    List<String> tags = const [],
    String? novaAnalysis,
  }) async {
    await init();

    final now = DateTime.now();
    final formattedContent = formatEntryContent(content);
    final formattedTitle = formatEntryTitle(
      title: title,
      content: formattedContent,
      type: type,
    );
    final formattedTags = _normalizeTags(tags, formattedContent);

    final nextEntry = JournalEntry(
      id: id ?? _newId(),
      type: type,
      title: formattedTitle,
      content: formattedContent,
      tags: formattedTags,
      novaAnalysis: novaAnalysis ?? entryById(id ?? '')?.novaAnalysis,
      novaAnalysisUpdatedAt: novaAnalysis != null
          ? now
          : entryById(id ?? '')?.novaAnalysisUpdatedAt,
      createdAt: id == null ? now : _existingCreatedAt(id) ?? now,
      updatedAt: now,
    );

    final index = _entries.indexWhere((entry) => entry.id == nextEntry.id);
    if (index >= 0) {
      _entries[index] = nextEntry;
    } else {
      _entries.add(nextEntry);
    }
    _entries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await _persist();
    notifyListeners();
    return nextEntry;
  }

  Future<void> deleteEntry(String id) async {
    await init();
    _entries.removeWhere((entry) => entry.id == id);
    await _persist();
    notifyListeners();
  }

  Future<JournalEntry?> updateNovaAnalysis({
    required String entryId,
    required String analysis,
  }) async {
    await init();
    final existing = entryById(entryId);
    if (existing == null) return null;
    final updated = existing.copyWith(
      novaAnalysis: analysis.trim(),
      novaAnalysisUpdatedAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    final index = _entries.indexWhere((entry) => entry.id == entryId);
    if (index >= 0) {
      _entries[index] = updated;
      _entries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      await _persist();
      notifyListeners();
    }
    return updated;
  }

  JournalEntry? entryById(String id) {
    try {
      return _entries.firstWhere((entry) => entry.id == id);
    } catch (_) {
      return null;
    }
  }

  static String formatEntryContent(String raw) {
    final lines = raw
        .replaceAll('\r\n', '\n')
        .split('\n')
        .map((line) => line.trimRight())
        .toList();

    final normalized = <String>[];
    var previousBlank = false;
    for (final line in lines) {
      final cleaned = line.trimLeft();
      final isBlank = cleaned.isEmpty;
      if (isBlank) {
        if (!previousBlank && normalized.isNotEmpty) {
          normalized.add('');
        }
        previousBlank = true;
        continue;
      }

      final sentence = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
      normalized.add(sentence);
      previousBlank = false;
    }

    return normalized.join('\n').trim();
  }

  static String formatEntryTitle({
    required String title,
    required String content,
    required JournalEntryType type,
  }) {
    final trimmed = title.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }

    final firstLine = content
        .split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    if (firstLine.isNotEmpty) {
      return firstLine.length <= 48
          ? firstLine
          : '${firstLine.substring(0, 45).trimRight()}...';
    }

    switch (type) {
      case JournalEntryType.dream:
        return 'Untitled dream';
      case JournalEntryType.reflection:
        return 'Mindful reflection';
      case JournalEntryType.idea:
        return 'Mindful idea';
    }
  }

  DateTime? _existingCreatedAt(String id) {
    for (final entry in _entries) {
      if (entry.id == id) {
        return entry.createdAt;
      }
    }
    return null;
  }

  List<String> _normalizeTags(List<String> tags, String content) {
    final normalized = <String>{};
    for (final tag in tags) {
      final cleaned = tag.trim().toLowerCase();
      if (cleaned.isNotEmpty) {
        normalized.add(cleaned);
      }
    }

    if (normalized.isEmpty && content.isNotEmpty) {
      final text = content.toLowerCase();
      if (text.contains('lucid') || text.contains('dream')) {
        normalized.add('dream');
      }
      if (text.contains('gratitude')) {
        normalized.add('gratitude');
      }
      if (text.contains('anxious') || text.contains('stress')) {
        normalized.add('stress');
      }
      if (text.contains('calm') || text.contains('peace')) {
        normalized.add('calm');
      }
    }

    return normalized.toList()..sort();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode(_entries.map((entry) => entry.toMap()).toList());
    await prefs.setString(_entriesKey, payload);
  }

  String _newId() => 'journal-${DateTime.now().microsecondsSinceEpoch}';
}

final journalServiceProvider = ChangeNotifierProvider<JournalService>((ref) {
  final service = JournalService();
  service.init();
  ref.onDispose(service.dispose);
  return service;
});
