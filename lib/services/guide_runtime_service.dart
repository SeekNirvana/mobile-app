import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path/path.dart' as p;

import 'guide_chat_store.dart';
import 'guide_model_manager.dart';

/// Runtime service for on-device AI using flutter_gemma
class GuideRuntimeService {
  InferenceModel? _currentModel;
  InferenceChat? _activeChat;

  GuideKind? _activeGuide;
  bool _isGenerating = false;
  String? _activeModelPath;
  ModelFileType? _activeModelFileType;
  Duration? _lastInitializeDuration;
  Duration? _lastGenerationDuration;
  int? _lastPromptTokenCount;
  int? _lastResponseTokenCount;
  int? _lastPromptCharCount;
  int? _lastResponseCharCount;
  String? _lastError;

  GuideKind? get activeGuide => _activeGuide;
  bool get hasLoadedModel => _activeChat != null;
  bool get isGenerating => _isGenerating;
  String? get activeModelPath => _activeModelPath;
  String? get activeModelFileName =>
      _activeModelPath == null ? null : p.basename(_activeModelPath!);
  ModelFileType? get activeModelFileType => _activeModelFileType;
  Duration? get lastInitializeDuration => _lastInitializeDuration;
  Duration? get lastGenerationDuration => _lastGenerationDuration;
  int? get lastPromptTokenCount => _lastPromptTokenCount;
  int? get lastResponseTokenCount => _lastResponseTokenCount;
  int? get lastPromptCharCount => _lastPromptCharCount;
  int? get lastResponseCharCount => _lastResponseCharCount;
  String? get lastError => _lastError;

  /// Initialize the runtime for a specific guide
  Future<void> initialize(GuideKind guide) async {
    debugPrint('Initializing runtime for guide: $guide');

    // If already initialized for this guide, skip
    if (_activeGuide == guide && _activeChat != null) {
      debugPrint('Already initialized for $guide');
      return;
    }

    // Clean up previous model/chat
    await offload();

    final definition = guidePersonaDefinitions[guide]!;
    final stopwatch = Stopwatch()..start();

    try {
      await _loadGuideModel(definition);
      stopwatch.stop();
      _lastInitializeDuration = stopwatch.elapsed;
      _lastError = null;
    } catch (e, stack) {
      if (_isZipArchiveError(e)) {
        debugPrint(
          'Invalid model bundle detected for ${definition.name}. Reinstalling once.',
        );

        try {
          await _ensureGuideModelReady(definition, forceReinstall: true);
          await _loadGuideModel(definition);
          stopwatch.stop();
          _lastInitializeDuration = stopwatch.elapsed;
          _lastError = null;
          return;
        } catch (retryError, retryStack) {
          debugPrint('Retry initialization failed: $retryError');
          debugPrint('Retry stack: $retryStack');
          _lastError = retryError.toString();
          rethrow;
        }
      }

      debugPrint('Error initializing runtime: $e');
      debugPrint('Stack: $stack');
      _lastError = e.toString();
      rethrow;
    }
  }

  /// Generate a response for the current chat session
  Future<String> generateResponse({
    required GuideKind guide,
    required List<GuideChatMessage> messages,
  }) async {
    debugPrint('Generating response for guide: $guide');

    // Initialize if needed
    await initialize(guide);

    if (_activeChat == null) {
      throw StateError('Failed to initialize chat');
    }

    _isGenerating = true;

    try {
      // Get the last user message
      final lastUserMessage = messages.lastWhere(
        (m) => m.role == GuideChatMessageRole.user,
        orElse: () => messages.last,
      );

      debugPrint(
        'Sending: ${lastUserMessage.text.substring(0, lastUserMessage.text.length > 30 ? 30 : lastUserMessage.text.length)}...',
      );
      _lastPromptCharCount = lastUserMessage.text.length;

      // Add message to chat
      await _activeChat!.addQueryChunk(
        Message.text(text: lastUserMessage.text, isUser: true),
      );

      // Generate response
      final stopwatch = Stopwatch()..start();
      final response = await _activeChat!.generateChatResponse();
      stopwatch.stop();
      _lastGenerationDuration = stopwatch.elapsed;

      if (response is TextResponse) {
        debugPrint(
          'Response: ${response.token.substring(0, response.token.length > 30 ? 30 : response.token.length)}...',
        );
        _lastResponseCharCount = response.token.length;
        _lastPromptTokenCount = await _safeCountTokens(lastUserMessage.text);
        _lastResponseTokenCount = await _safeCountTokens(response.token);
        _lastError = null;
        return response.token;
      } else {
        throw StateError('Unexpected response type');
      }
    } catch (e, stack) {
      debugPrint('Error generating response: $e');
      debugPrint('Stack: $stack');
      _lastError = e.toString();
      rethrow;
    } finally {
      _isGenerating = false;
    }
  }

