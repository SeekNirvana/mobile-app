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
      case 1: return 'Awake';  // SDK: 1 = 清醒
      case 2: return 'Light';  // SDK: 2 = 浅睡
      case 3: return 'Deep';   // SDK: 3 = 深睡
      case 4: return 'REM';    // SDK: 4 = 眼动期
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
    
    // Convert ALL records to SleepRecords (including sleepType=0) so that
    // session detection sees continuous timestamps. Filtering sleepType=0
    // before gap detection was creating artificial gaps that split sessions.
    final allRecords = records
        .where((r) => (r['sleepType'] as int?) != null && (r['time'] as int?) != null)
        .map((r) => SleepRecord.fromMap(r))
        .where((r) => r.timestamp > 0)
        .toList();

    if (allRecords.isEmpty) {
      debugPrint('[SleepLogService] No records to process');
      return;
    }

    // Sort by timestamp
    allRecords.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    // Log distribution for debugging
    final typeCounts = <int, int>{};
    for (final r in allRecords) {
      typeCounts[r.sleepType] = (typeCounts[r.sleepType] ?? 0) + 1;
    }
    final firstDt = allRecords.first.dateTime;
    final lastDt = allRecords.last.dateTime;
    debugPrint('[SleepLogService] Record distribution: $typeCounts '
        '(total=${allRecords.length}, '
        'span=${firstDt.toLocal()} → ${lastDt.toLocal()}, '
        'tz=${firstDt.timeZoneName}, '
        'rawFirst=${allRecords.first.timestamp}, rawLast=${allRecords.last.timestamp})');
    // Log first few records for timestamp debugging
    for (int i = 0; i < allRecords.length && i < 5; i++) {
      final r = allRecords[i];
      debugPrint('[SleepLogService] Sample[$i]: ts=${r.timestamp} → ${r.dateTime.toLocal()} sleep=${r.sleepType} hr=${r.heartRate}');
    }

    // Group into sessions using gap detection on ALL records
    final sessions = _detectSessions(allRecords);
    
    debugPrint('[SleepLogService] Detected ${sessions.length} sessions from ${allRecords.length} records');

    // Merge with existing sessions (avoid duplicates)
    for (final newSession in sessions) {
      _mergeSession(newSession);
    }

    await _saveToStorage();
    
    // Also append to raw log for debugging
    await appendRawLog(records);
  }

  /// Detect sleep sessions from records using gap detection.
  /// Uses ALL records (including sleepType=0) to maintain timestamp continuity.
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
    // Only require that the group has >= 6 sleep records (sleepType > 0)
    // to qualify as a sleep session
    return sessionGroups
        .where((group) {
          final sleepCount = group.where((r) => r.sleepType > 0).length;
          return sleepCount >= 6; // At least ~30 min of actual sleep data
        })
        .map((group) => _createSessionFromRecords(group))
        .toList();
  }

  /// Create a SleepSession from a group of records.
  /// Records may include sleepType=0 (invalid) for continuity —
  /// only sleepType > 0 records contribute to stage durations.
  SleepSession _createSessionFromRecords(List<SleepRecord> records) {
    int light = 0, deep = 0, rem = 0, awake = 0;

    // Calculate duration from actual timestamps between consecutive records
    for (int i = 0; i < records.length; i++) {
      // Skip sleepType=0 (invalid/not-wearing) for duration accumulation
      if (records[i].sleepType == 0) continue;

      int durationSec;
      // Look forward to the next record for delta
      if (i < records.length - 1) {
        durationSec = records[i + 1].timestamp - records[i].timestamp;
        // Cap at 15 min (900s) to handle unexpected gaps; fall back to 5 min
        if (durationSec <= 0 || durationSec > 900) durationSec = 300;
      } else {
        // Last record: use the same interval as the previous gap, or 5 min
        if (i > 0) {
          final prevGap = records[i].timestamp - records[i - 1].timestamp;
          durationSec = (prevGap > 0 && prevGap <= 900) ? prevGap : 300;
        } else {
          durationSec = 300;
        }
      }
      final mins = (durationSec / 60).round();

      // SDK sleep type mapping:
      //   1 = Awake (清醒), 2 = Light (浅睡), 3 = Deep (深睡), 4 = REM (眼动期)
      switch (records[i].sleepType) {
        case 1: awake += mins; break;
        case 2: light += mins; break;
        case 3: deep  += mins; break;
        case 4: rem   += mins; break;
      }
    }

    // Find the first and last actual sleep records for start/end times
    final sleepRecords = records.where((r) => r.sleepType > 0).toList();
    final start = sleepRecords.isNotEmpty ? sleepRecords.first.dateTime : records.first.dateTime;
    final end = sleepRecords.isNotEmpty ? sleepRecords.last.dateTime : records.last.dateTime;
    
    // Determine the "sleep date" - if sleep started before 6 AM, count as previous day
    DateTime sleepDate = start;
    if (start.hour < 6) {
      sleepDate = start.subtract(const Duration(days: 1));
    }
    // Normalize to just the date
    sleepDate = DateTime(sleepDate.year, sleepDate.month, sleepDate.day);

    debugPrint('[SleepLogService] Session: ${start.toLocal()} → ${end.toLocal()}, '
        'light=${light}m deep=${deep}m rem=${rem}m awake=${awake}m '
        'total=${light + deep + rem}m (${((light + deep + rem) / 60.0).toStringAsFixed(1)}h), '
        'records=${records.length}, sleepRecords=${sleepRecords.length}');

    return SleepSession(
      date: sleepDate,
      sleepStart: start,
      sleepEnd: end,
      lightMinutes: light,
      deepMinutes: deep,
      remMinutes: rem,
      awakeMinutes: awake,
      records: sleepRecords, // Only store sleep records for timeline display
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
