import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_startup_service.dart';

enum GuideKind { luna, nova }

const List<GuideKind> activeGuideKinds = [GuideKind.luna, GuideKind.nova];

enum GuideModelStatus {
  idle,
  checking,
  missing,
  downloading,
  verifying,
  ready,
  failed,
}

class GuidePersonaDefinition {
  final GuideKind kind;
  final String name;
  final String title;
  final String specialty;
  final String modelLabel;
  final String repoId;
  final String remoteDirectory;
  final String localFolderName;
  final String shortDescription;
  final String tooltipSummary;
  final String starterMessage;
  final List<String> quickPrompts;
  final String systemPrompt;
  final ModelType flutterGemmaModelType;
  final ModelFileType modelFileType;
  final String modelDownloadUrl;
  final String? huggingFaceToken;

  const GuidePersonaDefinition({
    required this.kind,
    required this.name,
    required this.title,
    required this.specialty,
    required this.modelLabel,
    required this.repoId,
    required this.remoteDirectory,
    required this.localFolderName,
    required this.shortDescription,
    required this.tooltipSummary,
    required this.starterMessage,
    required this.quickPrompts,
    required this.systemPrompt,
    required this.flutterGemmaModelType,
    required this.modelFileType,
    required this.modelDownloadUrl,
    this.huggingFaceToken,
  });
}

List<GuideKind> guideKindsSharingBundle(GuidePersonaDefinition definition) {
  final modelFile = guideInstalledModelFileName(definition);
  return activeGuideKinds
      .where((kind) {
        return guideInstalledModelFileName(guidePersonaDefinitions[kind]!) ==
            modelFile;
      })
      .toList(growable: false);
}

String guideInstalledModelFileName(GuidePersonaDefinition definition) {
  return Uri.parse(definition.modelDownloadUrl).pathSegments.last;
}

String guideInstalledModelName(GuidePersonaDefinition definition) {
  return p.basenameWithoutExtension(guideInstalledModelFileName(definition));
}

InferenceModelSpec guideInferenceModelSpec(GuidePersonaDefinition definition) {
  return InferenceModelSpec.fromLegacyUrl(
    name: guideInstalledModelName(definition),
    modelUrl: definition.modelDownloadUrl,
    modelType: definition.flutterGemmaModelType,
    fileType: definition.modelFileType,
    replacePolicy: ModelReplacePolicy.keep,
  );
}

String? guidePrimaryModelPathFromFileMap(
  InferenceModelSpec spec,
  Map<String, String>? filePaths,
) {
  if (filePaths == null || filePaths.isEmpty) {
    return null;
  }

  final primaryKey = spec.files.first.prefsKey;
  return filePaths[primaryKey] ?? filePaths.values.first;
}

Future<bool> _validateGuideBundleFile(
  String? filePath,
  ModelFileType fileType,
) async {
  if (filePath == null || filePath.isEmpty) {
    return false;
  }

  final file = File(filePath);
  if (!await file.exists()) {
    return false;
  }

  if (fileType != ModelFileType.task) {
    final fileLength = await file.length();
    return fileLength > 1024 * 1024;
  }

  final raf = await file.open();
  try {
    final header = await raf.read(4);
    if (header.length < 4) {
      return false;
    }

    return header[0] == 0x50 &&
        header[1] == 0x4B &&
        ((header[2] == 0x03 && header[3] == 0x04) ||
            (header[2] == 0x05 && header[3] == 0x06) ||
            (header[2] == 0x07 && header[3] == 0x08));
  } finally {
    await raf.close();
  }
}

Future<String?> resolveInstalledGuideModelPath(
  GuidePersonaDefinition definition,
) async {
  final spec = guideInferenceModelSpec(definition);
  final filePaths = await FlutterGemmaPlugin.instance.modelManager
      .getModelFilePaths(spec);
  return guidePrimaryModelPathFromFileMap(spec, filePaths);
}

