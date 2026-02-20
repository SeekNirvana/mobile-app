import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sleep record with timestamp
class SleepRecord {
  final int timestamp; // Unix timestamp in seconds
  final int sleepType; // 1=Light, 2=Deep, 3=Awake, 4=REM
  final int heartRate;
  final int? bloodOxygen;
  final int? temperature;
  final int? hrv;
  final int? stress;

  SleepRecord({
    required this.timestamp,
    required this.sleepType,
    this.heartRate = 0,
    this.bloodOxygen,
    this.temperature,
    this.hrv,
    this.stress,
  });

  factory SleepRecord.fromMap(Map<String, dynamic> map) {
    return SleepRecord(
      timestamp: map['time'] ?? map['timestamp'] ?? 0,
      sleepType: map['sleepType'] ?? 0,
      heartRate: map['heartRate'] ?? map['hr'] ?? 0,
      bloodOxygen: map['bloodOxygen'] ?? map['spo2'],
      temperature: map['temperature'] ?? map['temp'],
      hrv: map['hrv'] ?? map['heartRateVariability'],
      stress: map['stress'] ?? map['stressIndex'],
    );
  }

  Map<String, dynamic> toMap() => {
    'timestamp': timestamp,
    'sleepType': sleepType,
    'heartRate': heartRate,
    'bloodOxygen': bloodOxygen,
    'temperature': temperature,
    'hrv': hrv,
    'stress': stress,
  };

  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
  
  String get stageName {
    switch (sleepType) {
      case 1: return 'Light';
      case 2: return 'Deep';
      case 3: return 'Awake';
      case 4: return 'REM';
      default: return 'Unknown';
    }
  }
}

/// Sleep session summary for a specific night
class SleepSession {
  final DateTime date; // The date this sleep belongs to (typically the night of)
  final DateTime sleepStart;
  final DateTime sleepEnd;
  final int lightMinutes;
  final int deepMinutes;
  final int remMinutes;
  final int awakeMinutes;
  final List<SleepRecord> records;

  SleepSession({
    required this.date,
    required this.sleepStart,
    required this.sleepEnd,
    required this.lightMinutes,
    required this.deepMinutes,
    required this.remMinutes,
    required this.awakeMinutes,
    required this.records,
  });

  int get totalMinutes => lightMinutes + deepMinutes + remMinutes;
  double get durationHours => totalMinutes / 60.0;
  int get sleepEfficiency => totalMinutes > 0 
    ? ((totalMinutes / (totalMinutes + awakeMinutes)) * 100).round() 
    : 0;

  Map<String, dynamic> toMap() => {
    'date': date.toIso8601String(),
    'sleepStart': sleepStart.toIso8601String(),
    'sleepEnd': sleepEnd.toIso8601String(),
    'lightMinutes': lightMinutes,
    'deepMinutes': deepMinutes,
    'remMinutes': remMinutes,
    'awakeMinutes': awakeMinutes,
    'records': records.map((r) => r.toMap()).toList(),
  };

  factory SleepSession.fromMap(Map<String, dynamic> map) {
    return SleepSession(
      date: DateTime.parse(map['date']),
      sleepStart: DateTime.parse(map['sleepStart']),
      sleepEnd: DateTime.parse(map['sleepEnd']),
      lightMinutes: map['lightMinutes'] ?? 0,
      deepMinutes: map['deepMinutes'] ?? 0,
      remMinutes: map['remMinutes'] ?? 0,
      awakeMinutes: map['awakeMinutes'] ?? 0,
      records: (map['records'] as List?)
          ?.map((r) => SleepRecord.fromMap(r))
          .toList() ?? [],
    );
  }
}

/// Service for logging and retrieving sleep data
class SleepLogService {
  static const String _sleepDataKey = 'sleep_sessions_v2';
  static const String _rawLogKey = 'sleep_raw_log';
  
  // In-memory cache
  List<SleepSession> _cachedSessions = [];
  bool _initialized = false;

  /// Initialize and load cached data
  Future<void> init() async {
    if (_initialized) return;
    await _loadFromStorage();
    _initialized = true;
  }

