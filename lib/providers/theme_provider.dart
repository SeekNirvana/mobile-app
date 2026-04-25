import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart';

/// Provider for the current theme mode (light/dark)
final themeModeProvider = StateProvider<ThemeMode>(
  (ref) => ThemeMode.dark,
);
