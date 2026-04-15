import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
        'A body-first guide for sleep tension, breath pacing, wind-down routines, and gentle movement before bed.',
    tooltipSummary:
        'Luna is the grounded, body-first guide. Choose Luna for sleep tension, restlessness, body discomfort, breath pacing, and gentle physical unwinding.',
    starterMessage:
        'I\'m Luna. Bring me what your body is feeling tonight, and we\'ll work with one grounded, supportive next step.',
    quickPrompts: [
      'My shoulders are tense at bedtime. What should I do first?',
      'Give me a 10-minute wind-down routine for physical restlessness.',
      'My jaw and neck carry stress at night. Help me settle.',
    ],
    systemPrompt:
        'You are Luna, SeekNirvana\'s private somatic guide. Speak with warmth, steadiness, and simple precision. Help the user settle sleep-related physical tension, restlessness, breath dysregulation, and body-based stress using gentle, low-risk practices. Keep answers grounded in sensation, pacing, posture, and nervous-system settling. Usually offer one primary practice first, not a long list. Keep language calm and uncluttered. Avoid sounding clinical, mystical, or overly poetic. Do not diagnose, prescribe medication, or claim certainty. Encourage stopping if discomfort increases and suggest professional care when symptoms sound dangerous, severe, or persistent.',
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
    modelLabel: 'Qwen 3 0.6B on-device',
    repoId: 'litert-community/Qwen3-0.6B',
    remoteDirectory: '',
    localFolderName: 'nova-qwen3',
    shortDescription:
        'A reflective guide for dream recall, lucid dreaming practice, meditation, and easing mental loops before sleep.',
    tooltipSummary:
        'Nova is the reflective, mind-first guide. Choose Nova for dream work, meditation, anxious thought loops, mental decompression, and insight-oriented reflection.',
    starterMessage:
        'I\'m Nova. Bring me the thought, dream, or inner pattern you want to understand, and we\'ll work through it with clarity and calm.',
    quickPrompts: [
      'Help me build a dream recall practice I can actually keep up.',
      'My mind is noisy at bedtime. Give me one calming mental practice.',
      'How should I start lucid dreaming without overcomplicating it?',
    ],
    systemPrompt:
        'You are Nova, SeekNirvana\'s private reflective guide. Speak with calm clarity, gentle curiosity, and concise insight. Help the user with dream recall, lucid dreaming routines, meditation, bedtime overthinking, and reflective mental decompression. Ask thoughtful follow-up questions only when they truly help. Prefer one clear frame or practice over a long menu of advice. Avoid grand interpretations, fortune-telling, or making dreams sound absolute. Do not diagnose mental illness or provide crisis counseling. If the user sounds at risk or medically unwell, encourage professional or emergency support appropriately.',
    flutterGemmaModelType: ModelType.qwen,
    modelFileType: ModelFileType.litertlm,
    modelDownloadUrl:
        'https://huggingface.co/litert-community/Qwen3-0.6B/resolve/main/Qwen3-0.6B.litertlm',
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

class GuideModelManager extends ChangeNotifier {
  static const _storageDirectoryKey = 'guide_model_storage_directory_v1';
  static const _runtimeDebugEnabledKey = 'guide_runtime_debug_enabled_v1';

  Future<void>? _initFuture;
  String? _storageDirectoryPath;
  String? _defaultStorageDirectoryPath;
  String? _globalError;
  bool _runtimeDebugEnabled = false;

  final Map<GuideKind, GuideModelState> _states = {
    for (final entry in guidePersonaDefinitions.entries)
      entry.key: GuideModelState(definition: entry.value),
  };

  Map<GuideKind, GuideModelState> get states => _states;

  String? get globalError => _globalError;

  String? get storageDirectoryPath => _storageDirectoryPath;

  String? get defaultStorageDirectoryPath => _defaultStorageDirectoryPath;

  bool get runtimeDebugEnabled => _runtimeDebugEnabled;

  String? get modelDirectoryPath => _storageDirectoryPath == null
      ? null
      : p.join(_storageDirectoryPath!, 'models');

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
      _defaultStorageDirectoryPath =
          await _resolveDefaultStorageDirectoryPath();
      final prefs = await SharedPreferences.getInstance();
      final savedPath = prefs.getString(_storageDirectoryKey);
      _runtimeDebugEnabled = prefs.getBool(_runtimeDebugEnabledKey) ?? false;
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

  Future<void> deleteModel(GuideKind kind) async {
    final state = _states[kind]!;
    final spec = guideInferenceModelSpec(state.definition);

    try {
      await FlutterGemmaPlugin.instance.modelManager.deleteModel(spec);
      state.status = GuideModelStatus.missing;
      state.progress = 0;
      state.errorMessage = null;
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
