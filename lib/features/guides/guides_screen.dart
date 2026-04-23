import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../services/guide_chat_store.dart';
import '../../services/guide_model_manager.dart';
import '../../services/guide_runtime_service.dart';
import '../../services/guide_voice_service.dart';

class GuidesScreen extends ConsumerStatefulWidget {
  const GuidesScreen({super.key});

  @override
  ConsumerState<GuidesScreen> createState() => _GuidesScreenState();
}

class _GuidesScreenState extends ConsumerState<GuidesScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _composerController = TextEditingController();
  final ScrollController _messagesScrollController = ScrollController();
  final GuideRuntimeService _runtimeService = GuideRuntimeService();
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    // Auto-refresh model status when screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshModelStatus();
    });
  }

  Future<void> _refreshModelStatus() async {
    final manager = ref.read(guideModelManagerProvider);
    for (final guide in activeGuideKinds) {
      await manager.recheckModelStatus(guide);
    }
  }

  @override
  void dispose() {
    _composerController.dispose();
    _messagesScrollController.dispose();
    _runtimeService.dispose();
    super.dispose();
  }

  void _scheduleScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_messagesScrollController.hasClients) return;
      _messagesScrollController.animateTo(
        _messagesScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  void _openInfoPage(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GuideInfoScreen(runtimeService: _runtimeService),
      ),
    );
  }

  Future<void> _renameSession(
    BuildContext context,
    GuideChatStore store,
    GuideChatSession session,
  ) async {
    final controller = TextEditingController(text: session.title);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Rename chat'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 60,
            decoration: const InputDecoration(
              labelText: 'Chat name',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                await store.renameSession(
                  sessionId: session.id,
                  title: controller.text,
                );
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteSession(
    BuildContext context,
    GuideChatStore store,
    GuideChatSession session,
  ) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete chat?'),
          content: Text(
            'This will remove "${session.title}" from local storage on this device.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete == true) {
      await store.deleteSession(session.id);
    }
  }

  Future<void> _sendMessage(
    String text,
    GuideChatStore store,
    GuideKind guide,
  ) async {
    if (text.trim().isEmpty || _isGenerating) return;

    // Clear input immediately
    _composerController.clear();

    // Add user message to chat
    await store.sendMessage(text);
    _scheduleScrollToBottom();

    setState(() {
      _isGenerating = true;
    });

    final streamingEnabled = ref
        .read(guideModelManagerProvider)
        .streamingEnabled;
    final voiceService = ref.read(guideVoiceServiceProvider);
    String? draftMessageId;
    var latestResponse = '';
    var lastPersistAt = DateTime.now();

    try {
      if (streamingEnabled) {
        draftMessageId = await store.beginGuideResponseDraft();
        _scheduleScrollToBottom();

        // Track how much text has been sent to TTS for incremental speaking
        var spokenUpTo = 0;
        final sentenceEnd = RegExp(r'[.!?]\s+');

        await for (final partial in _runtimeService.streamResponse(
          guide: guide,
          messages: store.currentSession?.messages ?? [],
        )) {
          latestResponse = partial;
          final now = DateTime.now();
          final shouldPersist =
              now.difference(lastPersistAt) >=
              const Duration(milliseconds: 250);

          if (draftMessageId != null) {
            await store.updateGuideResponseDraft(
              draftMessageId,
              latestResponse,
              persist: shouldPersist,
            );
          }

          if (shouldPersist) {
            lastPersistAt = now;
          }

          // Incremental TTS: speak completed sentences as they stream in
          if (voiceService.voiceResponsesEnabled) {
            final unspoken = latestResponse.substring(spokenUpTo);
            final matches = sentenceEnd.allMatches(unspoken);
            if (matches.isNotEmpty) {
              final lastMatch = matches.last;
              final speakable = unspoken.substring(0, lastMatch.end).trim();
              if (speakable.isNotEmpty) {
                spokenUpTo += lastMatch.end;
                voiceService.queueSpeak(_plainTextForExport(speakable));
              }
            }
          }

          _scheduleScrollToBottom();
        }

        if (draftMessageId != null) {
          if (latestResponse.trim().isEmpty) {
            await store.removeGuideResponseDraft(draftMessageId);
          } else {
            await store.completeGuideResponseDraft(
              draftMessageId,
              latestResponse,
            );
          }
        }

        // Speak any remaining un-spoken text after streaming finishes
        if (voiceService.voiceResponsesEnabled) {
          final remaining = latestResponse.substring(spokenUpTo).trim();
          if (remaining.isNotEmpty) {
            voiceService.queueSpeak(_plainTextForExport(remaining));
          }
        }
      } else {
        latestResponse = await _runtimeService.generateResponse(
          guide: guide,
          messages: store.currentSession?.messages ?? [],
        );
        await store.addGuideResponse(latestResponse);
        _scheduleScrollToBottom();

        // Non-streaming: speak the full response at once
        if (latestResponse.trim().isNotEmpty &&
            voiceService.voiceResponsesEnabled) {
          unawaited(voiceService.speak(_plainTextForExport(latestResponse)));
        }
      }
    } catch (e, stack) {
      debugPrint('Error generating response: $e');
      debugPrint('Stack trace: $stack');
      if (draftMessageId != null) {
        final fallbackText = latestResponse.trim().isEmpty
            ? 'Error: $e'
            : '${latestResponse.trimRight()}\n\n[Generation interrupted: $e]';
        await store.completeGuideResponseDraft(draftMessageId, fallbackText);
      } else {
        await store.addGuideResponse('Error: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  Future<void> _toggleVoicePrompt(BuildContext context) async {
    final voiceService = ref.read(guideVoiceServiceProvider);
    final store = ref.read(guideChatStoreProvider);
    final selectedGuide = store.selectedGuide;

    try {
      if (voiceService.isRecording) {
        final transcript = await voiceService.stopRecordingAndTranscribe();
        if (transcript.trim().isNotEmpty) {
          // Auto-submit the transcribed voice prompt
          await _sendMessage(transcript.trim(), store, selectedGuide);
        }
      } else {
        await voiceService.startRecording();
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _speakGuideText(BuildContext context, String text) async {
    final voiceService = ref.read(guideVoiceServiceProvider);
    try {
      await voiceService.speak(_plainTextForExport(text));
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _copyMessage(BuildContext context, String text) async {
    final normalized = _plainTextForExport(text);
    if (normalized.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: normalized));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Message copied')));
    }
  }

  Future<void> _shareChatThrough(
    BuildContext context,
    GuideChatSession session,
    int messageIndex,
  ) async {
    final transcript = _buildTranscript(session, messageIndex);
    await SharePlus.instance.share(
      ShareParams(
        text: transcript,
        title: '${guidePersonaDefinitions[session.guide]!.name} chat export',
        subject:
            'SeekNirvana ${guidePersonaDefinitions[session.guide]!.name} chat',
      ),
    );
  }

  String _buildTranscript(GuideChatSession session, int messageIndex) {
    final persona = guidePersonaDefinitions[session.guide]!;
    final lines = <String>[
      'SeekNirvana Chat Export',
      'Guide: ${persona.name}',
      'Session: ${session.title}',
      'Exported: ${DateFormat.yMMMd().add_jm().format(DateTime.now())}',
      '',
    ];

    for (final message in session.messages.take(messageIndex + 1)) {
      final speaker = message.fromGuide ? persona.name : 'You';
      final text = _plainTextForExport(message.text);
      if (text.trim().isEmpty) {
        continue;
      }
      lines.add(
        '[${DateFormat.MMMd().add_jm().format(message.timestamp)}] $speaker: $text',
      );
      lines.add('');
    }

    return lines.join('\n').trim();
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(guideChatStoreProvider);
    final manager = ref.watch(guideModelManagerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final session = store.currentSession;
    final selectedGuide = store.selectedGuide;
    final persona = guidePersonaDefinitions[selectedGuide]!;
    final streamingEnabled = manager.streamingEnabled;
    final voiceService = ref.watch(guideVoiceServiceProvider);
    final hasUserMessage =
        session?.messages.any(
          (message) => message.role == GuideChatMessageRole.user,
        ) ??
        false;

    return Scaffold(
      key: _scaffoldKey,
      resizeToAvoidBottomInset: true,
      backgroundColor: isDark
          ? AppColors.backgroundDark
          : AppColors.backgroundLight,
      drawer: _GuideHistoryDrawer(
        store: store,
        onRenameSession: (session) => _renameSession(context, store, session),
        onDeleteSession: (session) => _deleteSession(context, store, session),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Compact header section
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                    icon: const Icon(Icons.menu_rounded, size: 22),
                    tooltip: 'Open chat history',
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          session?.title ?? persona.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          'Private · ${persona.modelLabel}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                fontSize: 11,
                                color: isDark
                                    ? AppColors.textSecondaryDark
                                    : AppColors.textSecondaryLight,
                              ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => _openInfoPage(context),
                    icon: const Icon(Icons.info_outline_rounded, size: 22),
                    tooltip: 'Guide setup and downloads',
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            if (activeGuideKinds.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                child: _GuideSelector(
                  selectedGuide: selectedGuide,
                  onGuideChanged: (guide) {
                    store.selectGuide(guide);
                    _runtimeService.offload();
                  },
                ),
              ),
            if (!hasUserMessage) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: _GuideHeroCard(persona: persona),
              ),
              const SizedBox(height: 6),
            ] else ...[
              const SizedBox(height: 6),
            ],
            Expanded(
              child: session == null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (manager.globalError != null) ...[
                            Icon(
                              Icons.error_outline_rounded,
                              size: 48,
                              color: AppColors.error,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Something went wrong',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              manager.globalError!,
                              style: Theme.of(context).textTheme.bodySmall,
                              textAlign: TextAlign.center,
                            ),
                          ] else if (!manager
                              .stateFor(selectedGuide)
                              .isReady) ...[
                            Icon(
                              Icons.download_outlined,
                              size: 48,
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondaryLight,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Download ${persona.name} to start chatting',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Go to Guide Setup to download the AI model',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ] else ...[
                            Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 48,
                              color: isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondaryLight,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Start a new chat with ${persona.name}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: () => store.startNewSession(),
                              icon: const Icon(Icons.add_comment_rounded),
                              label: const Text('Start New Chat'),
                            ),
                          ],
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _messagesScrollController,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: session.messages.length,
                      itemBuilder: (context, index) {
                        final message = session.messages[index];
                        return _ChatBubble(
                          message: message,
                          guideName: persona.name,
                          isSpeaking:
                              message.fromGuide && voiceService.isSpeaking,
                          onCopy: message.text.trim().isEmpty
                              ? null
                              : () => _copyMessage(context, message.text),
                          onShare: message.text.trim().isEmpty
                              ? null
                              : () =>
                                    _shareChatThrough(context, session, index),
                          onSpeak:
                              message.fromGuide &&
                                  message.text.trim().isNotEmpty
                              ? () => _speakGuideText(context, message.text)
                              : null,
                          onStopSpeaking:
                              message.fromGuide && voiceService.isSpeaking
                              ? voiceService.stopSpeaking
                              : null,
                        );
                      },
                    ),
            ),
            if (_isGenerating && !streamingEnabled)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: persona.name == 'Luna'
                            ? AppColors.sleep
                            : AppColors.hrv,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${persona.name} is thinking...',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            if (manager.runtimeDebugEnabled)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: _RuntimeDebugCard(runtimeService: _runtimeService),
              ),
            _ComposerBar(
              controller: _composerController,
              enabled:
                  manager.stateFor(selectedGuide).isReady &&
                  session != null &&
                  !_isGenerating,
              isRecording: voiceService.isRecording,
              isTranscribing: voiceService.isTranscribing,
              guideName: persona.name,
              hintText: _composerHint(
                selectedGuide,
                modelReady: manager.stateFor(selectedGuide).isReady,
                hasSession: session != null,
              ),
              onVoicePrompt: () => _toggleVoicePrompt(context),
              onSend: (text) => _sendMessage(text, store, selectedGuide),
            ),
          ],
        ),
      ),
    );
  }

  String _composerHint(
    GuideKind guide, {
    required bool modelReady,
    required bool hasSession,
  }) {
    final name = guidePersonaDefinitions[guide]!.name;
    if (!modelReady) {
      return 'Download $name\'s model to start chatting';
    }
    if (!hasSession) {
      return 'Start a new chat to message $name';
    }
    return 'Message $name...';
  }
}

class _GuideSelector extends StatelessWidget {
  final GuideKind selectedGuide;
  final ValueChanged<GuideKind> onGuideChanged;

  const _GuideSelector({
    required this.selectedGuide,
    required this.onGuideChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
        border: Border.all(
          color: isDark ? AppColors.cardBorderDark : AppColors.cardBorderLight,
        ),
      ),
      child: Row(
        children: activeGuideKinds.map((guide) {
          final isSelected = selectedGuide == guide;
          final persona = guidePersonaDefinitions[guide]!;
          final color = guide == GuideKind.luna
              ? AppColors.sleep
              : AppColors.hrv;

          return Expanded(
            child: GestureDetector(
              onTap: () => onGuideChanged(guide),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? color.withValues(alpha: isDark ? 0.25 : 0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(
                    AppConstants.radiusFull - 4,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      guide == GuideKind.luna
                          ? Icons.nightlight_round
                          : Icons.auto_awesome_rounded,
                      size: 18,
                      color: isSelected
                          ? color
                          : (isDark
                                ? AppColors.textSecondaryDark
                                : AppColors.textSecondaryLight),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      persona.name,
                      style: TextStyle(
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: isSelected
                            ? color
                            : (isDark
                                  ? AppColors.textSecondaryDark
                                  : AppColors.textSecondaryLight),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _GuideHeroCard extends StatelessWidget {
  final GuidePersonaDefinition persona;

  const _GuideHeroCard({required this.persona});

  Color get _accentColor {
    return persona.kind == GuideKind.luna ? AppColors.sleep : AppColors.hrv;
  }

  IconData get _icon {
    return persona.kind == GuideKind.luna
        ? Icons.nightlight_round
        : Icons.auto_awesome_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _accentColor.withValues(alpha: isDark ? 0.28 : 0.18),
            AppColors.primary.withValues(alpha: isDark ? 0.18 : 0.10),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppConstants.radiusXL),
        border: Border.all(color: _accentColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _accentColor.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(_icon, size: 20, color: _accentColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      persona.name,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      persona.shortDescription,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: persona.quickPrompts
                .map(
                  (prompt) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.cardDark.withValues(alpha: 0.6)
                          : Colors.white.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusFull,
                      ),
                    ),
                    child: Text(
                      prompt,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _RuntimeDebugCard extends StatelessWidget {
  final GuideRuntimeService runtimeService;

  const _RuntimeDebugCard({required this.runtimeService});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final path = runtimeService.activeModelPath;
    final load = runtimeService.lastInitializeDuration;
    final generate = runtimeService.lastGenerationDuration;
    final promptTokens = runtimeService.lastPromptTokenCount;
    final responseTokens = runtimeService.lastResponseTokenCount;
    final promptChars = runtimeService.lastPromptCharCount;
    final responseChars = runtimeService.lastResponseCharCount;
    final error = runtimeService.lastError;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        borderRadius: BorderRadius.circular(AppConstants.radiusLG),
        border: Border.all(
          color: isDark ? AppColors.cardBorderDark : AppColors.cardBorderLight,
        ),
      ),
      child: DefaultTextStyle(
        style: Theme.of(context).textTheme.bodySmall!,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Runtime Debug',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text('Active file: ${runtimeService.activeModelFileName ?? '--'}'),
            Text(
              'Bundle type: ${runtimeService.activeModelFileType?.name ?? '--'}',
            ),
            Text('Load time: ${_formatDuration(load)}'),
            Text('Last response: ${_formatDuration(generate)}'),
            Text(
              'Prompt: ${promptTokens?.toString() ?? '--'} tokens · ${promptChars?.toString() ?? '--'} chars',
            ),
            Text(
              'Reply: ${responseTokens?.toString() ?? '--'} tokens · ${responseChars?.toString() ?? '--'} chars',
            ),
            if (path != null) ...[
              const SizedBox(height: 6),
              Text(
                path,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
            if (error != null && error.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Last error: $error',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: AppColors.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final GuideChatMessage message;
  final String guideName;
  final bool isSpeaking;
  final VoidCallback? onCopy;
  final VoidCallback? onShare;
  final VoidCallback? onSpeak;
  final VoidCallback? onStopSpeaking;

  const _ChatBubble({
    required this.message,
    required this.guideName,
    this.isSpeaking = false,
    this.onCopy,
    this.onShare,
    this.onSpeak,
    this.onStopSpeaking,
  });

  @override
  Widget build(BuildContext context) {
    final isDraftGuideMessage =
        message.fromGuide && message.text.trim().isEmpty;

    return Align(
      alignment: message.fromGuide
          ? Alignment.centerLeft
          : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(AppConstants.spacingMD),
        constraints: const BoxConstraints(maxWidth: 340),
        decoration: BoxDecoration(
          color: message.fromGuide
              ? AppColors.hrv.withValues(alpha: 0.14)
              : AppColors.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppConstants.radiusLG),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isDraftGuideMessage)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$guideName is thinking...',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(height: 1.4),
                  ),
                ],
              )
            else
              MarkdownBody(
                data: message.text,
                selectable: true,
                styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                  p: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.4),
                  strong: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                  ),
                  em: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.4,
                    fontStyle: FontStyle.italic,
                  ),
                  code: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    backgroundColor: Theme.of(context).brightness == Brightness.dark
                        ? AppColors.cardDark
                        : AppColors.cardLight,
                  ),
                  blockquote: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    height: 1.4,
                    fontStyle: FontStyle.italic,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                  ),
                  listBullet: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.4),
                  h1: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  h2: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  h3: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    DateFormat.jm().format(message.timestamp),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight,
                    ),
                  ),
                ),
                if (!isDraftGuideMessage && onCopy != null)
                  IconButton(
                    onPressed: onCopy,
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    tooltip: 'Copy message',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    padding: EdgeInsets.zero,
                  ),
                if (!isDraftGuideMessage && onSpeak != null)
                  IconButton(
                    onPressed: isSpeaking ? onStopSpeaking : onSpeak,
                    icon: Icon(
                      isSpeaking
                          ? Icons.stop_circle_outlined
                          : Icons.volume_up_rounded,
                      size: 16,
                    ),
                    tooltip: isSpeaking ? 'Stop speaking' : 'Speak message',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    padding: EdgeInsets.zero,
                  ),
                if (!isDraftGuideMessage && onShare != null)
                  IconButton(
                    onPressed: onShare,
                    icon: const Icon(Icons.share_rounded, size: 16),
                    tooltip: 'Share chat up to here',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    padding: EdgeInsets.zero,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


String _plainTextForExport(String text) {
  var clean = text;
  
  // Remove headers
  clean = clean.replaceAll(RegExp(r'^#+\s+', multiLine: true), '');
  
  // Remove links but keep text
  clean = clean.replaceAll(RegExp(r'\[(.*?)\]\(.*?\)'), r'$1');
  
  // Remove bold/italics
  clean = clean.replaceAll(RegExp(r'\*\*(.*?)\*\*'), r'$1');
  clean = clean.replaceAll(RegExp(r'\*(.*?)\*'), r'$1');
  clean = clean.replaceAll(RegExp(r'__(.*?)__'), r'$1');
  clean = clean.replaceAll(RegExp(r'_(.*?)_'), r'$1');
  
  // Remove strikethrough
  clean = clean.replaceAll(RegExp(r'~~(.*?)~~'), r'$1');
  
  // Remove inline code
  clean = clean.replaceAll(RegExp(r'`(.*?)`'), r'$1');
  
  // Remove blockquotes
  clean = clean.replaceAll(RegExp(r'^\s*>\s*', multiLine: true), '');
  
  return clean.trim();
}

class _ComposerBar extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final bool isRecording;
  final bool isTranscribing;
  final String guideName;
  final String hintText;
  final VoidCallback onVoicePrompt;
  final ValueChanged<String> onSend;

  const _ComposerBar({
    required this.controller,
    required this.enabled,
    required this.isRecording,
    required this.isTranscribing,
    required this.guideName,
    required this.hintText,
    required this.onVoicePrompt,
    required this.onSend,
  });

  void _handleSend() {
    final text = controller.text;
    if (text.trim().isEmpty) return;
    onSend(text);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isRecording)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _RecordingIndicator(),
              ),
            if (isTranscribing)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Transcribing...',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight,
                      ),
                    ),
                  ],
                ),
              ),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
              decoration: BoxDecoration(
                color: isDark ? AppColors.cardDark : AppColors.cardLight,
                borderRadius: BorderRadius.circular(AppConstants.radiusXL),
                border: Border.all(
                  color: isRecording
                      ? AppColors.error.withValues(alpha: 0.5)
                      : (isDark
                            ? AppColors.cardBorderDark
                            : AppColors.cardBorderLight),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      minLines: 1,
                      maxLines: 5,
                      enabled: enabled && !isRecording,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _handleSend(),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: isRecording
                            ? 'Listening...'
                            : (enabled ? 'Message $guideName...' : hintText),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: isTranscribing
                        ? null
                        : ((enabled || isRecording) ? onVoicePrompt : null),
                    icon: isTranscribing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            isRecording
                                ? Icons.stop_circle_rounded
                                : Icons.mic_rounded,
                            color: isRecording ? AppColors.error : null,
                          ),
                    tooltip: isTranscribing
                        ? 'Transcribing voice prompt'
                        : (isRecording ? 'Stop recording' : 'Record voice prompt'),
                  ),
                  IconButton(
                    onPressed: enabled && !isRecording ? _handleSend : null,
                    icon: const Icon(Icons.send_rounded),
                    tooltip: 'Send message',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordingIndicator extends StatefulWidget {
  @override
  State<_RecordingIndicator> createState() => _RecordingIndicatorState();
}

class _RecordingIndicatorState extends State<_RecordingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Opacity(
              opacity: _animation.value,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: AppColors.error,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.error.withValues(alpha: 0.4),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Recording...',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _GuideHistoryDrawer extends StatelessWidget {
  final GuideChatStore store;
  final Future<void> Function(GuideChatSession session) onRenameSession;
  final Future<void> Function(GuideChatSession session) onDeleteSession;

  const _GuideHistoryDrawer({
    required this.store,
    required this.onRenameSession,
    required this.onDeleteSession,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedGuide = store.selectedGuide;
    final persona = guidePersonaDefinitions[selectedGuide]!;
    final sessions = store.sessionsForGuide(selectedGuide);
    final todaySessions = <GuideChatSession>[];
    final earlierSessions = <GuideChatSession>[];
    final now = DateTime.now();

    for (final session in sessions) {
      if (_isSameDay(session.updatedAt, now)) {
        todaySessions.add(session);
      } else {
        earlierSessions.add(session);
      }
    }

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
              child: Row(
                children: [
                  Text(
                    '${persona.name} Chats',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FilledButton.icon(
                onPressed: () async {
                  await store.startNewSession();
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
                icon: const Icon(Icons.edit_rounded),
                label: const Text('New chat'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppConstants.radiusLG),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  Text(
                    'History',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (todaySessions.isNotEmpty) ...[
                    _HistorySectionLabel(label: 'Today'),
                    const SizedBox(height: 8),
                    ...todaySessions.map(
                      (session) => _SessionTile(
                        session: session,
                        selected: session.id == store.selectedSessionId,
                        onTap: () {
                          store.selectSession(session.id);
                          Navigator.of(context).pop();
                        },
                        onRename: () => onRenameSession(session),
                        onDelete: () => onDeleteSession(session),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (earlierSessions.isNotEmpty) ...[
                    _HistorySectionLabel(label: 'Earlier'),
                    const SizedBox(height: 8),
                    ...earlierSessions.map(
                      (session) => _SessionTile(
                        session: session,
                        selected: session.id == store.selectedSessionId,
                        onTap: () {
                          store.selectSession(session.id);
                          Navigator.of(context).pop();
                        },
                        onRename: () => onRenameSession(session),
                        onDelete: () => onDeleteSession(session),
                      ),
                    ),
                  ],
                  if (sessions.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.cardDark
                            : AppColors.cardLight,
                        borderRadius: BorderRadius.circular(
                          AppConstants.radiusLG,
                        ),
                      ),
                      child: const Text('No chats yet. Start a new one above.'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

class _HistorySectionLabel extends StatelessWidget {
  final String label;

  const _HistorySectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(
        context,
      ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

class _SessionTile extends StatelessWidget {
  final GuideChatSession session;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _SessionTile({
    required this.session,
    required this.selected,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppConstants.radiusLG),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppConstants.radiusLG),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    session.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onRename,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  splashRadius: 18,
                  tooltip: 'Rename chat',
                ),
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  splashRadius: 18,
                  tooltip: 'Delete chat',
                ),
              ],
            ),
            Text(
              DateFormat.MMMd().add_jm().format(session.updatedAt),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class GuideInfoScreen extends ConsumerWidget {
  final GuideRuntimeService runtimeService;

  const GuideInfoScreen({super.key, required this.runtimeService});

  Future<void> _confirmClearChats(
    BuildContext context,
    GuideChatStore store, {
    GuideKind? guide,
  }) async {
    final label = guide == null
        ? 'all saved chats'
        : '${guidePersonaDefinitions[guide]!.name} chats';
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete saved chats?'),
          content: Text(
            'This will remove $label from local storage on this device.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete == true) {
      await store.clearSessions(guide: guide);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.watch(guideModelManagerProvider);
    final store = ref.watch(guideChatStoreProvider);
    final voiceService = ref.watch(guideVoiceServiceProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.backgroundDark
          : AppColors.backgroundLight,
      appBar: AppBar(title: const Text('Guide Setup')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: manager.runtimeDebugEnabled,
              onChanged: manager.setRuntimeDebugEnabled,
              title: const Text('Runtime Debug'),
              subtitle: const Text(
                'Show the model file, timings, and last runtime error on Luna and Nova.',
              ),
            ),
            if (!Platform.isIOS)
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: manager.streamingEnabled,
                onChanged: manager.setStreamingEnabled,
                title: const Text('Streaming Responses'),
                subtitle: const Text(
                  'Show replies as they arrive. Turn this off to wait for the full response and show the thinking state above the composer.',
                ),
              ),
            const SizedBox(height: 12),
            _GuideVoiceSettingsCard(voiceService: voiceService, isDark: isDark),
            const SizedBox(height: 12),
            for (var index = 0; index < activeGuideKinds.length; index++) ...[
              _GuideSetupCard(
                guide: activeGuideKinds[index],
                manager: manager,
                isDark: isDark,
              ),
              if (index < activeGuideKinds.length - 1)
                const SizedBox(height: 16),
            ],
            if (manager.runtimeDebugEnabled) ...[
              const SizedBox(height: 16),
              _RuntimeDebugCard(runtimeService: runtimeService),
            ],
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? AppColors.cardDark : AppColors.cardLight,
                borderRadius: BorderRadius.circular(AppConstants.radiusXL),
                border: Border.all(
                  color: isDark
                      ? AppColors.cardBorderDark
                      : AppColors.cardBorderLight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Saved Chats',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Delete locally stored sessions if you want a clean slate or a lighter backup.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(height: 1.4),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _confirmClearChats(
                          context,
                          store,
                          guide: GuideKind.luna,
                        ),
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('Clear Luna chats'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _confirmClearChats(
                          context,
                          store,
                          guide: GuideKind.nova,
                        ),
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('Clear Nova chats'),
                      ),
                      FilledButton.icon(
                        onPressed: () => _confirmClearChats(context, store),
                        icon: const Icon(Icons.delete_sweep_rounded),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.error,
                        ),
                        label: const Text('Clear all chats'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _GuideStorageInfoCard(manager: manager, isDark: isDark),
          ],
        ),
      ),
    );
  }
}

class _GuideVoiceSettingsCard extends StatelessWidget {
  final GuideVoiceService voiceService;
  final bool isDark;

  const _GuideVoiceSettingsCard({
    required this.voiceService,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        borderRadius: BorderRadius.circular(AppConstants.radiusXL),
        border: Border.all(
          color: isDark ? AppColors.cardBorderDark : AppColors.cardBorderLight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Voice',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Text(
            'Use on-device Whisper for spoken prompts and native system voices for guide replies.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4),
          ),
          const SizedBox(height: 12),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: voiceService.voiceResponsesEnabled,
            onChanged: voiceService.setVoiceResponsesEnabled,
            title: const Text('Speak guide replies'),
            subtitle: const Text(
              'Automatically read Luna and Nova responses out loud after they finish.',
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<WhisperModel>(
            initialValue: voiceService.whisperModel,
            decoration: const InputDecoration(
              labelText: 'Speech recognition model',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: WhisperModel.tiny, child: Text('Tiny')),
              DropdownMenuItem(value: WhisperModel.base, child: Text('Base')),
              DropdownMenuItem(value: WhisperModel.small, child: Text('Small')),
            ],
            onChanged: (value) {
              if (value != null) {
                voiceService.setWhisperModel(value);
              }
            },
          ),
          const SizedBox(height: 12),
          if (voiceService.hasVoices) ...[
            DropdownButtonFormField<String>(
              initialValue: voiceService.selectedVoice?.stableId,
              decoration: const InputDecoration(
                labelText: 'Voice',
                border: OutlineInputBorder(),
              ),
              items: voiceService.voices
                  .map(
                    (voice) => DropdownMenuItem<String>(
                      value: voice.stableId,
                      child: Text(voice.label, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: (selectedId) {
                final selected = voiceService.voices
                    .cast<GuideVoiceOption?>()
                    .firstWhere(
                      (voice) => voice?.stableId == selectedId,
                      orElse: () => null,
                    );
                voiceService.setSelectedVoice(selected);
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: voiceService.isSpeaking
                      ? voiceService.stopSpeaking
                      : voiceService.previewVoice,
                  icon: Icon(
                    voiceService.isSpeaking
                        ? Icons.stop_rounded
                        : Icons.play_arrow_rounded,
                    size: 18,
                  ),
                  label: Text(
                    voiceService.isSpeaking
                        ? 'Stop preview'
                        : 'Preview voice',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    voiceService.selectedVoice?.label ?? 'No voice selected',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ] else
            Text(
              'No system voices are currently available to choose from on this device.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(height: 12),
          FutureBuilder<bool>(
            future: voiceService.isWhisperModelReady(),
            builder: (context, snapshot) {
              final whisperReady = snapshot.data ?? false;
              final isDownloading = voiceService.isPreparingWhisperModel;
              final progress = voiceService.whisperDownloadProgress;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Speech model',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${voiceService.whisperModel.modelName} · ${whisperReady ? 'Downloaded' : (isDownloading ? 'Downloading…' : 'Not downloaded')}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (isDownloading) ...[
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: progress > 0 ? progress : null,
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                      color: AppColors.primary,
                      backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      progress > 0
                          ? 'Downloading... ${(progress * 100).toInt()}%'
                          : 'Starting download...',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 4),
                  FutureBuilder<String>(
                    future: voiceService.whisperModelPath(),
                    builder: (context, pathSnapshot) {
                      return Text(
                        pathSnapshot.data ?? 'Preparing speech model path…',
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: isDownloading
                            ? null
                            : () => voiceService.preloadWhisperModel(
                                force: whisperReady,
                              ),
                        icon: isDownloading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.download_rounded),
                        label: Text(
                          whisperReady
                              ? 'Redownload speech model'
                              : 'Download speech model',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FutureBuilder<int>(
                          future: voiceService.whisperModelBytes(),
                          builder: (context, sizeSnapshot) {
                            final bytes = sizeSnapshot.data ?? 0;
                            return Text(
                              bytes > 0
                                  ? 'Local size: ${_GuideStorageInfoCard.formatBytes(bytes)}'
                                  : 'Speech model not on device yet',
                              style: Theme.of(context).textTheme.bodySmall,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: voiceService.refreshVoices,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Refresh voices'),
              ),
              const SizedBox(width: 12),
              if (voiceService.lastError != null &&
                  voiceService.lastError!.isNotEmpty)
                Expanded(
                  child: Text(
                    voiceService.lastError!,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppColors.error),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GuideStorageInfoCard extends StatelessWidget {
  final GuideModelManager manager;
  final bool isDark;

  const _GuideStorageInfoCard({required this.manager, required this.isDark});

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }
    final decimals = value >= 10 || unitIndex == 0 ? 0 : 1;
    return '${value.toStringAsFixed(decimals)} ${units[unitIndex]}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        borderRadius: BorderRadius.circular(AppConstants.radiusXL),
        border: Border.all(
          color: isDark ? AppColors.cardBorderDark : AppColors.cardBorderLight,
        ),
      ),
      child: FutureBuilder<GuideStorageSnapshot>(
        future: manager.loadStorageSnapshot(),
        builder: (context, snapshot) {
          final storage = snapshot.data;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Storage Info',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Text(
                'Guide chats and downloaded model files stay on this device. This shows the actual local paths and current disk usage.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(height: 1.4),
              ),
              const SizedBox(height: 12),
              if (snapshot.connectionState == ConnectionState.waiting)
                Text(
                  'Calculating storage usage...',
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else ...[
                _StorageInfoRow(
                  label: 'Total used',
                  value: storage == null
                      ? '--'
                      : formatBytes(storage.totalBytes),
                ),
                _StorageInfoRow(
                  label: 'Guide models',
                  value: storage == null
                      ? '--'
                      : formatBytes(storage.guideModelBytes),
                ),
                _StorageInfoRow(
                  label: 'Voice cache',
                  value: storage == null
                      ? '--'
                      : formatBytes(storage.voiceBytes),
                ),
                _StorageInfoRow(
                  label: 'Whisper model',
                  value: storage == null
                      ? '--'
                      : formatBytes(storage.whisperModelBytes),
                ),
                _StorageInfoRow(
                  label: 'Chats',
                  value: storage == null
                      ? '--'
                      : formatBytes(storage.chatBytes),
                ),
                _StorageInfoRow(
                  label: 'Chat DB',
                  value: storage == null
                      ? '--'
                      : formatBytes(storage.databaseBytes),
                ),
                const SizedBox(height: 12),
                _StoragePathBlock(
                  title: 'Storage root',
                  path: storage?.rootPath,
                ),
                const SizedBox(height: 10),
                _StoragePathBlock(
                  title: 'Whisper folder',
                  path: storage?.whisperModelPath,
                ),
                const SizedBox(height: 10),
                if (storage != null && storage.guideModelPaths.isNotEmpty) ...[
                  for (final path in storage.guideModelPaths) ...[
                    _StoragePathBlock(title: 'Guide model bundle', path: path),
                    const SizedBox(height: 10),
                  ],
                ],
                _StoragePathBlock(
                  title: 'Voice cache',
                  path: storage?.voicePath,
                ),
                const SizedBox(height: 10),
                _StoragePathBlock(
                  title: 'Chats database',
                  path: storage?.chatDatabasePath,
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _StorageInfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _StorageInfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _StoragePathBlock extends StatelessWidget {
  final String title;
  final String? path;

  const _StoragePathBlock({required this.title, required this.path});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        SelectableText(
          path ?? 'Unavailable',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

class _GuideSetupCard extends StatelessWidget {
  final GuideKind guide;
  final GuideModelManager manager;
  final bool isDark;

  const _GuideSetupCard({
    required this.guide,
    required this.manager,
    required this.isDark,
  });

  Color get _accentColor {
    return guide == GuideKind.luna ? AppColors.sleep : AppColors.hrv;
  }

  IconData get _icon {
    return guide == GuideKind.luna
        ? Icons.nightlight_round
        : Icons.auto_awesome_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final state = manager.stateFor(guide);
    final persona = guidePersonaDefinitions[guide]!;
    final isDownloading = state.status == GuideModelStatus.downloading;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        borderRadius: BorderRadius.circular(AppConstants.radiusXL),
        border: Border.all(color: _accentColor.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_icon, color: _accentColor),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      persona.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${persona.title} · ${persona.modelLabel}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              _InfoStatusPill(label: state.statusLabel, color: _accentColor),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            persona.tooltipSummary,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(height: 1.45),
          ),
          if (isDownloading) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: state.progress == 0 ? null : state.progress,
              minHeight: 8,
              borderRadius: BorderRadius.circular(AppConstants.radiusFull),
              color: _accentColor,
              backgroundColor: _accentColor.withValues(alpha: 0.12),
            ),
            const SizedBox(height: 8),
            Text(
              'Downloading... ${(state.progress * 100).toInt()}%',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (state.errorMessage != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppConstants.radiusMD),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 18,
                    color: AppColors.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Download failed. Please check your connection and try again.',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: AppColors.error),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (state.status == GuideModelStatus.ready) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => manager.deleteModel(guide),
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Remove model'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () async {
                      await manager.deleteModel(guide);
                      await manager.downloadModel(guide);
                    },
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Redownload'),
                  ),
                ),
              ],
            ),
          ] else ...[
            Row(
              children: [
                if (state.status == GuideModelStatus.failed) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isDownloading
                          ? null
                          : () => manager.deleteModel(guide),
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Remove'),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: FilledButton.icon(
                    onPressed: isDownloading
                        ? null
                        : () async {
                            if (state.status == GuideModelStatus.failed) {
                              await manager.deleteModel(guide);
                            }
                            await manager.downloadModel(guide);
                          },
                    icon: Icon(
                      isDownloading
                          ? Icons.downloading
                          : state.status == GuideModelStatus.failed
                          ? Icons.refresh_rounded
                          : Icons.download_rounded,
                    ),
                    label: Text(
                      isDownloading
                          ? 'Downloading...'
                          : state.status == GuideModelStatus.failed
                          ? 'Redownload ${persona.name}'
                          : 'Download ${persona.name}',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoStatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _InfoStatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

String _formatDuration(Duration? duration) {
  if (duration == null) {
    return '--';
  }

  if (duration.inMilliseconds < 1000) {
    return '${duration.inMilliseconds} ms';
  }

  return '${(duration.inMilliseconds / 1000).toStringAsFixed(2)} s';
}