  /// Load all sessions from local storage
  Future<void> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_sleepDataKey);
      if (jsonStr != null) {
        final List<dynamic> decoded = jsonDecode(jsonStr);
        _cachedSessions = decoded
            .map((m) => SleepSession.fromMap(m))
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date)); // Newest first
        debugPrint('[SleepLogService] Loaded ${_cachedSessions.length} sessions');
      }
    } catch (e) {
      debugPrint('[SleepLogService] Error loading: $e');
    }
  }

  /// Save all sessions to local storage
  Future<void> _saveToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(_cachedSessions.map((s) => s.toMap()).toList());
      await prefs.setString(_sleepDataKey, jsonStr);
    } catch (e) {
      debugPrint('[SleepLogService] Error saving: $e');
    }
  }

  /// Append raw history records to log file for debugging
  Future<void> appendRawLog(List<Map<String, dynamic>> records) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getString(_rawLogKey) ?? '';
      final timestamp = DateTime.now().toIso8601String();
      final newEntry = '\n=== $timestamp ===\n${jsonEncode(records)}\n';
      await prefs.setString(_rawLogKey, existing + newEntry);
      
      // Also write to file for easy access
      await _writeToFile('sleep_raw_log.txt', existing + newEntry);
    } catch (e) {
      debugPrint('[SleepLogService] Error appending raw log: $e');
    }
  }

  /// Write content to app documents file
  Future<void> _writeToFile(String filename, String content) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$filename');
      await file.writeAsString(content);
      debugPrint('[SleepLogService] Log written to: ${file.path}');
    } catch (e) {
      debugPrint('[SleepLogService] Error writing file: $e');
    }
  }

  /// Export all sleep data to a JSON file for analysis
  Future<String> exportLogFile() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/sleep_analysis.json');
      
      final exportData = {
        'exportDate': DateTime.now().toIso8601String(),
        'totalSessions': _cachedSessions.length,
        'sessions': _cachedSessions.map((s) => s.toMap()).toList(),
      };
      
      await file.writeAsString(jsonEncode(exportData));
      return file.path;
    } catch (e) {
      debugPrint('[SleepLogService] Error exporting: $e');
      return '';
    }
  }

  /// Process and store new sleep records from ring sync
  Future<void> processNewRecords(List<Map<String, dynamic>> records) async {
    await init();
    
    // Filter for sleep records only
    final sleepRecords = records
        .where((r) => (r['sleepType'] as int?) != null && (r['sleepType'] as int) > 0)
        .map((r) => SleepRecord.fromMap(r))
        .toList();

    if (sleepRecords.isEmpty) {
      debugPrint('[SleepLogService] No sleep records to process');
      return;
    }

    // Sort by timestamp
    sleepRecords.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // Group into sessions using gap detection
    final sessions = _detectSessions(sleepRecords);
    
    debugPrint('[SleepLogService] Detected ${sessions.length} sessions from ${sleepRecords.length} records');

    // Merge with existing sessions (avoid duplicates)
    for (final newSession in sessions) {
      _mergeSession(newSession);
    }

    await _saveToStorage();
    
    // Also append to raw log for debugging
    await appendRawLog(records);
  }

  /// Detect sleep sessions from records using gap detection
  List<SleepSession> _detectSessions(List<SleepRecord> records) {
    if (records.isEmpty) return [];

    const gapThresholdMinutes = 90;
    List<List<SleepRecord>> sessionGroups = [];
    List<SleepRecord> currentGroup = [records.first];

    for (int i = 1; i < records.length; i++) {
      final lastRecord = currentGroup.last;
      final currentRecord = records[i];
      final gapMinutes = (currentRecord.timestamp - lastRecord.timestamp) / 60;

      if (gapMinutes > gapThresholdMinutes) {
        sessionGroups.add(currentGroup);
        currentGroup = [currentRecord];
      } else {
        currentGroup.add(currentRecord);
      }
    }
    
    if (currentGroup.isNotEmpty) {
      sessionGroups.add(currentGroup);
    }

    // Convert groups to SleepSession objects
    return sessionGroups
        .where((group) => group.length >= 12) // At least 1 hour
        .map((group) => _createSessionFromRecords(group))
        .toList();
  }

  /// Create a SleepSession from a group of records
  SleepSession _createSessionFromRecords(List<SleepRecord> records) {
    int light = 0, deep = 0, rem = 0, awake = 0;

    for (final r in records) {
      switch (r.sleepType) {
        case 1: light += 5; break;
        case 2: deep += 5; break;
        case 3: awake += 5; break;
        case 4: rem += 5; break;
      }
    }

    final start = records.first.dateTime;
    final end = records.last.dateTime;
    
    // Determine the "sleep date" - if sleep started before 6 AM, count as previous day
    DateTime sleepDate = start;
    if (start.hour < 6) {
      sleepDate = start.subtract(const Duration(days: 1));
    }
    // Normalize to just the date
    sleepDate = DateTime(sleepDate.year, sleepDate.month, sleepDate.day);

    return SleepSession(
      date: sleepDate,
      sleepStart: start,
      sleepEnd: end,
      lightMinutes: light,
      deepMinutes: deep,
      remMinutes: rem,
      awakeMinutes: awake,
      records: records,
    );
  }

  /// Merge a new session with existing (update if same date, add if new)
  void _mergeSession(SleepSession newSession) {
    final existingIndex = _cachedSessions.indexWhere(
      (s) => _isSameDay(s.date, newSession.date)
    );

    if (existingIndex >= 0) {
      // Replace if new session is longer
      final existing = _cachedSessions[existingIndex];
      if (newSession.totalMinutes > existing.totalMinutes) {
        _cachedSessions[existingIndex] = newSession;
        debugPrint('[SleepLogService] Updated session for ${newSession.date.toIso8601String()}');
      }
    } else {
      _cachedSessions.add(newSession);
      _cachedSessions.sort((a, b) => b.date.compareTo(a.date));
      debugPrint('[SleepLogService] Added new session for ${newSession.date.toIso8601String()}');
    }
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// Get sleep session for a specific date
  SleepSession? getSessionForDate(DateTime date) {
    final target = DateTime(date.year, date.month, date.day);
    return _cachedSessions.cast<SleepSession?>().firstWhere(
      (s) => s != null && _isSameDay(s.date, target),
      orElse: () => null,
    );
  }

  /// Get all sessions for a date range
  List<SleepSession> getSessionsForRange(DateTime start, DateTime end) {
    return _cachedSessions.where((s) {
      return s.date.isAfter(start.subtract(const Duration(days: 1))) &&
             s.date.isBefore(end.add(const Duration(days: 1)));
    }).toList();
  }

  /// Get last N days of sessions
  List<SleepSession> getLastNDays(int days) {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    return _cachedSessions
        .where((s) => s.date.isAfter(cutoff))
        .toList();
  }

  /// Get today's session
  SleepSession? getTodaySession() => getSessionForDate(DateTime.now());

  /// Get yesterday's session
  SleepSession? getYesterdaySession() {
    return getSessionForDate(DateTime.now().subtract(const Duration(days: 1)));
  }

  /// Get last 7 days sessions
  List<SleepSession> getLastWeekSessions() => getLastNDays(7);

  /// Get last 30 days sessions
  List<SleepSession> getLastMonthSessions() => getLastNDays(30);

  /// Get all sessions (newest first)
  List<SleepSession> getAllSessions() => List.unmodifiable(_cachedSessions);

  /// Get average stats for a list of sessions
  Map<String, dynamic> getAverageStats(List<SleepSession> sessions) {
    if (sessions.isEmpty) return {};

    final totalLight = sessions.fold<int>(0, (sum, s) => sum + s.lightMinutes);
    final totalDeep = sessions.fold<int>(0, (sum, s) => sum + s.deepMinutes);
    final totalRem = sessions.fold<int>(0, (sum, s) => sum + s.remMinutes);
    final totalAwake = sessions.fold<int>(0, (sum, s) => sum + s.awakeMinutes);
    final totalDuration = sessions.fold<double>(0, (sum, s) => sum + s.durationHours);

    final count = sessions.length;
    return {
      'avgLightMinutes': totalLight ~/ count,
      'avgDeepMinutes': totalDeep ~/ count,
      'avgRemMinutes': totalRem ~/ count,
      'avgAwakeMinutes': totalAwake ~/ count,
      'avgDurationHours': totalDuration / count,
      'totalSessions': count,
    };
  }

  /// Clear all data (for debugging)
  Future<void> clearAll() async {
    _cachedSessions = [];
    await _saveToStorage();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_rawLogKey);
  }
}

// Global singleton instance
final sleepLogService = SleepLogService();
