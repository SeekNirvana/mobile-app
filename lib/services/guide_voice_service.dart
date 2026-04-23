import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path/path.dart' as p;
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';
import 'package:whisper_ggml_plus_ffmpeg/whisper_ggml_plus_ffmpeg.dart';

import 'guide_model_manager.dart';

@immutable
class GuideVoiceOption {
  final Map<String, String> raw;
  final String name;
  final String locale;
  final String? identifier;
  final String? gender;
  final String? quality;

  const GuideVoiceOption({
    required this.raw,
    required this.name,
    required this.locale,
    this.identifier,
    this.gender,
    this.quality,
  });

  String get stableId => identifier ?? '$name::$locale';

  String get label {
    final parts = <String>[name];
    if (locale.isNotEmpty) {
      parts.add(locale);
    }
    if (quality != null && quality!.isNotEmpty) {
      parts.add(quality!);
    }
    return parts.join(' · ');
  }
}

class GuideVoiceService extends ChangeNotifier {
  static const _voiceResponsesEnabledKey = 'guide_voice_responses_enabled_v1';
  static const _selectedVoiceJsonKey = 'guide_selected_voice_json_v1';
  static const _whisperModelKey = 'guide_whisper_model_v1';

  static bool _ffmpegConverterRegistered = false;

  final GuideModelManager _modelManager;
  final AudioRecorder _recorder = AudioRecorder();
  final FlutterTts _tts = FlutterTts();

  Future<void>? _initFuture;
  bool _voiceResponsesEnabled = false;
  bool _isRecording = false;
  bool _isTranscribing = false;
  bool _isSpeaking = false;
  bool _isPreparingWhisperModel = false;
  bool _isProcessingQueue = false;
  double _whisperDownloadProgress = 0;
  final List<String> _speakQueue = [];
  String? _activeRecordingPath;
  String? _lastError;
  WhisperModel _whisperModel = WhisperModel.tiny;
  List<GuideVoiceOption> _voices = const [];
  GuideVoiceOption? _selectedVoice;

  GuideVoiceService({required GuideModelManager modelManager})
    : _modelManager = modelManager {
    _tts.setStartHandler(() {
      _isSpeaking = true;
      notifyListeners();
    });
    _tts.setCompletionHandler(() {
      _isSpeaking = false;
      notifyListeners();
    });
    _tts.setCancelHandler(() {
      _isSpeaking = false;
      notifyListeners();
    });
    _tts.setErrorHandler((message) {
      _isSpeaking = false;
      _lastError = message?.toString();
      notifyListeners();
    });
  }

  bool get voiceResponsesEnabled => _voiceResponsesEnabled;
  bool get isRecording => _isRecording;
  bool get isTranscribing => _isTranscribing;
  bool get isSpeaking => _isSpeaking;
  bool get isPreparingWhisperModel => _isPreparingWhisperModel;
  double get whisperDownloadProgress => _whisperDownloadProgress;
  bool get isBusy => _isRecording || _isTranscribing;
  String? get lastError => _lastError;
  WhisperModel get whisperModel => _whisperModel;
  List<GuideVoiceOption> get voices => _voices;
  GuideVoiceOption? get selectedVoice => _selectedVoice;
  bool get hasVoices => _voices.isNotEmpty;

  Future<void> init() {
    return _initFuture ??= _initialize();
  }