Future<bool> validateInstalledGuideModel(
  GuidePersonaDefinition definition,
) async {
  final path = await resolveInstalledGuideModelPath(definition);
  return _validateGuideBundleFile(path, definition.modelFileType);
}

const Map<GuideKind, GuidePersonaDefinition> guidePersonaDefinitions = {
  GuideKind.luna: GuidePersonaDefinition(
    kind: GuideKind.luna,
    name: 'Luna',
    title: 'Somatic Guide',
    specialty: 'Body, sleep, and physical settling',
    modelLabel: 'Gemma 4 E2B on-device',
    repoId: 'google/gemma-4-e2b-it',
    remoteDirectory: '',
    localFolderName: 'luna-gemma4',
    shortDescription:
        'A calm, body-first guide for easing tension, settling restlessness, and preparing for deeper sleep.',
    tooltipSummary:
        'Luna is the grounded, body-first guide. Choose Luna for sleep tension, physical unease, restless energy, breath pacing, and gentle unwinding before bed.',
    starterMessage:
        'I\'m Luna. Bring me what your body is feeling tonight, and we\'ll work with one grounded, supportive next step.',
    quickPrompts: [
      'My shoulders are tense at bedtime. What should I do first?',
      'Give me a 10-minute wind-down routine for physical restlessness.',
      'My jaw and neck carry stress at night. Help me settle.',
    ],
    systemPrompt:
        'You are Luna, SeekNirvana\'s private somatic guide. Speak with warmth, steadiness, and grounded confidence. Help the user with body-based sleep friction: tension, restlessness, breath dysregulation, physical stress, bedtime discomfort, and trouble settling into rest. Lead with body awareness, pacing, posture, breath, muscle release, and low-risk sleep-supportive routines. Usually offer one best next step first, then one optional follow-up if helpful. Keep answers practical, calm, and uncluttered. Prefer supportive coaching over explanation-heavy teaching. Never output hidden reasoning, XML-like tags, or meta commentary. Do not diagnose, prescribe medication, or claim certainty. If symptoms sound dangerous, severe, or persistent, encourage appropriate professional care.',
    flutterGemmaModelType: ModelType.gemmaIt,
    modelFileType: ModelFileType.litertlm,
    modelDownloadUrl:
        'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm',
    huggingFaceToken: null,
  ),
  GuideKind.nova: GuidePersonaDefinition(
    kind: GuideKind.nova,
    name: 'Nova',
    title: 'Cognitive Guide',
    specialty: 'Mind, dreams, and inner practice',
    modelLabel: 'Gemma 4 E2B on-device',
    repoId: 'google/gemma-4-e2b-it',
    remoteDirectory: '',
    localFolderName: 'nova-gemma4',
    shortDescription:
        'A reflective guide for quieting mental loops, deepening dream recall, and building a steadier inner practice.',
    tooltipSummary:
        'Nova is the reflective, mind-first guide. Choose Nova for dream work, meditation, bedtime overthinking, mental decompression, and insight-oriented reflection.',
    starterMessage:
        'I\'m Nova. Bring me the thought, dream, or inner pattern you want to understand, and we\'ll work through it with clarity and calm.',
    quickPrompts: [
      'Help me build a dream recall practice I can actually keep up.',
      'My mind is noisy at bedtime. Give me one calming mental practice.',
      'How should I start lucid dreaming without overcomplicating it?',
    ],
    systemPrompt:
        'You are Nova, SeekNirvana\'s private reflective guide. Speak with calm clarity, emotional intelligence, and concise insight. Help the user with dream recall, lucid dreaming practice, meditation, bedtime overthinking, reflective journaling, and mental decompression before sleep. Favor clear framing, pattern recognition, and gentle reframes. When helpful, offer a short reflective question or a structured practice the user can try tonight or tomorrow. Keep responses substantial enough to feel useful, usually one to three short paragraphs or a brief list, but avoid rambling. Never output hidden reasoning, <think> tags, or chain-of-thought. Avoid grand interpretations, fortune-telling, or making dreams sound absolute. Do not diagnose mental illness or provide crisis counseling. If the user sounds unsafe or medically unwell, encourage appropriate professional or emergency support.',
    flutterGemmaModelType: ModelType.gemmaIt,
    modelFileType: ModelFileType.litertlm,
    modelDownloadUrl:
        'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm',
    huggingFaceToken: null,
  ),
};

