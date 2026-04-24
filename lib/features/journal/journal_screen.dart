import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../services/guide_model_manager.dart';
import '../../services/guide_runtime_service.dart';
import '../../services/guide_voice_service.dart';
import '../../services/journal_service.dart';

class JournalScreen extends ConsumerStatefulWidget {
  const JournalScreen({super.key});

  @override
  ConsumerState<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends ConsumerState<JournalScreen> {
  final GuideRuntimeService _runtimeService = GuideRuntimeService();
  String? _workingEntryId;
  bool _isCapturingDream = false;

  @override
  void dispose() {
    _runtimeService.dispose();
    super.dispose();
  }

  Future<void> _openComposer({
    JournalEntry? entry,
    JournalEntryType? type,
  }) async {
    final result = await showModalBottomSheet<_JournalDraftResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _JournalComposerSheet(
        initialEntry: entry,
        initialType: type ?? entry?.type ?? JournalEntryType.dream,
      ),
    );

    if (result == null) return;
    final saved = await ref
        .read(journalServiceProvider)
        .saveEntry(
          id: entry?.id,
          type: result.type,
          title: result.title,
          content: result.content,
          tags: result.tags,
        );
    if (!mounted) return;
    _openEntry(saved.id);
  }

  Future<void> _toggleWakeCapture() async {
    final voiceService = ref.read(guideVoiceServiceProvider);
    try {
      if (voiceService.isRecording) {
        final transcript = await voiceService.stopRecordingAndTranscribe();
        final entry = await ref
            .read(journalServiceProvider)
            .saveEntry(
              type: JournalEntryType.dream,
              title: '',
              content: transcript,
            );
        if (!mounted) return;
        setState(() => _isCapturingDream = false);
        _showSnack('Dream saved locally');
        _openEntry(entry.id);
      } else {
        setState(() => _isCapturingDream = true);
        await voiceService.startRecording();
        _showSnack('Recording dream narration...');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _isCapturingDream = false);
      }
      _showSnack(error.toString());
    }
  }

  Future<void> _shareEntry(JournalEntry entry) async {
    final payload =
        '${entry.title}\n${DateFormat.yMMMd().add_jm().format(entry.updatedAt)}\n\n${entry.content}';
    await SharePlus.instance.share(ShareParams(text: payload));
  }

  Future<void> _deleteEntry(JournalEntry entry) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete entry?'),
        content: Text('This will remove "${entry.title}" from your journal.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (shouldDelete == true) {
      await ref.read(journalServiceProvider).deleteEntry(entry.id);
    }
  }

  Future<void> _refineEntry(
    JournalEntry entry,
    GuideKind guide,
    GuideModelManager manager,
  ) async {
    if (_workingEntryId != null) return;
    if (!manager.stateFor(guide).isReady) {
      _showSnack('${guidePersonaDefinitions[guide]!.name} is not ready yet.');
      return;
    }

    setState(() => _workingEntryId = entry.id);
    try {
      final guideName = guidePersonaDefinitions[guide]!.name;
      final refined = await _runtimeService.generateResponse(
        guide: guide,
        messages: const [],
        userOverride:
            'Refine this ${entry.type.name} journal entry. Preserve the emotional truth, keep it personal, make it clearer and more elegant, and return only the improved entry text.\n\nTitle: ${entry.title}\n\n${entry.content}',
      );
      final saved = await ref
          .read(journalServiceProvider)
          .saveEntry(
            id: entry.id,
            type: entry.type,
            title: entry.title,
            content: refined,
            tags: entry.tags,
            novaAnalysis: entry.novaAnalysis,
          );
      if (!mounted) return;
      _showSnack('Refined with $guideName');
      _openEntry(saved.id);
    } catch (error) {
      _showSnack('Unable to refine entry: $error');
    } finally {
      if (mounted) {
        setState(() => _workingEntryId = null);
      }
    }
  }

  void _converseWithGuide(JournalEntry entry, GuideKind guide) {
    final prompt =
        'I want to talk about this ${entry.type.name} journal entry.\n\nTitle: ${entry.title}\n\n${entry.content}';
    context.go(
      '/guides?guide=${guide.name}&prompt=${Uri.encodeComponent(prompt)}',
    );
  }

  void _openEntry(String entryId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => JournalEntryScreen(entryId: entryId),
      ),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(journalServiceProvider).entries;
    final manager = ref.watch(guideModelManagerProvider);
    final voiceService = ref.watch(guideVoiceServiceProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.screenGradient(isDark)),
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Journal',
                        style: Theme.of(context).textTheme.displaySmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Capture dreams the moment they surface, then refine and explore them with your guides.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 18),
                      _JournalHero(
                        entryCount: entries.length,
                        isRecording:
                            voiceService.isRecording || _isCapturingDream,
                        isTranscribing: voiceService.isTranscribing,
                        onWakeCapture: _toggleWakeCapture,
                        onDream: () =>
                            _openComposer(type: JournalEntryType.dream),
                        onReflection: () =>
                            _openComposer(type: JournalEntryType.reflection),
                        onIdea: () =>
                            _openComposer(type: JournalEntryType.idea),
                      ),
                    ],
                  ),
                ),
              ),
              if (entries.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.nightlight_round,
                            size: 52,
                            color: AppColors.gold.withValues(alpha: 0.9),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Nothing stored yet',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Use Wake Capture to narrate a dream immediately, or add a quiet reflection in your own time.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                  sliver: SliverList.separated(
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final isWorking = _workingEntryId == entry.id;
                      return _JournalEntryCard(
                        entry: entry,
                        isWorking: isWorking,
                        onOpen: () => _openEntry(entry.id),
                        onEdit: () => _openComposer(entry: entry),
                        onShare: () => _shareEntry(entry),
                        onDelete: () => _deleteEntry(entry),
                        onRefineLuna: () =>
                            _refineEntry(entry, GuideKind.luna, manager),
                        onRefineNova: () =>
                            _refineEntry(entry, GuideKind.nova, manager),
                        onConverseLuna: () =>
                            _converseWithGuide(entry, GuideKind.luna),
                        onConverseNova: () =>
                            _converseWithGuide(entry, GuideKind.nova),
                      );
                    },
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 14),
                    itemCount: entries.length,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class JournalEntryScreen extends ConsumerStatefulWidget {
  final String entryId;

  const JournalEntryScreen({super.key, required this.entryId});

  @override
  ConsumerState<JournalEntryScreen> createState() => _JournalEntryScreenState();
}

