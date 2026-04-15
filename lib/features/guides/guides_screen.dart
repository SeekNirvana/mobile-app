import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../services/guide_chat_store.dart';
import '../../services/guide_model_manager.dart';
import '../../services/guide_runtime_service.dart';

class GuidesScreen extends ConsumerStatefulWidget {
  const GuidesScreen({super.key});

  @override
  ConsumerState<GuidesScreen> createState() => _GuidesScreenState();
}

class _GuidesScreenState extends ConsumerState<GuidesScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _composerController = TextEditingController();
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
    _runtimeService.dispose();
    super.dispose();
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

  Future<void> _sendMessage(
    String text,
    GuideChatStore store,
    GuideChatSession session,
    GuideKind guide,
  ) async {
    if (text.trim().isEmpty || _isGenerating) return;

    // Clear input immediately
    _composerController.clear();

    // Add user message to chat
    await store.sendMessage(text);

    setState(() {
      _isGenerating = true;
    });

    try {
      // Generate AI response
      final response = await _runtimeService.generateResponse(
        guide: guide,
        messages: store.currentSession?.messages ?? [],
      );

      // Add guide response to chat
      await store.addGuideResponse(response);
    } catch (e, stack) {
      debugPrint('Error generating response: $e');
      debugPrint('Stack trace: $stack');
      // Show error in chat for debugging
      await store.addGuideResponse('Error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(guideChatStoreProvider);
    final manager = ref.watch(guideModelManagerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final session = store.currentSession;
    final selectedGuide = store.selectedGuide;
    final persona = guidePersonaDefinitions[selectedGuide]!;

    return Scaffold(
      key: _scaffoldKey,
      resizeToAvoidBottomInset: true,
      backgroundColor: isDark
          ? AppColors.backgroundDark
          : AppColors.backgroundLight,
      drawer: _GuideHistoryDrawer(
        store: store,
        onRenameSession: (session) => _renameSession(context, store, session),
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
                          '${persona.name} · ${persona.modelLabel}',
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
            // Guide Hero Card - hide if no session to save space
            if (session == null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: _GuideHeroCard(persona: persona),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: _GuideStatusBanner(
                  manager: manager,
                  selectedGuide: selectedGuide,
                  onOpenInfo: () => _openInfoPage(context),
                ),
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
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: session.messages.length,
                      itemBuilder: (context, index) {
                        final message = session.messages[index];
                        return _ChatBubble(message: message);
                      },
                    ),
            ),
            if (_isGenerating)
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
              guideName: persona.name,
              hintText: _composerHint(
                selectedGuide,
                modelReady: manager.stateFor(selectedGuide).isReady,
                hasSession: session != null,
              ),
              onSend: (text) =>
                  _sendMessage(text, store, session!, selectedGuide),
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

class _GuideStatusBanner extends StatelessWidget {
  final GuideModelManager manager;
  final GuideKind selectedGuide;
  final VoidCallback onOpenInfo;

  const _GuideStatusBanner({
    required this.manager,
    required this.selectedGuide,
    required this.onOpenInfo,
  });

  @override
  Widget build(BuildContext context) {
    final state = manager.stateFor(selectedGuide);
    final persona = guidePersonaDefinitions[selectedGuide]!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final downloaded = state.status == GuideModelStatus.ready;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: downloaded
            ? AppColors.info.withValues(alpha: isDark ? 0.16 : 0.08)
            : AppColors.warning.withValues(alpha: isDark ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(AppConstants.radiusLG),
        border: Border.all(
          color: downloaded
              ? AppColors.info.withValues(alpha: 0.32)
              : AppColors.warning.withValues(alpha: 0.32),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            downloaded ? Icons.memory_rounded : Icons.download_rounded,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              downloaded
                  ? '${persona.name}\'s AI model is downloaded and ready for local, private chat.'
                  : 'Download ${persona.name}\'s AI model from the info page to enable private, on-device conversations.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(height: 1.35),
            ),
          ),
          if (!downloaded) ...[
            const SizedBox(width: 12),
            TextButton(onPressed: onOpenInfo, child: const Text('Open')),
          ],
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

  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
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
            Text(
              message.text,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(height: 1.4),
            ),
            const SizedBox(height: 8),
            Text(
              DateFormat.jm().format(message.timestamp),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComposerBar extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final String guideName;
  final String hintText;
  final ValueChanged<String> onSend;

  const _ComposerBar({
    required this.controller,
    required this.enabled,
    required this.guideName,
    required this.hintText,
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
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          decoration: BoxDecoration(
            color: isDark ? AppColors.cardDark : AppColors.cardLight,
            borderRadius: BorderRadius.circular(AppConstants.radiusXL),
            border: Border.all(
              color: isDark
                  ? AppColors.cardBorderDark
                  : AppColors.cardBorderLight,
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
                  enabled: enabled,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _handleSend(),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: enabled ? 'Message $guideName...' : hintText,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: enabled ? _handleSend : null,
                icon: const Icon(Icons.send_rounded),
                tooltip: 'Send message',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuideHistoryDrawer extends StatelessWidget {
  final GuideChatStore store;
  final Future<void> Function(GuideChatSession session) onRenameSession;

  const _GuideHistoryDrawer({
    required this.store,
    required this.onRenameSession,
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

  const _SessionTile({
    required this.session,
    required this.selected,
    required this.onTap,
    required this.onRename,
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.watch(guideModelManagerProvider);
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
            // Storage Info
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
                    'Storage Info',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Chat history is stored locally in the app. AI models are downloaded on-demand using flutter_gemma.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(height: 1.4),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Models: ~1-4GB each',
                    style: Theme.of(context).textTheme.bodySmall,
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
