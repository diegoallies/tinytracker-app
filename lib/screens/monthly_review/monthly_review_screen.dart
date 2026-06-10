import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

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

/// Digitises the "Monthly Milestone Tracker" done on the 4th of each month
/// (the baby's birth date): the stage checklist answered Yes / Sometimes /
/// Not yet, plus the nanny's comments.
class MonthlyReviewScreen extends ConsumerStatefulWidget {
  const MonthlyReviewScreen({super.key});

  @override
  ConsumerState<MonthlyReviewScreen> createState() =>
      _MonthlyReviewScreenState();
}

class _MonthlyReviewScreenState extends ConsumerState<MonthlyReviewScreen> {
  late DateTime _month;
  final ScrollController _scroll = ScrollController();

  final Map<String, String> _checklist = {};
  final _commentsCtrl = TextEditingController();

  String? _hydratedKey;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month, 1);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _commentsCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------

  String _monthKey(DateTime d) => '${d.year}-${d.month}';

  /// Hydration key for the form: includes the selected baby so switching
  /// babies while the screen is open re-hydrates with the new baby's review.
  String get _hydrationKey =>
      '${ref.read(selectedBabyProvider)?.id}|${_monthKey(_month)}';

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  /// The review is done on the baby's "month birthday" (the 4th in the
  /// original paper pack) - age is measured at that day of the month.
  DateTime _reviewDate(Baby baby) {
    final day = baby.dateOfBirth.day.clamp(1, 28);
    return DateTime(_month.year, _month.month, day);
  }

  CarePackStage? _resolveStage(Baby? baby, MonthlyReview? review) {
    if (review != null) {
      final saved = CarePackData.stageById(review.ageStage);
      if (saved != null) return saved;
    }
    if (baby == null) return null;
    return CarePackData.stageForAgeMonths(
        ageInMonths(baby.dateOfBirth, _reviewDate(baby)));
  }

  void _goToMonth(DateTime month) {
    Haptics.lightTap();
    setState(() {
      _month = DateTime(month.year, month.month, 1);
      _hydratedKey = null;
      _checklist.clear();
      _commentsCtrl.clear();
    });
    // The review renders at the top - make the switch visible.
    if (_scroll.hasClients) {
      _scroll.animateTo(0, duration: AppMotion.normal, curve: AppMotion.ease);
    }
  }

  void _hydrate(MonthlyReview? review) {
    setState(() {
      _hydratedKey = _hydrationKey;
      _checklist.clear();
      _commentsCtrl.clear();
      if (review == null) return;
      _checklist.addAll(review.checklist);
      _commentsCtrl.text = review.comments ?? '';
    });
  }

  (int yes, int total) _progress(CarePackStage stage) {
    var yes = 0;
    var total = 0;
    for (final section in stage.monthlyChecklist) {
      for (final item in section.items) {
        total++;
        if (_checklist[item.key] == CarePackData.monthlyYes) yes++;
      }
    }
    return (yes, total);
  }

  Future<void> _save() async {
    final baby = ref.read(selectedBabyProvider);
    final review = ref.read(monthlyReviewProvider(_month)).valueOrNull;
    final stage = _resolveStage(baby, review);
    if (baby == null || stage == null || _saving) return;

    Haptics.mediumTap();
    setState(() => _saving = true);
    try {
      await MonthlyReviewActions.save(
        babyId: baby.id,
        month: _month,
        ageStage: stage.id,
        checklist: Map.of(_checklist),
        comments: _commentsCtrl.text,
      );
      ref.invalidate(monthlyReviewProvider(_month));
      ref.invalidate(pastMonthlyReviewsProvider);
      if (mounted) context.showSuccessSnackBar('Monthly review saved');
    } on SchemaNotReadyException {
      if (mounted) {
        context.showErrorSnackBar(
            'The one-time database upgrade hasn’t been applied yet.');
      }
    } catch (_) {
      if (mounted) {
        context.showErrorSnackBar('Couldn’t save the review. Try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final baby = ref.watch(selectedBabyProvider);
    final reviewAsync = ref.watch(monthlyReviewProvider(_month));
    final stage = _resolveStage(baby, reviewAsync.valueOrNull);

    if (reviewAsync.hasValue && _hydratedKey != _hydrationKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _hydratedKey != _hydrationKey) {
          _hydrate(ref.read(monthlyReviewProvider(_month)).valueOrNull);
        }
      });
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Monthly Review')),
      body: SafeArea(
        child: baby == null
            ? const Center(child: Text('No baby selected'))
            : ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(AppSpacing.gutter,
                    AppSpacing.md, AppSpacing.gutter, AppSpacing.xxl),
                children: [
                  _buildHeaderCard(baby, stage),
                  const SizedBox(height: AppSpacing.md),
                  ..._buildBody(stage, reviewAsync),
                ],
              ),
      ),
    );
  }

  List<Widget> _buildBody(
      CarePackStage? stage, AsyncValue<MonthlyReview?> reviewAsync) {
    if (reviewAsync.hasError &&
        reviewAsync.error is SchemaNotReadyException) {
      return const [_SchemaPendingCard()];
    }
    if (reviewAsync.hasError) {
      return [
        _ErrorCard(
          onRetry: () => ref.invalidate(monthlyReviewProvider(_month)),
        ),
      ];
    }
    if (reviewAsync.isLoading && !reviewAsync.hasValue) {
      return const [CardSkeleton(), SizedBox(height: 16), CardSkeleton()];
    }
    if (stage == null) return const [];

    return [
      _buildProgressCard(stage),
      const SizedBox(height: AppSpacing.md),
      for (final (i, section) in stage.monthlyChecklist.indexed) ...[
        _buildSectionCard(section, index: 2 + i),
        const SizedBox(height: AppSpacing.md),
      ],
      _buildCommentsCard(stage.monthlyChecklist.length + 2),
      const SizedBox(height: AppSpacing.xl),
      ElevatedButton.icon(
        onPressed: _saving ? null : _save,
        icon: _saving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Icon(Icons.save_rounded, size: 20),
        label: const Text('Save review'),
      ),
      _buildHistory(),
    ];
  }

  Widget _buildHeaderCard(Baby baby, CarePackStage? stage) {
    final palette = context.palette;
    final months = ageInMonths(baby.dateOfBirth, _reviewDate(baby));
    return AnimatedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () =>
                    _goToMonth(DateTime(_month.year, _month.month - 1, 1)),
                icon: const Icon(Icons.chevron_left_rounded, size: 28),
                color: AppColors.primary,
                constraints:
                    const BoxConstraints(minWidth: 44, minHeight: 44),
              ),
              Expanded(
                child: Text(
                  DateFormat('MMMM yyyy').format(_month),
                  style: context.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
              ),
              IconButton(
                onPressed: _isCurrentMonth
                    ? null
                    : () =>
                        _goToMonth(DateTime(_month.year, _month.month + 1, 1)),
                icon: const Icon(Icons.chevron_right_rounded, size: 28),
                color: _isCurrentMonth
                    ? palette.muted.withValues(alpha: 0.4)
                    : AppColors.primary,
                constraints:
                    const BoxConstraints(minWidth: 44, minHeight: 44),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              const Icon(Icons.child_care_rounded,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  '${baby.name} · $months month${months == 1 ? '' : 's'} old '
                  'this month',
                  style: context.textTheme.bodyMedium,
                ),
              ),
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

  Widget _buildProgressCard(CarePackStage stage) {
    final (yes, total) = _progress(stage);
    return AnimatedCard(
      index: 1,
      child: Row(
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: total == 0 ? 0 : yes / total,
                  strokeWidth: 6,
                  strokeCap: StrokeCap.round,
                ),
                Center(
                  child: Text(
                    '$yes/$total',
                    style: context.textTheme.labelLarge
                        ?.copyWith(color: AppColors.primary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$yes of $total answered "Yes"',
                    style: context.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  'Every baby moves at his own pace - "Sometimes" and '
                  '"Not yet" are useful answers too.',
                  style: context.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard(CareChecklistSection section,
      {required int index}) {
    return AnimatedCard(
      index: index,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_sectionIcon(section.title),
                  size: 20, color: AppColors.primary),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(section.title,
                    style: context.textTheme.titleMedium),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final (i, item) in section.items.indexed) ...[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.label, style: context.textTheme.bodyMedium),
                const SizedBox(height: AppSpacing.xs),
                _TriSegmentControl(
                  options: const [
                    _TriSegmentOption(
                        CarePackData.monthlyYes, 'Yes', AppColors.success),
                    _TriSegmentOption(CarePackData.monthlySometimes,
                        'Sometimes', AppColors.warning),
                    _TriSegmentOption(
                        CarePackData.monthlyNotYet, 'Not yet', AppColors.info),
                  ],
                  selected: _checklist[item.key],
                  onChanged: (value) {
                    setState(() {
                      if (value == null) {
                        _checklist.remove(item.key);
                      } else {
                        _checklist[item.key] = value;
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

  IconData _sectionIcon(String title) {
    final lower = title.toLowerCase();
    if (lower.contains('physical')) return Icons.directions_run_rounded;
    if (lower.contains('communication')) return Icons.hearing_rounded;
    return Icons.favorite_rounded;
  }

  Widget _buildCommentsCard(int index) {
    return AnimatedCard(
      index: index,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.rate_review_rounded,
                  size: 20, color: AppColors.primary),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text("Nanny's comments",
                    style: context.textTheme.titleMedium),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text('Strengths and what to work on next month.',
              style: context.textTheme.bodySmall),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _commentsCtrl,
            maxLines: 5,
            minLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText:
                  'e.g. very strong on his tummy; let’s work on reaching…',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistory() {
    final pastAsync = ref.watch(pastMonthlyReviewsProvider);
    final reviews = pastAsync.valueOrNull ?? const <MonthlyReview>[];
    if (reviews.isEmpty) return const SizedBox.shrink();

    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.xl),
        Text('Past reviews', style: context.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        for (final review in reviews)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Material(
              color: palette.card,
              borderRadius: AppRadius.lgAll,
              child: InkWell(
                borderRadius: AppRadius.lgAll,
                onTap: () => _goToMonth(review.reviewMonth),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 56),
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month_rounded,
                          size: 20, color: AppColors.primary),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              DateFormat('MMMM yyyy')
                                  .format(review.reviewMonth),
                              style: context.textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              CarePackData.stageById(review.ageStage)?.label ??
                                  review.ageStage,
                              style: context.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: palette.muted),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Private widgets
// ---------------------------------------------------------------------------

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
            'Monthly reviews need a small database upgrade that hasn’t been '
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
            'Couldn’t load this month’s review',
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