  Future<void> _initialize() async {
    await _modelManager.init();
    _registerWhisperConverter();

    final prefs = await SharedPreferences.getInstance();
    _voiceResponsesEnabled = prefs.getBool(_voiceResponsesEnabledKey) ?? false;

    final savedModel = prefs.getString(_whisperModelKey);
    final parsedModel = WhisperModel.values.where((model) {
      return model.name == savedModel;
    });
    if (parsedModel.isNotEmpty) {
      _whisperModel = parsedModel.first;
    }

    await _configureTts();
    await _refreshVoices(notify: false);

    unawaited(() async {
      try {
        await _preloadWhisperModel(notify: false);
      } catch (_) {
        // Keep init resilient if the speech model can't be prefetched yet.
      }
    }());

    final selectedVoiceJson = prefs.getString(_selectedVoiceJsonKey);
    if (selectedVoiceJson != null && selectedVoiceJson.isNotEmpty) {
      try {
        final rawVoice = Map<String, dynamic>.from(
          jsonDecode(selectedVoiceJson) as Map,
        );
        final stableId = _stableVoiceId(rawVoice);
        _selectedVoice = _voices.cast<GuideVoiceOption?>().firstWhere(
          (voice) => voice?.stableId == stableId,
          orElse: () => null,
        );
      } catch (_) {
        // Ignore invalid persisted voice data.
      }
    }

    _selectedVoice ??= _defaultVoiceOption();
    notifyListeners();
  }

  void _registerWhisperConverter() {
    if (_ffmpegConverterRegistered) {
      return;
    }
    WhisperFFmpegConverter.register();
    _ffmpegConverterRegistered = true;
  }

  Future<void> _configureTts() async {
    await _tts.awaitSpeakCompletion(true);
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);