class _JournalEntryScreenState extends ConsumerState<JournalEntryScreen> {
  final GuideRuntimeService _runtimeService = GuideRuntimeService();
  bool _isAnalyzing = false;
  bool _isRecording = false;

  @override
  void dispose() {
    _runtimeService.dispose();
    super.dispose();
  }

  Future<void> _analyzeWithNova(
    JournalEntry entry,
    GuideModelManager manager,
  ) async {
    if (_isAnalyzing) return;
    if (!manager.stateFor(GuideKind.nova).isReady) {
      _showSnack('Nova is not ready yet.');
      return;
    }
    setState(() => _isAnalyzing = true);
    try {
      final analysis = await _runtimeService.generateResponse(
        guide: GuideKind.nova,
        messages: const [],
        userOverride:
            'Analyze this ${entry.type.name} journal entry with empathy and clarity. Share likely themes, emotional signals, symbolic patterns if relevant, and one grounded suggestion. Keep it reflective and concise.\n\nTitle: ${entry.title}\n\n${entry.content}',
      );
      await ref
          .read(journalServiceProvider)
          .updateNovaAnalysis(entryId: entry.id, analysis: analysis);
      _showSnack('Nova analysis saved');
    } catch (error) {
      _showSnack('Unable to analyze entry: $error');
    } finally {
      if (mounted) {
        setState(() => _isAnalyzing = false);
      }
    }
  }