class GuideModelState {
  final GuidePersonaDefinition definition;
  GuideModelStatus status;
  double progress;
  String? errorMessage;

  GuideModelState({
    required this.definition,
    this.status = GuideModelStatus.idle,
    this.progress = 0,
    this.errorMessage,
  });

  bool get isReady => status == GuideModelStatus.ready;

  String get statusLabel {
    switch (status) {
      case GuideModelStatus.idle:
        return 'Waiting';
      case GuideModelStatus.checking:
        return 'Checking';
      case GuideModelStatus.missing:
        return 'Not downloaded';
      case GuideModelStatus.downloading:
        return 'Downloading';
      case GuideModelStatus.verifying:
        return 'Verifying';
      case GuideModelStatus.ready:
        return 'Ready';
      case GuideModelStatus.failed:
        return 'Needs attention';
    }
  }
}

class GuideStorageSnapshot {
  final String? rootPath;
  final String? chatPath;
  final String? chatDatabasePath;
  final List<String> guideModelPaths;
  final String? voicePath;
  final String? whisperModelPath;
  final int guideModelBytes;
  final int voiceBytes;
  final int whisperModelBytes;
  final int chatBytes;
  final int databaseBytes;

  const GuideStorageSnapshot({
    required this.rootPath,
    required this.chatPath,
    required this.chatDatabasePath,
    required this.guideModelPaths,
    required this.voicePath,
    required this.whisperModelPath,
    required this.guideModelBytes,
    required this.voiceBytes,
    required this.whisperModelBytes,
    required this.chatBytes,
    required this.databaseBytes,
  });

  int get totalBytes =>
      guideModelBytes +
      voiceBytes +
      whisperModelBytes +
      chatBytes +
      databaseBytes;
}

class GuideModelManager extends ChangeNotifier {
  static const _storageDirectoryKey = 'guide_model_storage_directory_v1';
  static const _runtimeDebugEnabledKey = 'guide_runtime_debug_enabled_v1';
  static const _streamingEnabledKey = 'guide_streaming_enabled_v1';

  Future<void>? _initFuture;
  String? _storageDirectoryPath;
  String? _defaultStorageDirectoryPath;
  String? _globalError;
  bool _runtimeDebugEnabled = false;
  bool _streamingEnabled = !Platform.isIOS;

  final Map<GuideKind, GuideModelState> _states = {
    for (final entry in guidePersonaDefinitions.entries)
      entry.key: GuideModelState(definition: entry.value),
  };

  Map<GuideKind, GuideModelState> get states => _states;

  String? get globalError => _globalError;

  String? get storageDirectoryPath => _storageDirectoryPath;

  String? get defaultStorageDirectoryPath => _defaultStorageDirectoryPath;

  bool get runtimeDebugEnabled => _runtimeDebugEnabled;
  bool get streamingEnabled => Platform.isIOS ? false : _streamingEnabled;

  String? get chatDirectoryPath => _storageDirectoryPath == null
      ? null
      : p.join(_storageDirectoryPath!, 'chats');

  String? get chatDatabasePath => chatDirectoryPath == null
      ? null
      : p.join(chatDirectoryPath!, 'guide_chats.db');

  bool get allModelsReady =>
      activeGuideKinds.every((kind) => _states[kind]!.isReady);

  bool get runtimeAvailable => true;

  String get runtimeUnavailableReason => '';

  GuideModelState stateFor(GuideKind kind) => _states[kind]!;

