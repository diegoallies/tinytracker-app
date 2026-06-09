import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../config/design_tokens.dart';
import '../../config/theme.dart';
import '../../models/baby.dart';
import '../../models/care_pack_models.dart';
import '../../providers/baby_provider.dart';
import '../../providers/care_pack_provider.dart';
import '../../utils/care_pack_data.dart';
import '../../utils/extensions.dart';
import '../../utils/haptics.dart';
import '../../widgets/common/animated_card.dart';
import '../../widgets/common/loading_skeleton.dart';

/// Digitises the paper "Weekly Report by Age" the nanny hands to parents
/// every Friday: auto-filled metrics, the stage milestone checklist, the
/// stage focus questions, and the free-text sections — savable as a draft,
/// submittable to the parents, and shareable as a PDF.
class WeeklyReportScreen extends ConsumerStatefulWidget {
  const WeeklyReportScreen({super.key});

  @override
  ConsumerState<WeeklyReportScreen> createState() =>
      _WeeklyReportScreenState();
}

class _WeeklyReportScreenState extends ConsumerState<WeeklyReportScreen> {
  late DateTime _weekStart;

  final Map<String, String> _milestoneChecks = {};
  final Map<String, TextEditingController> _focusCtrls = {};
  final _strugglesCtrl = TextEditingController();
  final _summaryCtrl = TextEditingController();
  final _questionsCtrl = TextEditingController();