  Future<void> _appendVoiceNarration(JournalEntry entry) async {
    final voiceService = ref.read(guideVoiceServiceProvider);
    try {
      if (voiceService.isRecording) {
        final transcript = await voiceService.stopRecordingAndTranscribe();
        final combined = '${entry.content}\n\n$transcript'.trim();
        await ref
            .read(journalServiceProvider)
            .saveEntry(
              id: entry.id,
              type: entry.type,
              title: entry.title,
              content: combined,
              tags: entry.tags,
              novaAnalysis: entry.novaAnalysis,
            );
        if (!mounted) return;
        setState(() => _isRecording = false);
        _showSnack('Narration added');
      } else {
        setState(() => _isRecording = true);
        await voiceService.startRecording();
        _showSnack('Recording narration...');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _isRecording = false);
      }
      _showSnack(error.toString());
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final entry = ref.watch(journalServiceProvider).entryById(widget.entryId);
    final manager = ref.watch(guideModelManagerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (entry == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Journal Entry')),
        body: const Center(child: Text('Entry not found')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(entry.title)),
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.screenGradient(isDark)),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: AppColors.premiumPanelDecoration(isDark),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('MMMM d, y • h:mm a').format(entry.updatedAt),
                      style: Theme.of(
                        context,
                      ).textTheme.labelMedium?.copyWith(color: AppColors.gold),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      entry.content,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.copyWith(height: 1.7),
                    ),
                    if (entry.tags.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: entry.tags
                            .map(
                              (tag) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.cyanHint.withValues(
                                    alpha: 0.08,
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    AppConstants.radiusFull,
                                  ),
                                ),
                                child: Text('#$tag'),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: AppColors.premiumPanelDecoration(isDark),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Nova analysis',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: _isAnalyzing
                              ? null
                              : () => _analyzeWithNova(entry, manager),
                          icon: _isAnalyzing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.insights_rounded),
                          label: Text(
                            entry.novaAnalysis == null ? 'Analyze' : 'Refresh',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      entry.novaAnalysis?.trim().isNotEmpty == true
                          ? entry.novaAnalysis!
                          : 'Ask Nova to read themes, symbols, and emotional patterns from this entry.',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(height: 1.6),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: () => _appendVoiceNarration(entry),
                    icon: Icon(
                      _isRecording
                          ? Icons.stop_circle_outlined
                          : Icons.mic_rounded,
                    ),
                    label: Text(
                      _isRecording ? 'Stop narration' : 'Add narration',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => context.go(
                      '/guides?guide=luna&prompt=${Uri.encodeComponent('Help me reflect on this ${entry.type.name} journal entry.\n\nTitle: ${entry.title}\n\n${entry.content}')}',
                    ),
                    icon: const Icon(Icons.nightlight_round),
                    label: const Text('Converse with Luna'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => context.go(
                      '/guides?guide=nova&prompt=${Uri.encodeComponent('Help me reflect on this ${entry.type.name} journal entry.\n\nTitle: ${entry.title}\n\n${entry.content}')}',
                    ),
                    icon: const Icon(Icons.auto_awesome_rounded),
                    label: const Text('Converse with Nova'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JournalHero extends StatelessWidget {
  final int entryCount;
  final bool isRecording;
  final bool isTranscribing;
  final VoidCallback onWakeCapture;
  final VoidCallback onDream;
  final VoidCallback onReflection;
  final VoidCallback onIdea;

  const _JournalHero({
    required this.entryCount,
    required this.isRecording,
    required this.isTranscribing,
    required this.onWakeCapture,
    required this.onDream,
    required this.onReflection,
    required this.onIdea,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppColors.premiumPanelDecoration(
        Theme.of(context).brightness == Brightness.dark,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$entryCount local entries',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: AppColors.gold),
          ),
          const SizedBox(height: 8),
          Text(
            'Wake Capture is the fastest path: narrate first, organize later.',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: isTranscribing ? null : onWakeCapture,
            icon: isTranscribing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    isRecording
                        ? Icons.stop_circle_outlined
                        : Icons.mic_rounded,
                  ),
            label: Text(
              isTranscribing
                  ? 'Transcribing dream...'
                  : isRecording
                  ? 'Stop and save dream'
                  : 'Wake Capture dream',
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: onDream,
                icon: const Icon(Icons.edit_note_rounded),
                label: const Text('Write dream'),
              ),
              FilledButton.tonalIcon(
                onPressed: onReflection,
                icon: const Icon(Icons.self_improvement_rounded),
                label: const Text('Reflection'),
              ),
              FilledButton.tonalIcon(
                onPressed: onIdea,
                icon: const Icon(Icons.lightbulb_rounded),
                label: const Text('Mindful idea'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _JournalEntryCard extends StatelessWidget {
  final JournalEntry entry;
  final bool isWorking;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onShare;
  final VoidCallback onDelete;
  final VoidCallback onRefineLuna;
  final VoidCallback onRefineNova;
  final VoidCallback onConverseLuna;
  final VoidCallback onConverseNova;

  const _JournalEntryCard({
    required this.entry,
    required this.isWorking,
    required this.onOpen,
    required this.onEdit,
    required this.onShare,
    required this.onDelete,
    required this.onRefineLuna,
    required this.onRefineNova,
    required this.onConverseLuna,
    required this.onConverseNova,
  });

  @override
  Widget build(BuildContext context) {
    final typeLabel = switch (entry.type) {
      JournalEntryType.dream => 'Dream',
      JournalEntryType.reflection => 'Reflection',
      JournalEntryType.idea => 'Idea',
    };
    final preview = entry.content.length > 220
        ? '${entry.content.substring(0, 220).trimRight()}...'
        : entry.content;

    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(24),
      child: Ink(
        padding: const EdgeInsets.all(18),
        decoration: AppColors.premiumPanelDecoration(
          Theme.of(context).brightness == Brightness.dark,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(
                      AppConstants.radiusFull,
                    ),
                    border: Border.all(
                      color: AppColors.green.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Text(
                    typeLabel,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
                const Spacer(),
                Text(
                  DateFormat('MMM d · h:mm a').format(entry.updatedAt),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(entry.title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              preview,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(height: 1.55),
            ),
            if (entry.novaAnalysis?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 12),
              Text(
                'Nova has already analyzed this entry.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.gold),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_note_rounded),
                  label: const Text('Edit'),
                ),
                OutlinedButton.icon(
                  onPressed: onShare,
                  icon: const Icon(Icons.ios_share_rounded),
                  label: const Text('Share'),
                ),
                FilledButton.tonalIcon(
                  onPressed: isWorking ? null : onRefineNova,
                  icon: isWorking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome_rounded),
                  label: const Text('Refine'),
                ),
                TextButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Delete'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _JournalComposerSheet extends ConsumerStatefulWidget {
  final JournalEntry? initialEntry;
  final JournalEntryType initialType;

  const _JournalComposerSheet({this.initialEntry, required this.initialType});

  @override
  ConsumerState<_JournalComposerSheet> createState() =>
      _JournalComposerSheetState();
}

class _JournalComposerSheetState extends ConsumerState<_JournalComposerSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  late final TextEditingController _tagsController;
  late JournalEntryType _type;
  bool _detailsExpanded = false;

  @override
  void initState() {
    super.initState();
    _type = widget.initialEntry?.type ?? widget.initialType;
    _detailsExpanded =
        widget.initialEntry != null &&
        ((widget.initialEntry?.title.trim().isNotEmpty ?? false) ||
            widget.initialEntry!.tags.isNotEmpty);
    _titleController = TextEditingController(
      text: widget.initialEntry?.title ?? '',
    );
    _contentController = TextEditingController(
      text: widget.initialEntry?.content ?? '',
    );
    _tagsController = TextEditingController(
      text: widget.initialEntry?.tags.join(', ') ?? '',
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _toggleVoiceInput() async {
    final voiceService = ref.read(guideVoiceServiceProvider);
    try {
      if (voiceService.isRecording) {
        final transcript = await voiceService.stopRecordingAndTranscribe();
        final existing = _contentController.text.trim();
        _contentController.text = existing.isEmpty
            ? transcript
            : '$existing\n\n$transcript';
        setState(() {});
      } else {
        await voiceService.startRecording();
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final voiceService = ref.watch(guideVoiceServiceProvider);

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: AppColors.premiumPanelDecoration(isDark),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.initialEntry == null
                    ? 'New journal entry'
                    : 'Edit entry',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              SegmentedButton<JournalEntryType>(
                segments: const [
                  ButtonSegment(
                    value: JournalEntryType.dream,
                    label: Text('Dream'),
                    icon: Icon(Icons.bedtime_rounded),
                  ),
                  ButtonSegment(
                    value: JournalEntryType.reflection,
                    label: Text('Reflection'),
                    icon: Icon(Icons.self_improvement_rounded),
                  ),
                  ButtonSegment(
                    value: JournalEntryType.idea,
                    label: Text('Idea'),
                    icon: Icon(Icons.lightbulb_rounded),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: (selection) {
                  setState(() => _type = selection.first);
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _contentController,
                minLines: 7,
                maxLines: 14,
                decoration: InputDecoration(
                  labelText: switch (_type) {
                    JournalEntryType.dream => 'What do you remember?',
                    JournalEntryType.reflection => 'What are you noticing?',
                    JournalEntryType.idea => 'What idea do you want to keep?',
                  },
                  hintText: switch (_type) {
                    JournalEntryType.dream =>
                      'Start with the dream itself. You can title and tag it later.',
                    JournalEntryType.reflection =>
                      'Write the reflection first. Details can come after.',
                    JournalEntryType.idea =>
                      'Capture the idea now. Organize it in a second step.',
                  },
                  alignLabelWithHint: true,
                  suffixIcon: IconButton(
                    onPressed: voiceService.isTranscribing
                        ? null
                        : _toggleVoiceInput,
                    icon: voiceService.isTranscribing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            voiceService.isRecording
                                ? Icons.stop_circle_outlined
                                : Icons.mic_rounded,
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: () {
                  setState(() => _detailsExpanded = !_detailsExpanded);
                },
                icon: Icon(
                  _detailsExpanded ? Icons.expand_less : Icons.expand_more,
                ),
                label: Text(
                  _detailsExpanded
                      ? 'Hide title and tags'
                      : 'Add title and tags',
                ),
              ),
              if (_detailsExpanded) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    hintText: 'Optional title',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _tagsController,
                  decoration: const InputDecoration(
                    labelText: 'Tags',
                    hintText: 'dream, calm, gratitude',
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () {
                      final content = _contentController.text.trim();
                      if (content.isEmpty) {
                        return;
                      }
                      final tags = _tagsController.text
                          .split(',')
                          .map((part) => part.trim())
                          .where((part) => part.isNotEmpty)
                          .toList();
                      Navigator.of(context).pop(
                        _JournalDraftResult(
                          type: _type,
                          title: _titleController.text,
                          content: content,
                          tags: tags,
                        ),
                      );
                    },
                    child: Text(
                      widget.initialEntry == null
                          ? 'Save privately'
                          : 'Update entry',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JournalDraftResult {
  final JournalEntryType type;
  final String title;
  final String content;
  final List<String> tags;

  const _JournalDraftResult({
    required this.type,
    required this.title,
    required this.content,
    required this.tags,
  });
}