  Future<void> init() {
    return _initFuture ??= _initialize();
  }

  Future<void> _initialize() async {
    try {
      await AppStartupService.instance.ensureInitialized();
      _defaultStorageDirectoryPath =
          await _resolveDefaultStorageDirectoryPath();
      final prefs = await SharedPreferences.getInstance();
      final savedPath = prefs.getString(_storageDirectoryKey);
      _runtimeDebugEnabled = prefs.getBool(_runtimeDebugEnabledKey) ?? false;
      final savedStreaming = prefs.getBool(_streamingEnabledKey);
      _streamingEnabled = Platform.isIOS ? false : (savedStreaming ?? true);
      if (Platform.isIOS && savedStreaming != false) {
        await prefs.setBool(_streamingEnabledKey, false);
      }
      _storageDirectoryPath = (savedPath?.trim().isNotEmpty ?? false)
          ? savedPath!.trim()
          : _defaultStorageDirectoryPath;

      // Check which models are installed
      for (final kind in activeGuideKinds) {
        await _checkModelStatus(kind);
      }

      notifyListeners();
    } catch (error) {
      _globalError = 'Failed to initialize model storage: $error';
      notifyListeners();
    }
  }

  Future<void> _checkModelStatus(GuideKind kind) async {
    final state = _states[kind]!;

    // Don't recheck if already ready
    if (state.status == GuideModelStatus.ready) {
      return;
    }

    state.status = GuideModelStatus.checking;
    notifyListeners();

    await recheckModelStatus(kind);
  }

  /// Public method to recheck model status (can be called from UI)
  Future<void> recheckModelStatus(GuideKind kind) async {
    final state = _states[kind]!;
    final definition = state.definition;
    final spec = guideInferenceModelSpec(definition);

    debugPrint('Checking model status for ${definition.name}');

    try {
      await AppStartupService.instance.ensureInitialized();
      final manager = FlutterGemmaPlugin.instance.modelManager;
      final isInstalled = await manager.isModelInstalled(spec);
      debugPrint('Model ${definition.name} installed: $isInstalled');

      if (!isInstalled) {
        state.status = GuideModelStatus.missing;
        state.errorMessage = null;
        state.progress = 0;
      } else {
        final isValidArchive = await validateInstalledGuideModel(definition);
        debugPrint('Model ${definition.name} archive valid: $isValidArchive');

        if (isValidArchive) {
          state.status = GuideModelStatus.ready;
          state.errorMessage = null;
          state.progress = 1;
          _globalError = null;
        } else {
          state.status = GuideModelStatus.failed;
          state.errorMessage =
              '${definition.name} downloaded, but the model bundle is invalid. Delete and download again.';
        }
      }
    } catch (e, stack) {
      debugPrint('Check status error: $e');
      debugPrint('Stack: $stack');
      state.status = GuideModelStatus.failed;
      state.errorMessage = 'Failed to check model status: $e';
    }

    notifyListeners();
  }

  Future<void> recheckSharedModelStatuses(GuideKind kind) async {
    final definition = guidePersonaDefinitions[kind]!;
    for (final relatedKind in guideKindsSharingBundle(definition)) {
      await recheckModelStatus(relatedKind);
    }
  }