  /// Week key of the report whose saved values were loaded into the form.
  String? _hydratedKey;
  bool _saving = false;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _weekStart = weekStartOf(DateTime.now());
  }

  @override
  void dispose() {
    for (final c in _focusCtrls.values) {
      c.dispose();
    }
    _strugglesCtrl.dispose();
    _summaryCtrl.dispose();
    _questionsCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------

  String _weekKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  /// Hydration key for the form: includes the selected baby so switching
  /// babies while the screen is open re-hydrates with the new baby's report.
  String get _hydrationKey =>
      '${ref.read(selectedBabyProvider)?.id}|${_weekKey(_weekStart)}';

  DateTime get _weekEnd => _weekStart.add(const Duration(days: 6));

  bool get _isCurrentWeek =>
      _weekKey(_weekStart) == _weekKey(weekStartOf(DateTime.now()));

  TextEditingController _focusCtrl(String key) =>
      _focusCtrls.putIfAbsent(key, TextEditingController.new);

  String _weekRangeLabel() {
    final fmt = DateFormat('MMM d');
    final endFmt = _weekStart.month == _weekEnd.month
        ? DateFormat('d')
        : DateFormat('MMM d');
    return '${fmt.format(_weekStart)} – ${endFmt.format(_weekEnd)}';
  }

  String _ageLabel(Baby baby) {
    final months = ageInMonths(baby.dateOfBirth, _weekEnd);
    if (months < 1) {
      final weeks =
          (_weekEnd.difference(baby.dateOfBirth).inDays / 7).floor();
      return '$weeks week${weeks == 1 ? '' : 's'} old';
    }
    return '$months month${months == 1 ? '' : 's'} old';
  }

  /// Stage shown for the week being viewed. Saved reports keep the stage
  /// they were written against; the current week follows the baby's age.
  CarePackStage? _resolveStage(Baby? baby, WeeklyCareReport? report) {
    if (report != null) {
      final saved = CarePackData.stageById(report.ageStage);
      if (saved != null) return saved;
    }
    if (_isCurrentWeek) return ref.watch(currentStageProvider);
    if (baby == null) return null;
    return CarePackData.stageForAgeMonths(
        ageInMonths(baby.dateOfBirth, _weekEnd));
  }

  void _goToWeek(DateTime anchor) {
    Haptics.lightTap();
    setState(() {
      _weekStart = weekStartOf(anchor);
      _hydratedKey = null;
      _clearForm();
    });
  }

  void _clearForm() {
    _milestoneChecks.clear();
    for (final c in _focusCtrls.values) {
      c.clear();
    }
    _strugglesCtrl.clear();
    _summaryCtrl.clear();
    _questionsCtrl.clear();
  }

  void _hydrate(WeeklyCareReport? report) {
    setState(() {
      _hydratedKey = _hydrationKey;
      _clearForm();
      if (report == null) return;
      _milestoneChecks.addAll(report.milestoneChecks);
      report.focusAnswers.forEach((k, v) => _focusCtrl(k).text = v);
      _strugglesCtrl.text = report.struggles ?? '';
      _summaryCtrl.text = report.summary ?? '';
      _questionsCtrl.text = report.questions ?? '';
    });
  }

  Map<String, String> _collectFocusAnswers(CarePackStage stage) {
    final answers = <String, String>{};
    for (final q in stage.focusQuestions) {
      final text = _focusCtrls[q.key]?.text.trim() ?? '';
      if (text.isNotEmpty) answers[q.key] = text;
    }
    return answers;
  }

  // ---------------------------------------------------------------------
  // Save / submit
  // ---------------------------------------------------------------------

  Future<void> _save({required bool submit}) async {
    final baby = ref.read(selectedBabyProvider);
    final report = ref.read(weeklyReportProvider(_weekStart)).valueOrNull;
    final stage = _resolveStage(baby, report);
    if (baby == null || stage == null || _saving) return;

    Haptics.mediumTap();
    setState(() => _saving = true);
    try {
      Map<String, dynamic>? metrics;
      if (submit) {
        metrics = await ref.read(weeklyMetricsProvider(_weekStart).future);
      }
      await WeeklyReportActions.save(
        babyId: baby.id,
        weekStart: _weekStart,
        ageStage: stage.id,
        summary: _summaryCtrl.text,
        struggles: _strugglesCtrl.text,
        questions: _questionsCtrl.text,
        milestoneChecks: Map.of(_milestoneChecks),
        focusAnswers: _collectFocusAnswers(stage),
        metrics: metrics,
        submit: submit,
      );
      ref.invalidate(weeklyReportProvider(_weekStart));
      ref.invalidate(pastWeeklyReportsProvider);
      if (!mounted) return;
      if (submit) {
        context.showSuccessSnackBar('Report submitted to the parents');
      } else {
        context.showSuccessSnackBar('Draft saved');
      }
    } on SchemaNotReadyException {
      if (mounted) {
        context.showErrorSnackBar(
            'The one-time database upgrade hasn’t been applied yet.');
      }
    } catch (_) {
      if (mounted) {
        context.showErrorSnackBar('Couldn’t save the report. Try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------------------------------------------------------------------
  // Sharing
  // ---------------------------------------------------------------------

  static const List<(String key, String label)> _metricRows = [
    ('feeds_per_day', 'Feeds / day'),
    ('avg_ml_per_feed', 'Avg per feed'),
    ('nap_minutes_per_day', 'Naps / day'),
    ('longest_sleep_minutes', 'Longest sleep'),
    ('wet_diapers', 'Wet nappies'),
    ('dirty_diapers', 'Dirty nappies'),
    ('tummy_time_minutes', 'Tummy time total'),
    ('spitups_per_day', 'Spit-ups / day'),
    ('painful_reflux_episodes', 'Painful reflux'),
  ];

  String _metricValue(Map<String, dynamic> metrics, String key) {
    final raw = metrics[key];
    if (raw == null) return '—';
    switch (key) {
      case 'avg_ml_per_feed':
        return '$raw ml';
      case 'nap_minutes_per_day':
      case 'longest_sleep_minutes':
      case 'tummy_time_minutes':
        return _formatMinutes((raw as num).toInt());
      default:
        return '$raw';
    }
  }

  String _formatMinutes(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  Map<String, List<String>> _groupedChecklist(CarePackStage stage) {
    final groups = <String, List<String>>{
      'First time this week': [],
      'Getting better': [],
      'Not yet': [],
    };
    for (final item in stage.weeklyMilestones) {
      switch (_milestoneChecks[item.key]) {
        case CarePackData.checkFirstTime:
          groups['First time this week']!.add(item.label);
        case CarePackData.checkBetter:
          groups['Getting better']!.add(item.label);
        case CarePackData.checkNotYet:
          groups['Not yet']!.add(item.label);
      }
    }
    groups.removeWhere((_, v) => v.isEmpty);
    return groups;
  }

  Future<void> _sharePdf(Baby baby, CarePackStage stage) async {
    if (_sharing) return;
    Haptics.lightTap();
    setState(() => _sharing = true);
    try {
      final metrics = await ref.read(weeklyMetricsProvider(_weekStart).future);
      final pdf = _buildPdf(baby, stage, metrics);
      final bytes = await pdf.save();
      await Printing.sharePdf(
        bytes: bytes,
        filename:
            'weekly_report_${baby.name.toLowerCase().replaceAll(' ', '_')}'
            '_${DateFormat('yyyy_MM_dd').format(_weekStart)}.pdf',
      );
    } catch (_) {
      if (mounted) {
        context.showErrorSnackBar('Couldn’t generate the PDF. Try again.');
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  pw.Document _buildPdf(
      Baby baby, CarePackStage stage, Map<String, dynamic> metrics) {
    final pdf = pw.Document();
    final primary = PdfColor.fromHex('#9b72cf');
    final textColor = PdfColor.fromHex('#2d2640');
    final muted = PdfColor.fromHex('#8b85a0');
    final sectionStyle = pw.TextStyle(
        fontSize: 13, fontWeight: pw.FontWeight.bold, color: textColor);
    final bodyStyle = pw.TextStyle(fontSize: 10, color: textColor);

    pw.Widget section(String title, List<pw.Widget> children) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(height: 14),
            pw.Text(title, style: sectionStyle),
            pw.SizedBox(height: 6),
            ...children,
          ],
        );

    pw.Widget textBlock(String label, String? value) {
      final text = (value ?? '').trim();
      return section(label, [
        pw.Text(text.isEmpty ? '—' : text, style: bodyStyle),
      ]);
    }

    final groups = _groupedChecklist(stage);
    final focusAnswers = _collectFocusAnswers(stage);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: pw.TextStyle(fontSize: 9, color: muted),
          ),
        ),
        build: (context) => [
          pw.Text('Weekly Report — ${baby.name}',
              style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                  color: primary)),
          pw.SizedBox(height: 4),
          pw.Text(
            'Week of ${_weekRangeLabel()}, ${_weekStart.year} · '
            '${stage.label} (${stage.subtitle})',
            style: pw.TextStyle(fontSize: 10, color: muted),
          ),
          pw.Divider(color: primary, thickness: 1),
          section('This week by the numbers', [
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              children: [
                for (final (key, label) in _metricRows)
                  pw.TableRow(children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text(label, style: bodyStyle),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text(_metricValue(metrics, key),
                          style: bodyStyle),
                    ),
                  ]),
              ],
            ),
          ]),
          if (groups.isNotEmpty)
            section('Milestones', [
              for (final entry in groups.entries) ...[
                pw.Text(entry.key,
                    style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: primary)),
                pw.SizedBox(height: 3),
                for (final label in entry.value)
                  pw.Bullet(text: label, style: bodyStyle),
                pw.SizedBox(height: 6),
              ],
            ]),
          textBlock('What he struggled with this week', _strugglesCtrl.text),
          if (focusAnswers.isNotEmpty)
            section(stage.focusTitle, [
              for (final q in stage.focusQuestions)
                if (focusAnswers.containsKey(q.key))
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 5),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(q.label,
                            style: pw.TextStyle(fontSize: 9, color: muted)),
                        pw.Text(focusAnswers[q.key]!, style: bodyStyle),
                      ],
                    ),
                  ),
            ]),
          textBlock('Overall summary', _summaryCtrl.text),
          textBlock('Questions / things I need from you', _questionsCtrl.text),
        ],
      ),
    );
    return pdf;
  }

  Future<void> _shareAsText(Baby baby, CarePackStage stage) async {
    Haptics.lightTap();
    final metrics =
        ref.read(weeklyMetricsProvider(_weekStart)).valueOrNull ?? {};
    final buffer = StringBuffer()
      ..writeln('Weekly Report — ${baby.name}')
      ..writeln('Week of ${_weekRangeLabel()}, ${_weekStart.year}')
      ..writeln('Stage: ${stage.label} — ${stage.subtitle}')
      ..writeln()
      ..writeln('BY THE NUMBERS');
    for (final (key, label) in _metricRows) {
      buffer.writeln('• $label: ${_metricValue(metrics, key)}');
    }
    final groups = _groupedChecklist(stage);
    if (groups.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('MILESTONES');
      for (final entry in groups.entries) {
        buffer.writeln('${entry.key}:');
        for (final label in entry.value) {
          buffer.writeln('  • $label');
        }
      }
    }
    void textSection(String title, String value) {
      if (value.trim().isEmpty) return;
      buffer
        ..writeln()
        ..writeln(title.toUpperCase())
        ..writeln(value.trim());
    }

    textSection('What he struggled with this week', _strugglesCtrl.text);
    final focusAnswers = _collectFocusAnswers(stage);
    if (focusAnswers.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(stage.focusTitle.toUpperCase());
      for (final q in stage.focusQuestions) {
        final answer = focusAnswers[q.key];
        if (answer != null) buffer.writeln('• ${q.label}: $answer');
      }
    }
    textSection('Overall summary', _summaryCtrl.text);
    textSection('Questions / things I need from you', _questionsCtrl.text);

    await Share.share(buffer.toString(),
        subject: 'Weekly Report — ${baby.name}');
  }

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final baby = ref.watch(selectedBabyProvider);
    final reportAsync = ref.watch(weeklyReportProvider(_weekStart));
    final report = reportAsync.valueOrNull;
    final stage = _resolveStage(baby, report);

    // Prefill the form once the saved report (or its absence) is known.
    if (reportAsync.hasValue && _hydratedKey != _hydrationKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _hydratedKey != _hydrationKey) {
          _hydrate(ref.read(weeklyReportProvider(_weekStart)).valueOrNull);
        }
      });
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Weekly Report')),
      body: SafeArea(
        child: baby == null
            ? const Center(child: Text('No baby selected'))
            : ListView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.gutter,
                    AppSpacing.md, AppSpacing.gutter, AppSpacing.xxl),
                children: [
                  _buildHeaderCard(baby, stage, report),
                  const SizedBox(height: AppSpacing.md),
                  ..._buildBody(baby, stage, reportAsync),
                ],
              ),
      ),
    );
  }

  List<Widget> _buildBody(Baby baby, CarePackStage? stage,
      AsyncValue<WeeklyCareReport?> reportAsync) {
    if (reportAsync.hasError &&
        reportAsync.error is SchemaNotReadyException) {
      return [const _SchemaPendingCard(), _buildHistory()];
    }
    if (reportAsync.hasError) {
      return [
        _ErrorCard(
          onRetry: () => ref.invalidate(weeklyReportProvider(_weekStart)),
        ),
      ];
    }
    if (reportAsync.isLoading && !reportAsync.hasValue) {
      return const [CardSkeleton(), SizedBox(height: 16), CardSkeleton()];
    }
    if (stage == null) return const [];

    final report = reportAsync.valueOrNull;
    return [
      _buildMetricsCard(),
      const SizedBox(height: AppSpacing.md),
      _buildMilestonesCard(stage),
      const SizedBox(height: AppSpacing.md),
      _buildStrugglesCard(),
      const SizedBox(height: AppSpacing.md),
      _buildFocusCard(stage),
      const SizedBox(height: AppSpacing.md),
      _buildTextCard(
        index: 4,
        icon: Icons.notes_rounded,
        title: 'Overall summary',
        hint: 'How was the week overall? Mood, routine, anything notable.',
        controller: _summaryCtrl,
      ),
      const SizedBox(height: AppSpacing.md),
      _buildTextCard(
        index: 5,
        icon: Icons.help_outline_rounded,
        title: 'Questions / things I need from you',
        hint: 'Supplies running low, decisions needed, anything to discuss.',
        controller: _questionsCtrl,
      ),
      const SizedBox(height: AppSpacing.xl),
      _buildActions(baby, stage, report),
      _buildHistory(),
    ];
  }

  Widget _buildHeaderCard(
      Baby baby, CarePackStage? stage, WeeklyCareReport? report) {
    final palette = context.palette;
    return AnimatedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ChevronButton(
                icon: Icons.chevron_left_rounded,
                onTap: () =>
                    _goToWeek(_weekStart.subtract(const Duration(days: 7))),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      _isCurrentWeek ? 'This week' : _weekRangeLabel(),
                      style: context.textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _isCurrentWeek
                          ? _weekRangeLabel()
                          : 'Mon – Sun, ${_weekStart.year}',
                      style: context.textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              _ChevronButton(
                icon: Icons.chevron_right_rounded,
                onTap: _isCurrentWeek
                    ? null
                    : () =>
                        _goToWeek(_weekStart.add(const Duration(days: 7))),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(Icons.child_care_rounded,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  '${baby.name} · ${_ageLabel(baby)}',
                  style: context.textTheme.bodyMedium,
                ),
              ),
              if (report != null && report.isSubmitted)
                _SubmittedBadge(date: report.submittedAt!),
            ],
          ),
          if (stage != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: AppRadius.mdAll,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stage.label,
                    style: context.textTheme.labelLarge
                        ?.copyWith(color: AppColors.primary),
                  ),
                  const SizedBox(height: 2),
                  Text(stage.subtitle,
                      style: context.textTheme.bodySmall
                          ?.copyWith(color: palette.muted)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricsCard() {
    final metricsAsync = ref.watch(weeklyMetricsProvider(_weekStart));
    return AnimatedCard(
      index: 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(
              icon: Icons.insights_rounded, title: 'This week by the numbers'),
          const SizedBox(height: AppSpacing.sm),
          metricsAsync.when(
            loading: () => const LoadingSkeleton(height: 120),
            error: (_, _) => Text(
              'Couldn’t calculate this week’s numbers.',
              style: context.textTheme.bodySmall,
            ),
            data: (metrics) => GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: AppSpacing.xs,
                crossAxisSpacing: AppSpacing.xs,
                mainAxisExtent: 58,
              ),
              itemCount: _metricRows.length,
              itemBuilder: (context, i) {
                final (key, label) = _metricRows[i];
                return _MetricTile(
                    label: label, value: _metricValue(metrics, key));
              },
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Calculated automatically from the logs — no manual tallying.',
            style: context.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildMilestonesCard(CarePackStage stage) {
    return AnimatedCard(
      index: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(
              icon: Icons.emoji_events_rounded, title: 'Milestones this week'),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Mark what happened this week. Leave a row blank if it didn’t '
            'come up.',
            style: context.textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final (i, item) in stage.weeklyMilestones.indexed) ...[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.label, style: context.textTheme.bodyMedium),
                const SizedBox(height: AppSpacing.xs),
                _TriSegmentControl(
                  options: const [
                    _TriSegmentOption(CarePackData.checkFirstTime,
                        'First time', AppColors.success),
                    _TriSegmentOption(
                        CarePackData.checkBetter, 'Better', AppColors.info),
                    _TriSegmentOption(
                        CarePackData.checkNotYet, 'Not yet', AppColors.warning),
                  ],
                  selected: _milestoneChecks[item.key],
                  onChanged: (value) {
                    setState(() {
                      if (value == null) {
                        _milestoneChecks.remove(item.key);
                      } else {
                        _milestoneChecks[item.key] = value;
                      }
                    });
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStrugglesCard() {
    return AnimatedCard(
      index: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(
            icon: Icons.priority_high_rounded,
            iconColor: AppColors.warning,
            title: 'What he struggled with this week',
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'The most important section — anything marked "Not yet", '
            'anything hard, frustrating, or upsetting.',
            style: context.textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _strugglesCtrl,
            maxLines: 4,
            minLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'e.g. fought every nap after 3pm, hated tummy time…',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFocusCard(CarePackStage stage) {
    return AnimatedCard(
      index: 4,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(icon: Icons.center_focus_strong_rounded,
              title: stage.focusTitle),
          const SizedBox(height: AppSpacing.xxs),
          Text(stage.focusIntro, style: context.textTheme.bodySmall),
          const SizedBox(height: AppSpacing.sm),
          for (final (i, q) in stage.focusQuestions.indexed) ...[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(q.label, style: context.textTheme.bodyMedium),
                const SizedBox(height: AppSpacing.xs),
                TextField(
                  controller: _focusCtrl(q.key),
                  maxLines: 2,
                  minLines: 1,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(hintText: 'Your answer…'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTextCard({
    required int index,
    required IconData icon,
    required String title,
    required String hint,
    required TextEditingController controller,
  }) {
    return AnimatedCard(
      index: index,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardTitle(icon: icon, title: title),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: controller,
            maxLines: 4,
            minLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(hintText: hint),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(
      Baby baby, CarePackStage stage, WeeklyCareReport? report) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: _saving ? null : () => _save(submit: false),
          icon: const Icon(Icons.save_outlined, size: 20),
          label: const Text('Save draft'),
        ),
        const SizedBox(height: AppSpacing.sm),
        ElevatedButton.icon(
          onPressed: _saving ? null : () => _save(submit: true),
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Icon(Icons.send_rounded, size: 20),
          label: Text(report != null && report.isSubmitted
              ? 'Re-submit to parents'
              : 'Submit to parents'),
        ),
        if (report != null && report.isSubmitted) ...[
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _sharing ? null : () => _sharePdf(baby, stage),
                  icon: const Icon(Icons.picture_as_pdf_rounded, size: 20),
                  label: Text(_sharing ? 'Preparing…' : 'Share PDF'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _shareAsText(baby, stage),
                  icon: const Icon(Icons.share_rounded, size: 20),
                  label: const Text('Share as text'),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildHistory() {
    final pastAsync = ref.watch(pastWeeklyReportsProvider);
    final reports = pastAsync.valueOrNull ?? const <WeeklyCareReport>[];
    if (reports.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.xl),
        Text('Past reports', style: context.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 84,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: reports.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
            itemBuilder: (context, i) {
              final r = reports[i];
              final isSelected = _weekKey(r.weekStart) == _weekKey(_weekStart);
              return _PastReportChip(
                report: r,
                selected: isSelected,
                onTap: () => _goToWeek(r.weekStart),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Private widgets
// ---------------------------------------------------------------------------

class _CardTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color iconColor;

  const _CardTitle({
    required this.icon,
    required this.title,
    this.iconColor = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: iconColor),
        const SizedBox(width: AppSpacing.xs),
        Expanded(child: Text(title, style: context.textTheme.titleMedium)),
      ],
    );
  }
}

class _ChevronButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _ChevronButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 28),
      color: onTap == null
          ? context.palette.muted.withValues(alpha: 0.4)
          : AppColors.primary,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
    );
  }
}

class _SubmittedBadge extends StatelessWidget {
  final DateTime date;

  const _SubmittedBadge({required this.date});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.12),
        borderRadius: AppRadius.smAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_rounded,
              size: 14, color: AppColors.success),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            'Submitted ${DateFormat('MMM d').format(date)}',
            style: context.textTheme.bodySmall?.copyWith(
              color: AppColors.success,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;

  const _MetricTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: AppRadius.mdAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: context.textTheme.titleMedium
                ?.copyWith(color: AppColors.primary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: context.textTheme.bodySmall?.copyWith(color: palette.muted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _TriSegmentOption {
  final String value;
  final String label;
  final Color color;

  const _TriSegmentOption(this.value, this.label, this.color);
}

/// Three-state segmented control. Tapping the selected segment again clears
/// it back to "untouched".
class _TriSegmentControl extends StatelessWidget {
  final List<_TriSegmentOption> options;
  final String? selected;
  final ValueChanged<String?> onChanged;

  const _TriSegmentControl({
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        for (final (i, option) in options.indexed) ...[
          if (i > 0) const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: GestureDetector(
              onTap: () {
                Haptics.selectionClick();
                onChanged(selected == option.value ? null : option.value);
              },
              child: AnimatedContainer(
                duration: AppMotion.fast,
                curve: AppMotion.ease,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected == option.value
                      ? option.color
                      : option.color.withValues(alpha: 0.08),
                  borderRadius: AppRadius.mdAll,
                  border: Border.all(
                    color: selected == option.value
                        ? option.color
                        : palette.border,
                  ),
                ),
                child: Text(
                  option.label,
                  style: context.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: selected == option.value
                        ? Colors.white
                        : palette.text,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _PastReportChip extends StatelessWidget {
  final WeeklyCareReport report;
  final bool selected;
  final VoidCallback onTap;

  const _PastReportChip({
    required this.report,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final stage = CarePackData.stageById(report.ageStage);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 150,
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.1)
              : palette.card,
          borderRadius: AppRadius.lgAll,
          border: Border.all(
            color: selected ? AppColors.primary : palette.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Week of ${DateFormat('MMM d').format(report.weekStart)}',
              style: context.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              stage?.label ?? report.ageStage,
              style: context.textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.xxs),
            Row(
              children: [
                Icon(
                  report.isSubmitted
                      ? Icons.check_circle_rounded
                      : Icons.edit_note_rounded,
                  size: 14,
                  color: report.isSubmitted
                      ? AppColors.success
                      : palette.muted,
                ),
                const SizedBox(width: AppSpacing.xxs),
                Text(
                  report.isSubmitted ? 'Submitted' : 'Draft',
                  style: context.textTheme.bodySmall?.copyWith(
                    color: report.isSubmitted
                        ? AppColors.success
                        : palette.muted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SchemaPendingCard extends StatelessWidget {
  const _SchemaPendingCard();

  @override
  Widget build(BuildContext context) {
    return AnimatedCard(
      index: 1,
      child: Column(
        children: [
          const Icon(Icons.cloud_sync_rounded,
              size: 40, color: AppColors.info),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'One-time database upgrade pending',
            style: context.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Weekly reports need a small database upgrade that hasn’t been '
            'applied yet. Everything else keeps working in the meantime.',
            style: context.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorCard({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return AnimatedCard(
      index: 1,
      child: Column(
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 40, color: AppColors.error),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Couldn’t load this week’s report',
            style: context.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Check your connection and try again.',
            style: context.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.md),
          TextButton.icon(
            onPressed: () {
              Haptics.lightTap();
              onRetry();
            },
            icon: const Icon(Icons.refresh_rounded, size: 20),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
