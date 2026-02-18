import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/health_provider.dart';
import '../providers/ring_provider.dart';

/// Service that manages REM audio cues for lucid dreaming.
/// Monitors sleep stages and plays gentle audio when REM is detected.
class RemAudioService {
  final Ref ref;
  AudioPlayer? _audioPlayer;
  StreamSubscription? _healthSub;
  Timer? _remCheckTimer;
  
  // State
  bool _isEnabled = false;
  double _volume = 0.5;
  String _selectedSound = 'Gentle Chime';
  bool _isPlaying = false;
  
  // Track REM state to avoid re-triggering
  bool _wasInRem = false;
  DateTime? _lastRemTriggerTime;
  
  // Minimum time between REM triggers (5 minutes)
  static const _minTriggerInterval = Duration(minutes: 5);

  RemAudioService(this.ref) {
    _init();
  }

  Future<void> _init() async {
    // Load saved settings
    await _loadSettings();
    
    // Initialize audio player
    _audioPlayer = AudioPlayer();
    await _audioPlayer!.setVolume(_volume);
    
    // Listen to health data for REM detection
    _healthSub = ref.read(historyDataProvider.notifier).stream.listen((data) {
      if (_isEnabled) {
        _checkForRemState();
      }
    });
    
    // Periodic REM check every 30 seconds
    _remCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_isEnabled) {
        _checkForRemState();
      }
    });
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _isEnabled = prefs.getBool('rem_audio_enabled') ?? false;
    _volume = prefs.getDouble('rem_audio_volume') ?? 0.5;
    _selectedSound = prefs.getString('rem_audio_sound') ?? 'Gentle Chime';
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('rem_audio_enabled', _isEnabled);
    await prefs.setDouble('rem_audio_volume', _volume);
    await prefs.setString('rem_audio_sound', _selectedSound);
  }

  void _checkForRemState() {
    // Get recent sleep data
    final historyData = ref.read(historyDataProvider);
    if (historyData.isEmpty) return;
    
    // Check the most recent sleep record
    final latestRecord = historyData.last;
    final sleepType = latestRecord['sleepType'] as int?;
    
    // REM sleep type is 4
    final isInRem = sleepType == 4;
    
    // Trigger audio when entering REM (and not already triggered recently)
    if (isInRem && !_wasInRem) {
      final now = DateTime.now();
      if (_lastRemTriggerTime == null || 
          now.difference(_lastRemTriggerTime!) > _minTriggerInterval) {
        debugPrint('[RemAudioService] REM detected - triggering audio');
        _playRemAudio();
        _lastRemTriggerTime = now;
      }
    }
    
    _wasInRem = isInRem;
  }

  Future<void> _playRemAudio() async {
    if (_isPlaying) return;
    
    _isPlaying = true;
    
    try {
      // Generate a simple tone using system sound
      // For now, use a beep or system sound
      await _generateTone();
      
      debugPrint('[RemAudioService] Playing REM audio: $_selectedSound');
    } catch (e) {
      debugPrint('[RemAudioService] Error playing audio: $e');
    } finally {
      // Reset playing state after a delay
      await Future.delayed(const Duration(seconds: 2));
      _isPlaying = false;
    }
  }

  Future<void> _generateTone() async {
    // Use platform channel to play system sounds
    // Different sounds have different frequencies
    final frequencies = switch (_selectedSound) {
      'Gentle Chime' => [523.25, 659.25], // C5, E5
      'Tibetan Bowl' => [180.0, 200.0], // Low frequencies
      'Soft Whisper' => [800.0, 1000.0], // Higher frequencies
      'Binaural Beat' => [200.0, 210.0], // Slight difference
      'Custom Audio' => [440.0, 528.0], // A4, C5
      _ => [523.25, 659.25],
    };
    
    // Try to use the ring's built-in audio if available
    // Otherwise, play a simple beep through the phone
    try {
      // For now, use a simple beep pattern
      // In a real implementation, you would generate actual audio tones
      await SystemSound.play(SystemSoundType.click);
      
      // Double beep for some sounds
      if (_selectedSound == 'Gentle Chime' || _selectedSound == 'Tibetan Bowl') {
        await Future.delayed(const Duration(milliseconds: 200));
        await SystemSound.play(SystemSoundType.click);
      }
    } catch (e) {
      debugPrint('[RemAudioService] Could not play system sound: $e');
    }
  }

  // ─── Public API ─────────────────────────────────────────

  /// Enable/disable REM audio cues
  Future<void> setEnabled(bool enabled) async {
    _isEnabled = enabled;
    await _saveSettings();
    debugPrint('[RemAudioService] REM audio ${enabled ? 'enabled' : 'disabled'}');
  }

  /// Set audio volume (0.0 to 1.0)
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    await _audioPlayer?.setVolume(_volume);
    await _saveSettings();
  }

  /// Select sound type
  Future<void> setSound(String sound) async {
    _selectedSound = sound;
    await _saveSettings();
  }

  /// Test play the selected sound
  Future<void> testPlay() async {
    debugPrint('[RemAudioService] Testing audio: $_selectedSound');
    await _playRemAudio();
  }

  /// Get current settings
  bool get isEnabled => _isEnabled;
  double get volume => _volume;
  String get selectedSound => _selectedSound;
  List<String> get availableSounds => [
    'Gentle Chime',
    'Tibetan Bowl',
    'Soft Whisper',
    'Binaural Beat',
    'Custom Audio',
  ];
  bool get isPlaying => _isPlaying;

  void dispose() {
    _healthSub?.cancel();
    _remCheckTimer?.cancel();
    _audioPlayer?.dispose();
  }
}

/// Provider for the REM audio service
final remAudioServiceProvider = Provider<RemAudioService>((ref) {
  return RemAudioService(ref);
});

/// Provider to access current REM audio settings
final remAudioSettingsProvider = Provider<RemAudioSettings>((ref) {
  final service = ref.watch(remAudioServiceProvider);
  return RemAudioSettings(
    enabled: service.isEnabled,
    volume: service.volume,
    selectedSound: service.selectedSound,
    availableSounds: service.availableSounds,
    isPlaying: service.isPlaying,
  );
});

class RemAudioSettings {
  final bool enabled;
  final double volume;
  final String selectedSound;
  final List<String> availableSounds;
  final bool isPlaying;

  RemAudioSettings({
    required this.enabled,
    required this.volume,
    required this.selectedSound,
    required this.availableSounds,
    required this.isPlaying,
  });
}