  Future<void> downloadModel(
    GuideKind kind, {
    Function(double)? onProgress,
  }) async {
    final state = _states[kind]!;
    final definition = state.definition;
    final spec = guideInferenceModelSpec(definition);

    state.status = GuideModelStatus.downloading;
    state.progress = 0;
    state.errorMessage = null;
    notifyListeners();

    debugPrint('Starting download for ${definition.name}');
    debugPrint('URL: ${definition.modelDownloadUrl}');
    debugPrint('Model type: ${definition.flutterGemmaModelType}');

    try {
      await AppStartupService.instance.ensureInitialized();
      await FlutterGemma.installModel(
            modelType: definition.flutterGemmaModelType,
            fileType: definition.modelFileType,
          )
          .fromNetwork(
            definition.modelDownloadUrl,
            token: definition.huggingFaceToken,
          )
          .withProgress((progress) {
            debugPrint('Download progress: ${progress.toStringAsFixed(1)}%');
            state.progress = progress / 100;
            onProgress?.call(state.progress);
            notifyListeners();
          })
          .install();

      state.status = GuideModelStatus.verifying;
      notifyListeners();

      final manager = FlutterGemmaPlugin.instance.modelManager;
      manager.setActiveModel(spec);
      final modelPath = await resolveInstalledGuideModelPath(definition);
      final fileLength = modelPath == null ? 0 : await File(modelPath).length();
      final installedNow = await manager.isModelInstalled(spec);
      final validNow = await validateInstalledGuideModel(definition);

      debugPrint(
        'Verification for ${definition.name}: installed=$installedNow, valid=$validNow, path=$modelPath, bytes=$fileLength',
      );

      final isReady = installedNow && validNow;

      if (isReady) {
        state.status = GuideModelStatus.ready;
        state.progress = 1;
        state.errorMessage = null;
        _globalError = null;
        debugPrint('Model ${definition.name} installed and verified');
        await recheckSharedModelStatuses(kind);
      } else {
        await manager.deleteModel(spec);
        state.status = GuideModelStatus.failed;
        state.errorMessage =
            'Downloaded ${definition.name}, but the model bundle could not be validated. Please try again.';
        _globalError = state.errorMessage;
      }
    } catch (e, stack) {
      debugPrint('Download error: $e');
      debugPrint('Stack trace: $stack');
      state.status = GuideModelStatus.failed;
      state.errorMessage = 'Download failed: $e';
      _globalError = state.errorMessage;
    }

    notifyListeners();
  }