    if (Platform.isIOS) {
      await _tts.setSharedInstance(true);
      await _tts.autoStopSharedSession(true);
      await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        const [
          IosTextToSpeechAudioCategoryOptions.duckOthers,
          IosTextToSpeechAudioCategoryOptions
              .interruptSpokenAudioAndMixWithOthers,
        ],
        IosTextToSpeechAudioMode.voicePrompt,
      );
    }
  }

  Future<void> refreshVoices({bool notify = true}) async {
    await init();
    await _refreshVoices(notify: notify);
  }

  Future<void> _refreshVoices({bool notify = true}) async {
    try {
      await _tts.getLanguages;
      final parsed = <GuideVoiceOption>[];
      final rawVoices = await _tts.getVoices;
      if (rawVoices is List) {
        parsed.addAll(
          rawVoices
              .whereType<Map>()
              .map((item) => _parseVoiceOption(Map<String, dynamic>.from(item)))
              .whereType<GuideVoiceOption>(),
        );
      }

      if (parsed.isEmpty) {
        final defaultVoice = await _defaultSystemVoiceFallback();
        if (defaultVoice != null) {
          parsed.add(defaultVoice);
        }
      }

      if (parsed.isEmpty) {
        parsed.addAll(await _languageVoiceFallbacks());
      }

      _voices = parsed.toSet().toList()
        ..sort(
          (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
        );
      if (_selectedVoice != null) {
        final selectedId = _selectedVoice!.stableId;
        _selectedVoice = _voices.cast<GuideVoiceOption?>().firstWhere(
          (voice) => voice?.stableId == selectedId,
          orElse: () => _defaultVoiceOption(),
        );
      }
      _lastError = null;
    } catch (error) {
      _lastError = 'Unable to load device voices: $error';
    }

    if (notify) {
      notifyListeners();
    }
  }

  Future<void> setVoiceResponsesEnabled(bool enabled) async {
    await init();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_voiceResponsesEnabledKey, enabled);
    _voiceResponsesEnabled = enabled;
    notifyListeners();
  }

  Future<void> setWhisperModel(WhisperModel model) async {
    await init();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_whisperModelKey, model.name);
    _whisperModel = model;
    unawaited(() async {
      try {
        await _preloadWhisperModel(force: false);
      } catch (_) {
        // Surface the error through lastError without crashing UI callbacks.
      }
    }());
    notifyListeners();
  }

  Future<void> setSelectedVoice(GuideVoiceOption? voice) async {
    await init();
    final prefs = await SharedPreferences.getInstance();
    _selectedVoice = voice;
    if (voice == null) {
      await prefs.remove(_selectedVoiceJsonKey);
    } else {
      await prefs.setString(_selectedVoiceJsonKey, jsonEncode(voice.raw));
    }
    notifyListeners();
  }

  Future<void> startRecording() async {
    await init();
    _lastError = null;

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      throw StateError('Microphone permission is required.');
    }

    if (_isSpeaking) {
      await stopSpeaking();
    }

    final path = await _nextRecordingPath();
    await File(path).parent.create(recursive: true);

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: path,
    );

    _activeRecordingPath = path;
    _isRecording = true;
    notifyListeners();
  }

  Future<String?> stopRecording() async {
    if (!_isRecording) {
      return _activeRecordingPath;
    }

    final path = await _recorder.stop();
    _isRecording = false;
    _activeRecordingPath = path;
    notifyListeners();
    return path;
  }

  Future<void> cancelRecording() async {
    if (!_isRecording) return;
    await _recorder.cancel();
    _isRecording = false;
    _activeRecordingPath = null;
    notifyListeners();
  }

  Future<String> stopRecordingAndTranscribe() async {
    final path = await stopRecording();
    if (path == null || path.isEmpty) {
      throw StateError('No audio was recorded.');
    }
    return transcribeFile(path);
  }

  Future<String> transcribeFile(String path) async {
    await init();
    _isTranscribing = true;
    _lastError = null;
    notifyListeners();

    Whisper? whisper;
    try {
      await _preloadWhisperModel();
      whisper = Whisper(
        model: _whisperModel,
        modelDir: await _whisperModelDirectoryPath(),
      );
      final cores = Platform.numberOfProcessors.clamp(2, 8);
      final response = await whisper.transcribe(
        transcribeRequest: TranscribeRequest(
          audio: path,
          language: 'auto',
          isNoTimestamps: true,
          threads: cores,
          splitOnWord: false,
        ),
        modelPath: await whisperModelPath(),
      );
      final text = response.text.trim();
      if (text.isEmpty) {
        throw StateError('No speech was detected.');
      }
      return text;
    } catch (error) {
      _lastError = error.toString();
      rethrow;
    } finally {
      if (whisper != null) {
        try {
          await whisper.dispose();
        } catch (_) {
          // Ignore cleanup failures from native whisper contexts.
        }
      }
      _isTranscribing = false;
      notifyListeners();
    }
  }

  Future<void> speak(String text) async {
    await init();
    final normalized = text.trim();
    if (normalized.isEmpty) return;

    _lastError = null;

    if (_isSpeaking) {
      await _tts.stop();
    }

    if (_selectedVoice != null) {
      final locale = _selectedVoice!.locale;
      if (locale.isNotEmpty) {
        await _tts.setLanguage(locale);
      }
      await _tts.setVoice(_selectedVoice!.raw);
    }

    _isSpeaking = true;
    notifyListeners();

    try {
      await _tts.speak(normalized, focus: true);
    } catch (error) {
      _isSpeaking = false;
      _lastError = 'Unable to speak the response: $error';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> stopSpeaking() async {
    _speakQueue.clear();
    _isProcessingQueue = false;
    _isSpeaking = false;
    await _tts.stop();
    notifyListeners();
  }

  /// Queue a chunk of text for TTS. Sentences are spoken sequentially.
  /// Use this during streaming to speak as text arrives.
  void queueSpeak(String text) {
    final normalized = text.trim();
    if (normalized.isEmpty) return;
    _speakQueue.add(normalized);
    if (!_isProcessingQueue) {
      unawaited(_processQueue());
    }
  }

  Future<void> _processQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;
    _lastError = null;

    if (_selectedVoice != null) {
      final locale = _selectedVoice!.locale;
      if (locale.isNotEmpty) {
        await _tts.setLanguage(locale);
      }
      await _tts.setVoice(_selectedVoice!.raw);
    }

    _isSpeaking = true;
    notifyListeners();

    while (_speakQueue.isNotEmpty) {
      final chunk = _speakQueue.removeAt(0);
      try {
        await _tts.speak(chunk, focus: true);
      } catch (error) {
        _lastError = 'Unable to speak: $error';
        break;
      }
    }

    _isProcessingQueue = false;
    _isSpeaking = false;
    notifyListeners();
  }

  /// Speak a short sample using the currently selected voice for previewing.
  Future<void> previewVoice() async {
    const sample = 'Hello, I\'m your guide. Let me help you find calm and clarity.';
    await speak(sample);
  }

  @override
  void dispose() {
    unawaited(_recorder.dispose());
    unawaited(_tts.stop());
    super.dispose();
  }

  GuideVoiceOption? _parseVoiceOption(Map<String, dynamic> raw) {
    final mapped = raw.map(
      (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
    );
    final name = mapped['name']?.trim() ?? '';
    final locale = [mapped['locale'], mapped['language'], mapped['identifier']]
        .map((value) => value?.trim() ?? '')
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    if (name.isEmpty || locale.isEmpty) {
      return null;
    }
    return GuideVoiceOption(
      raw: mapped,
      name: name,
      locale: locale,
      identifier: _stringOrNull(mapped['identifier']),
      gender: _stringOrNull(mapped['gender']),
      quality: _stringOrNull(mapped['quality']),
    );
  }

  GuideVoiceOption? _defaultVoiceOption() {
    if (_voices.isEmpty) {
      return null;
    }

    final preferredEnglish = _voices.cast<GuideVoiceOption?>().firstWhere(
      (voice) => voice?.locale.toLowerCase().startsWith('en') ?? false,
      orElse: () => null,
    );
    return preferredEnglish ?? _voices.first;
  }

  Future<GuideVoiceOption?> _defaultSystemVoiceFallback() async {
    try {
      final rawDefaultVoice = await _tts.getDefaultVoice;
      if (rawDefaultVoice is Map) {
        final parsed = _parseVoiceOption(
          Map<String, dynamic>.from(rawDefaultVoice),
        );
        if (parsed != null) {
          return parsed;
        }
      }
    } catch (_) {
      // Some platforms do not expose getDefaultVoice.
    }
    return null;
  }

  Future<List<GuideVoiceOption>> _languageVoiceFallbacks() async {
    try {
      final rawLanguages = await _tts.getLanguages;
      if (rawLanguages is! List) {
        final locale = Platform.localeName.trim();
        if (locale.isEmpty) {
          return const [];
        }
        return [
          GuideVoiceOption(
            raw: <String, String>{'name': 'System default', 'locale': locale},
            name: 'System default',
            locale: locale,
          ),
        ];
      }
      final options = rawLanguages
          .whereType<String>()
          .where((language) => language.trim().isNotEmpty)
          .map(
            (language) => GuideVoiceOption(
              raw: <String, String>{'name': 'System voice', 'locale': language},
              name: 'System voice',
              locale: language,
            ),
          )
          .toList();
      if (options.isNotEmpty) {
        return options;
      }
      final locale = Platform.localeName.trim();
      if (locale.isEmpty) {
        return const [];
      }
      return [
        GuideVoiceOption(
          raw: <String, String>{'name': 'System default', 'locale': locale},
          name: 'System default',
          locale: locale,
        ),
      ];
    } catch (_) {
      final locale = Platform.localeName.trim();
      if (locale.isEmpty) {
        return const [];
      }
      return [
        GuideVoiceOption(
          raw: <String, String>{'name': 'System default', 'locale': locale},
          name: 'System default',
          locale: locale,
        ),
      ];
    }
  }

  String _stableVoiceId(Map<String, dynamic> rawVoice) {
    final identifier = rawVoice['identifier']?.toString().trim();
    if (identifier != null && identifier.isNotEmpty) {
      return identifier;
    }
    final name = rawVoice['name']?.toString().trim() ?? '';
    final locale = rawVoice['locale']?.toString().trim() ?? '';
    return '$name::$locale';
  }

  String? _stringOrNull(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  Future<String> _voiceRootPath() async {
    await _modelManager.init();
    final root = _modelManager.storageDirectoryPath;
    if (root == null || root.isEmpty) {
      throw StateError('Guide storage is not ready yet.');
    }
    final voiceRoot = p.join(root, 'voice');
    await Directory(voiceRoot).create(recursive: true);
    return voiceRoot;
  }

  Future<String> _whisperModelDirectoryPath() async {
    final root = await _voiceRootPath();
    final directory = p.join(root, 'whisper');
    await Directory(directory).create(recursive: true);
    return directory;
  }

  Future<String> whisperModelPath() async {
    final directory = await _whisperModelDirectoryPath();
    return p.join(directory, 'ggml-${_whisperModel.modelName}.bin');
  }

  Future<bool> isWhisperModelReady() async {
    final modelFile = File(await whisperModelPath());
    return modelFile.exists();
  }

  Future<int> whisperModelBytes() async {
    final modelFile = File(await whisperModelPath());
    if (!await modelFile.exists()) {
      return 0;
    }
    return modelFile.length();
  }

  Future<void> preloadWhisperModel({
    bool notify = true,
    bool force = false,
  }) async {
    await init();
    await _preloadWhisperModel(notify: notify, force: force);
  }

  Future<void> _preloadWhisperModel({
    bool notify = true,
    bool force = false,
  }) async {
    if (_isPreparingWhisperModel) {
      return;
    }

    final targetPath = await whisperModelPath();
    final targetFile = File(targetPath);
    if (force && await targetFile.exists()) {
      await targetFile.delete();
    }

    if (await targetFile.exists()) {
      if (notify) {
        notifyListeners();
      }
      return;
    }

    _isPreparingWhisperModel = true;
    _whisperDownloadProgress = 0;
    _lastError = null;
    if (notify) {
      notifyListeners();
    }

    try {
      final request = await HttpClient().getUrl(_whisperModel.modelUri);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Model download failed with status ${response.statusCode}',
          uri: _whisperModel.modelUri,
        );
      }

      final contentLength = response.contentLength;
      await targetFile.parent.create(recursive: true);
      final tempFile = File('$targetPath.download');
      if (await tempFile.exists()) {
        await tempFile.delete();
      }

      final sink = tempFile.openWrite();
      var received = 0;
      var lastNotifyAt = DateTime.now();

      try {
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;

          if (contentLength > 0) {
            _whisperDownloadProgress = (received / contentLength).clamp(0.0, 1.0);
          }

          final now = DateTime.now();
          if (now.difference(lastNotifyAt) >= const Duration(milliseconds: 200)) {
            lastNotifyAt = now;
            if (notify) {
              notifyListeners();
            }
          }
        }
      } finally {
        await sink.flush();
        await sink.close();
      }

      _whisperDownloadProgress = 1.0;
      if (notify) {
        notifyListeners();
      }

      await tempFile.rename(targetPath);
    } catch (error) {
      _lastError = 'Unable to download speech model: $error';
      rethrow;
    } finally {
      _isPreparingWhisperModel = false;
      _whisperDownloadProgress = 0;
      if (notify) {
        notifyListeners();
      }
    }
  }

  Future<String> _nextRecordingPath() async {
    final root = await _voiceRootPath();
    final directory = p.join(root, 'recordings');
    await Directory(directory).create(recursive: true);
    return p.join(
      directory,
      'guide_prompt_${DateTime.now().millisecondsSinceEpoch}.wav',
    );
  }
}

final guideVoiceServiceProvider = ChangeNotifierProvider<GuideVoiceService>((
  ref,
) {
  final manager = ref.read(guideModelManagerProvider);
  final service = GuideVoiceService(modelManager: manager);
  service.init();
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});
