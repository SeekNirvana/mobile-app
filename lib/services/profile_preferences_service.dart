import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_constants.dart';

class ProfilePreferencesService extends ChangeNotifier {
  static const _displayNameKey = 'profile_display_name_v1';
  static const _heightCmKey = 'profile_height_cm_v1';
  static const _weightKgKey = 'profile_weight_kg_v1';
  static const _stepGoalKey = 'profile_step_goal_v1';
  static const _notificationsEnabledKey = 'profile_notifications_enabled_v1';

  Future<void>? _initFuture;

  String _displayName = 'SeekNirvana User';
  int _heightCm = 178;
  int _weightKg = 70;
  int _stepGoal = AppConstants.defaultStepGoal;
  bool _notificationsEnabled = true;

  String get displayName => _displayName;
  int get heightCm => _heightCm;
  int get weightKg => _weightKg;
  int get stepGoal => _stepGoal;
  bool get notificationsEnabled => _notificationsEnabled;

  String get profileSummary =>
      '$_heightCm cm · $_weightKg kg · ${_stepGoal.toString()} steps';

  Future<void> init() => _initFuture ??= _load();

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _displayName = prefs.getString(_displayNameKey) ?? _displayName;
    _heightCm = prefs.getInt(_heightCmKey) ?? _heightCm;
    _weightKg = prefs.getInt(_weightKgKey) ?? _weightKg;
    _stepGoal = prefs.getInt(_stepGoalKey) ?? _stepGoal;
    _notificationsEnabled =
        prefs.getBool(_notificationsEnabledKey) ?? _notificationsEnabled;
    notifyListeners();
  }

  Future<void> updateProfile({
    required String displayName,
    required int heightCm,
    required int weightKg,
    required int stepGoal,
  }) async {
    final normalizedName = displayName.trim().isEmpty
        ? 'SeekNirvana User'
        : displayName.trim();

    _displayName = normalizedName;
    _heightCm = heightCm;
    _weightKg = weightKg;
    _stepGoal = stepGoal;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_displayNameKey, _displayName);
    await prefs.setInt(_heightCmKey, _heightCm);
    await prefs.setInt(_weightKgKey, _weightKg);
    await prefs.setInt(_stepGoalKey, _stepGoal);
    notifyListeners();
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    _notificationsEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notificationsEnabledKey, enabled);
    notifyListeners();
  }
}

final profilePreferencesProvider =
    ChangeNotifierProvider<ProfilePreferencesService>((ref) {
      final service = ProfilePreferencesService();
      Future.microtask(() => service.init());
      ref.onDispose(service.dispose);
      return service;
    });