  Future<void> setRuntimeDebugEnabled(bool enabled) async {
    await init();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_runtimeDebugEnabledKey, enabled);
    _runtimeDebugEnabled = enabled;
    notifyListeners();
  }

  Future<void> setStreamingEnabled(bool enabled) async {
    await init();
    final prefs = await SharedPreferences.getInstance();
    if (Platform.isIOS) {
      await prefs.setBool(_streamingEnabledKey, false);
      _streamingEnabled = false;
    } else {
      await prefs.setBool(_streamingEnabledKey, enabled);
      _streamingEnabled = enabled;
    }
    notifyListeners();
  }

  Future<void> deleteModel(GuideKind kind) async {
    final state = _states[kind]!;
    final spec = guideInferenceModelSpec(state.definition);

    try {
      await AppStartupService.instance.ensureInitialized();
      await FlutterGemmaPlugin.instance.modelManager.deleteModel(spec);
      for (final relatedKind in guideKindsSharingBundle(state.definition)) {
        final relatedState = _states[relatedKind]!;
        relatedState.status = GuideModelStatus.missing;
        relatedState.progress = 0;
        relatedState.errorMessage = null;
      }
    } catch (e) {
      state.errorMessage = 'Failed to delete model: $e';
    }

    notifyListeners();
  }

  Future<void> updateStorageDirectory(String path) async {
    await init();
    final normalized = path.trim();
    if (normalized.isEmpty) {
      await resetStorageDirectory();
      return;
    }

    final directory = Directory(normalized);
    await directory.create(recursive: true);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageDirectoryKey, normalized);
    _storageDirectoryPath = normalized;

    // Reset state and recheck models
    for (final kind in activeGuideKinds) {
      _states[kind] = GuideModelState(
        definition: guidePersonaDefinitions[kind]!,
      );
      await _checkModelStatus(kind);
    }

    notifyListeners();
  }

  Future<void> resetStorageDirectory() async {
    await init();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageDirectoryKey);
    _storageDirectoryPath = _defaultStorageDirectoryPath;

    // Reset state and recheck models
    for (final kind in activeGuideKinds) {
      _states[kind] = GuideModelState(
        definition: guidePersonaDefinitions[kind]!,
      );
      await _checkModelStatus(kind);
    }

    notifyListeners();
  }

  Future<GuideStorageSnapshot> loadStorageSnapshot() async {
    await init();

    final chatPath = chatDirectoryPath;
    final databasePath = chatDatabasePath;
    final voicePath = _storageDirectoryPath == null
        ? null
        : p.join(_storageDirectoryPath!, 'voice');
    final whisperModelPath = voicePath == null
        ? null
        : p.join(voicePath, 'whisper');

    final guideModelPaths = await _installedGuideModelPaths();
    final guideModelBytes = await _measureUniquePathsBytes(guideModelPaths);
    final whisperModelBytes = await _measurePathBytes(whisperModelPath);
    final rawVoiceBytes = await _measurePathBytes(voicePath);
    final voiceBytes = rawVoiceBytes > whisperModelBytes
        ? rawVoiceBytes - whisperModelBytes
        : 0;
    final chatBytes = await _measurePathBytes(chatPath);
    final databaseBytes = await _measureFileBytes(databasePath);

    return GuideStorageSnapshot(
      rootPath: storageDirectoryPath,
      chatPath: chatPath,
      chatDatabasePath: databasePath,
      guideModelPaths: guideModelPaths,
      voicePath: voicePath,
      whisperModelPath: whisperModelPath,
      guideModelBytes: guideModelBytes,
      voiceBytes: voiceBytes,
      whisperModelBytes: whisperModelBytes,
      chatBytes: chatBytes,
      databaseBytes: databaseBytes,
    );
  }

  Future<List<String>> _installedGuideModelPaths() async {
    final uniquePaths = <String>{};
    for (final kind in activeGuideKinds) {
      final path = await resolveInstalledGuideModelPath(
        guidePersonaDefinitions[kind]!,
      );
      if (path != null && path.isNotEmpty) {
        uniquePaths.add(path);
      }
    }
    return uniquePaths.toList()..sort();
  }

  Future<int> _measureUniquePathsBytes(List<String> paths) async {
    var total = 0;
    for (final path in paths.toSet()) {
      total += await _measurePathBytes(path);
    }
    return total;
  }

  Future<int> _measurePathBytes(String? path) async {
    if (path == null || path.isEmpty) {
      return 0;
    }

    final type = FileSystemEntity.typeSync(path, followLinks: false);
    switch (type) {
      case FileSystemEntityType.file:
        return _measureFileBytes(path);
      case FileSystemEntityType.directory:
        final directory = Directory(path);
        if (!await directory.exists()) {
          return 0;
        }

        var total = 0;
        await for (final entity in directory.list(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is File) {
            try {
              total += await entity.length();
            } catch (_) {
              // Skip unreadable files while still reporting the rest of storage.
            }
          }
        }
        return total;
      case FileSystemEntityType.notFound:
      case FileSystemEntityType.link:
      case FileSystemEntityType.pipe:
      case FileSystemEntityType.unixDomainSock:
        return 0;
    }

    return 0;
  }

  Future<int> _measureFileBytes(String? path) async {
    if (path == null || path.isEmpty) {
      return 0;
    }

    final file = File(path);
    if (!await file.exists()) {
      return 0;
    }

    try {
      return await file.length();
    } catch (_) {
      return 0;
    }
  }

  Future<String> _resolveDefaultStorageDirectoryPath() async {
    if (Platform.isAndroid) {
      final baseDir =
          await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
      return p.join(baseDir.path, 'seeknirvana');
    }

    final documentsDir = await getApplicationDocumentsDirectory();
    return p.join(documentsDir.path, 'seeknirvana');
  }
}

final guideModelManagerProvider = ChangeNotifierProvider<GuideModelManager>((
  ref,
) {
  final manager = GuideModelManager();
  manager.init();
  return manager;
});
