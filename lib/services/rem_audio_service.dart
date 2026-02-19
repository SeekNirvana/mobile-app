import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/ring_provider.dart';

// Local audio assets for lucid dreaming sounds
// Files should be placed in assets/audio/ directory
const _soundAssets = {
  'Gentle Chime': 'audio/chime-sound.mp3',
  'Tibetan Bowl': 'audio/tibetan-bowl-sound.mp3',
  'Singing Bowl': 'audio/tibetan-singing-bowl.mp3',
  'Dream Modular': 'audio/dreaming-modular-sound.mp3',
};

/// Service that manages REM audio cues for lucid dreaming.
/// Monitors sleep stages and plays gentle audio when REM is detected.
class RemAudioService extends ChangeNotifier {
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
    
    // Set release mode to stop when finished
    await _audioPlayer!.setReleaseMode(ReleaseMode.stop);
    
    // Listen for audio completion
    _audioPlayer!.onPlayerComplete.listen((_) {
      debugPrint('[RemAudioService] Audio playback completed');
      _isPlaying = false;
      notifyListeners();
    });
    
    // Listen for audio errors
    _audioPlayer!.onPlayerStateChanged.listen((state) {
      debugPrint('[RemAudioService] Player state: $state');
    });
    
    // Listen for playback errors
    _audioPlayer!.onLog.listen((String message) {
      debugPrint('[RemAudioService] Audio log: $message');
    });
    
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
    final savedSound = prefs.getString('rem_audio_sound');
    // Validate that saved sound exists in available sounds, default to Gentle Chime
    if (savedSound != null && _soundAssets.containsKey(savedSound)) {
      _selectedSound = savedSound;
    } else {
      _selectedSound = 'Gentle Chime';
    }
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
    notifyListeners();
    
    try {
      debugPrint('[RemAudioService] Playing REM audio: $_selectedSound');
      await _generateTone();
      
      // Auto-reset playing state after 3 seconds max (for short cues)
      // The onPlayerComplete listener will reset it earlier if audio finishes first
      Future.delayed(const Duration(seconds: 3), () {
        if (_isPlaying) {
          _isPlaying = false;
          notifyListeners();
        }
      });
    } catch (e) {
      debugPrint('[RemAudioService] Error playing audio: $e');
      _isPlaying = false;
      notifyListeners();
    }
  }

  Future<void> _generateTone() async {
    try {
      // Get the asset path for the selected sound
      final assetPath = _soundAssets[_selectedSound] ?? _soundAssets['Gentle Chime']!;
      
      debugPrint('[RemAudioService] Playing sound: $_selectedSound from assets/$assetPath');
      
      // Use AudioPlayer to play the sound from assets
      if (_audioPlayer != null) {
        // Stop any currently playing audio
        await _audioPlayer!.stop();
        
        debugPrint('[RemAudioService] Creating AssetSource for: $assetPath');
        final source = AssetSource(assetPath);
        
        // Play from asset
        debugPrint('[RemAudioService] Calling play()...');
        await _audioPlayer!.play(source);
        
        debugPrint('[RemAudioService] Audio playback started successfully');
      } else {
        // Fallback to system sound if audio player not initialized
        debugPrint('[RemAudioService] AudioPlayer is null, using fallback');
        await _fallbackBeep();
      }
    } catch (e, stackTrace) {
      debugPrint('[RemAudioService] Error playing audio: $e');
      debugPrint('[RemAudioService] Stack trace: $stackTrace');
      // Fallback to system sound
      await _fallbackBeep();
    }
  }
  
  Future<void> _fallbackBeep() async {
    try {
      // Use a pattern of system clicks to simulate a gentle chime
      await SystemSound.play(SystemSoundType.click);
      await Future.delayed(const Duration(milliseconds: 150));
      await SystemSound.play(SystemSoundType.click);
      await Future.delayed(const Duration(milliseconds: 150));
      await SystemSound.play(SystemSoundType.click);
    } catch (e) {
      debugPrint('[RemAudioService] Fallback beep also failed: $e');
    }
  }

  // ─── Public API ─────────────────────────────────────────

  /// Enable/disable REM audio cues
  Future<void> setEnabled(bool enabled) async {
    _isEnabled = enabled;
    await _saveSettings();
    notifyListeners();
    debugPrint('[RemAudioService] REM audio ${enabled ? 'enabled' : 'disabled'}');
  }

  /// Set audio volume (0.0 to 1.0)
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    await _audioPlayer?.setVolume(_volume);
    await _saveSettings();
    notifyListeners();
  }

  /// Select sound type
  Future<void> setSound(String sound) async {
    _selectedSound = sound;
    await _saveSettings();
    notifyListeners();
  }

  /// Test play the selected sound
  Future<void> testPlay() async {
    debugPrint('[RemAudioService] Testing audio: $_selectedSound');
    // Don't set _isPlaying here, let _playRemAudio handle it
    await _playRemAudio();
  }

  /// Get current settings
  bool get isEnabled => _isEnabled;
  double get volume => _volume;
  String get selectedSound => _selectedSound;
  List<String> get availableSounds => _soundAssets.keys.toList();
  bool get isPlaying => _isPlaying;

  @override
  void dispose() {
    _healthSub?.cancel();
    _remCheckTimer?.cancel();
    _audioPlayer?.dispose();
  }
}

/// Provider for the REM audio service (ChangeNotifier)
final remAudioServiceProvider = ChangeNotifierProvider<RemAudioService>((ref) {
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