  /// Offload and free resources
  Future<void> offload() async {
    _activeChat = null;
    _activeGuide = null;
    _isGenerating = false;
    await _currentModel?.close();
    _currentModel = null;
    _activeModelPath = null;
    _activeModelFileType = null;
  }

  /// Dispose and cleanup all resources
  Future<void> dispose() async {
    await offload();
  }

  Future<void> _loadGuideModel(GuidePersonaDefinition definition) async {
    await _ensureGuideModelReady(definition);

    _currentModel = await FlutterGemma.getActiveModel(
      maxTokens: 1024,
      preferredBackend: _preferredBackendFor(definition),
    );
    debugPrint('Loaded active model for ${definition.name}');

    _activeChat = await _currentModel!.createChat(
      modelType: definition.flutterGemmaModelType,
      systemInstruction: definition.systemPrompt,
    );
    debugPrint('Created chat session for ${definition.name}');

    _activeGuide = definition.kind;
  }

  Future<void> _ensureGuideModelReady(
    GuidePersonaDefinition definition, {
    bool forceReinstall = false,
  }) async {
    final manager = FlutterGemmaPlugin.instance.modelManager;
    final spec = guideInferenceModelSpec(definition);

    if (forceReinstall) {
      await _deleteGuideModelIfPresent(manager, spec);
    }

    var isInstalled = await manager.isModelInstalled(spec);
    if (isInstalled) {
      final isValid = await validateInstalledGuideModel(definition);
      if (!isValid) {
        debugPrint(
          'Installed archive for ${definition.name} is invalid. Removing it.',
        );
        await _deleteGuideModelIfPresent(manager, spec);
        isInstalled = false;
      }
    }

    if (!isInstalled) {
      debugPrint('Installing model for ${definition.name}');
      await FlutterGemma.installModel(
            modelType: definition.flutterGemmaModelType,
            fileType: definition.modelFileType,
          )
          .fromNetwork(
            definition.modelDownloadUrl,
            token: definition.huggingFaceToken,
          )
          .install();

      final installedNow =
          await manager.isModelInstalled(spec) &&
          await validateInstalledGuideModel(definition);
      if (!installedNow) {
        await _deleteGuideModelIfPresent(manager, spec);
        throw StateError(
          'Downloaded ${definition.name}, but the model bundle is invalid.',
        );
      }
    }

    manager.setActiveModel(spec);

    final modelPath = await resolveInstalledGuideModelPath(definition);
    _activeModelPath = modelPath;
    _activeModelFileType = definition.modelFileType;
    debugPrint('Using unified model file: $modelPath');
  }

  Future<void> _deleteGuideModelIfPresent(
    ModelFileManager manager,
    InferenceModelSpec spec,
  ) async {
    if (await manager.isModelInstalled(spec)) {
      await manager.deleteModel(spec);
    }
  }

  bool _isZipArchiveError(Object error) {
    return error.toString().contains('Unable to open zip archive');
  }

  PreferredBackend _preferredBackendFor(GuidePersonaDefinition definition) {
    if (definition.kind == GuideKind.nova) {
      return PreferredBackend.cpu;
    }

    return PreferredBackend.gpu;
  }

  Future<int?> _safeCountTokens(String text) async {
    try {
      return await _currentModel?.session?.sizeInTokens(text);
    } catch (_) {
      return null;
    }
  }
}
