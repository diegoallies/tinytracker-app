import '../../widgets/expandable_history_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../config/theme.dart';
import '../../providers/baby_provider.dart';
import '../../providers/diaper_provider.dart';
import '../../utils/care_pack_data.dart';
import '../../utils/date_utils.dart';
import '../../utils/extensions.dart';
import '../../utils/haptics.dart';
import '../../widgets/common/animated_card.dart';
import '../../widgets/common/app_dialogs.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/swipe_to_dismiss.dart';

class DiaperScreen extends ConsumerStatefulWidget {
  const DiaperScreen({super.key});

  @override
  ConsumerState<DiaperScreen> createState() => _DiaperScreenState();
}

class _DiaperScreenState extends ConsumerState<DiaperScreen> {
  String _selectedType = 'wet';
  String? _selectedColor;
  int? _stoolType; // Bristol-style 1-7, only for dirty/both
  final TextEditingController _notesController = TextEditingController();
  bool _isSaving = false;
  DateTime _loggedAt = DateTime.now();

  static const _diaperTypes = [
    ('wet', 'Wet', Icons.water_drop_outlined),
    ('dirty', 'Dirty', Icons.circle),
    ('both', 'Both', Icons.layers_outlined),
  ];

  static const _poopColors = [
    ('yellow', 'Yellow', Color(0xFFDAA520)),
    ('green', 'Green', Color(0xFF228B22)),
    ('brown', 'Brown', Color(0xFF8B4513)),
    ('black', 'Black', Color(0xFF1A1A1A)),
    ('red', 'Red', Color(0xFFDC143C)),
    ('white', 'White', Color(0xFFF5F5DC)),
  ];

  bool get _showColorPicker =>
      _selectedType == 'dirty' || _selectedType == 'both';

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final baby = ref.read(selectedBabyProvider);
    if (baby == null) return;

    setState(() => _isSaving = true);

    try {
      await DiaperActions.logDiaper(
        babyId: baby.id,
        type: _selectedType,
        color: _showColorPicker ? _selectedColor : null,
        stoolType: _showColorPicker ? _stoolType : null,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        loggedAt: _loggedAt,
      );

      if (!mounted) return;
      ref.invalidate(recentDiapersProvider);
      ref.invalidate(todayDiaperStatsProvider);
      ref.invalidate(lastDiaperAtProvider);

      setState(() {
        _selectedColor = null;
        _stoolType = null;
        _notesController.clear();
        _loggedAt = DateTime.now();
      });

      Haptics.mediumTap();

      if (mounted) {
        context.showSuccessSnackBar('Diaper logged successfully');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Couldn’t save the diaper entry. Check your connection and try again.', onRetry: _save);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<bool?> _confirmDelete() {
    return showDeleteDialog(context, what: 'diaper entry');
  }

  Future<void> _deleteDiaper(String diaperId) async {
    try {
      await DiaperActions.deleteDiaper(diaperId);
      ref.invalidate(recentDiapersProvider);
      ref.invalidate(todayDiaperStatsProvider);
      ref.invalidate(lastDiaperAtProvider);
      if (mounted) {
        context.showSuccessSnackBar('Diaper entry deleted');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar('Couldn’t delete the diaper entry.');
      }
    }
  }

  Future<void> _onRefresh() async {
    Haptics.lightTap();
    ref.invalidate(recentDiapersProvider);
    ref.invalidate(todayDiaperStatsProvider);
    ref.invalidate(lastDiaperAtProvider);
    await ref.read(recentDiapersProvider.future);
  }

  Future<void> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _loggedAt,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(
            primary: AppColors.primary,
            onPrimary: Colors.white,
            surface: ctx.palette.card,
            onSurface: ctx.palette.text,
          ),
        ),
        child: child!,
      ),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_loggedAt),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(
            primary: AppColors.primary,
            onPrimary: Colors.white,
            surface: ctx.palette.card,
            onSurface: ctx.palette.text,
          ),
        ),
        child: child!,
      ),
    );
    if (time == null) return;

    final picked =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (picked.isAfter(DateTime.now())) {
      Haptics.lightTap();
      if (mounted) {
        context.showErrorSnackBar('Can’t log a time in the future.');
      }
      return;
    }
    Haptics.selectionClick();
    setState(() => _loggedAt = picked);
  }

  void _setRelativeTime(Duration ago) {
    Haptics.selectionClick();
    setState(() => _loggedAt = DateTime.now().subtract(ago));
  }

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(todayDiaperStatsProvider);
    final lastAt = ref.watch(lastDiaperAtProvider);
    final recentDiapers = ref.watch(recentDiapersProvider);

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/dashboard'),
        ),
        title: const Text(
          'Diaper',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _onRefresh,
          color: AppColors.primary,
          child: ListView(
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              _buildTodayStats(stats, lastAt),
              const SizedBox(height: 16),
              _buildTypeSelector(),
              const SizedBox(height: 16),
              if (_showColorPicker) ...[
                _buildColorPicker(),
                const SizedBox(height: 16),
                _buildStoolTypePicker(),
                const SizedBox(height: 16),
              ],
              _buildTimeSelector(),
              const SizedBox(height: 16),
              _buildNotesField(),
              const SizedBox(height: 20),
              _buildSaveButton(),
              const SizedBox(height: 24),
              _buildRecentList(recentDiapers),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTodayStats(
    AsyncValue<dynamic> stats,
    AsyncValue<DateTime?> lastAt,
  ) {
    return AnimatedCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: stats.when(
          loading: () => const SizedBox(
            height: 48,
            child: Center(
              child: CircularProgressIndicator(
                  color: AppColors.primary, strokeWidth: 2),
            ),
          ),
          error: (_, _) => Text(
            'Could not load today\'s stats',
            style: TextStyle(color: context.palette.muted),
          ),
          data: (data) {
            final wet = data['wet'] ?? 0;
            final dirty = data['dirty'] ?? 0;
            final both = data['both'] ?? 0;
            final last = lastAt.asData?.value;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Today',
                      style: TextStyle(
                        color: context.palette.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const Spacer(),
                    if (last != null) _buildSinceLastBadge(last),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildStatChip(
                        Icons.water_drop_outlined, '$wet', 'Wet', Colors.blue),
                    _buildStatChip(Icons.circle, '$dirty', 'Dirty',
                        const Color(0xFF8B4513)),
                    _buildStatChip(Icons.layers_outlined, '$both', 'Both',
                        AppColors.primary),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSinceLastBadge(DateTime last) {
    final diff = DateTime.now().difference(last);
    final hours = diff.inHours;
    final minutes = diff.inMinutes % 60;
    final label = hours > 0 ? '${hours}h ${minutes}m' : '${diff.inMinutes}m';
    final isOverdue = hours >= 3;
    final color = isOverdue ? Colors.orange.shade700 : AppColors.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule_rounded, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            'Last $label ago',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeSelector() {
    final now = DateTime.now();
    final isNow = now.difference(_loggedAt).inSeconds.abs() < 60;
    final isToday = _loggedAt.year == now.year &&
        _loggedAt.month == now.month &&
        _loggedAt.day == now.day;
    final isYesterday = _loggedAt.year == now.year &&
        _loggedAt.month == now.month &&
        _loggedAt.day == now.day - 1;

    final timeStr = DateFormat('h:mm a').format(_loggedAt);
    String fullLabel;
    if (isNow) {
      fullLabel = 'Right now';
    } else if (isToday) {
      fullLabel = 'Today, $timeStr';
    } else if (isYesterday) {
      fullLabel = 'Yesterday, $timeStr';
    } else {
      fullLabel = DateFormat('EEE, MMM d • h:mm a').format(_loggedAt);
    }

    // A custom time is anything not matching one of the quick options.
    final isQuickPick = isNow ||
        _matchesAgo(const Duration(minutes: 15)) ||
        _matchesAgo(const Duration(minutes: 30)) ||
        _matchesAgo(const Duration(hours: 1));
    final isCustom = !isQuickPick;

    return AnimatedCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'When did it happen?',
              style: TextStyle(
                color: context.palette.text,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Quick pick or set a specific time',
              style: TextStyle(
                color: context.palette.muted,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 14),

            // Quick options - most-used live here.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _TimePill(
                  label: 'Now',
                  selected: isNow,
                  onTap: () => _setRelativeTime(Duration.zero),
                ),
                _TimePill(
                  label: '15m ago',
                  selected: _matchesAgo(const Duration(minutes: 15)),
                  onTap: () =>
                      _setRelativeTime(const Duration(minutes: 15)),
                ),
                _TimePill(
                  label: '30m ago',
                  selected: _matchesAgo(const Duration(minutes: 30)),
                  onTap: () =>
                      _setRelativeTime(const Duration(minutes: 30)),
                ),
                _TimePill(
                  label: '1h ago',
                  selected: _matchesAgo(const Duration(hours: 1)),
                  onTap: () => _setRelativeTime(const Duration(hours: 1)),
                ),
              ],
            ),

            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: Divider(color: context.palette.muted.withValues(alpha: 0.2))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    'OR',
                    style: TextStyle(
                      color: context.palette.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                Expanded(child: Divider(color: context.palette.muted.withValues(alpha: 0.2))),
              ],
            ),
            const SizedBox(height: 14),

            // Separate, prominent custom-time tile.
            _CustomTimeTile(
              label: fullLabel,
              selected: isCustom,
              onTap: _pickDateTime,
            ),
          ],
        ),
      ),
    );
  }

  bool _matchesAgo(Duration target) {
    final actual = DateTime.now().difference(_loggedAt);
    return (actual - target).abs() < const Duration(seconds: 30);
  }

  String _itemTimeLabel(DateTime loggedAt) {
    final now = DateTime.now();
    final diff = now.difference(loggedAt);
    if (diff.inHours < 6) return AppDateUtils.timeAgo(loggedAt);

    final isToday = loggedAt.year == now.year &&
        loggedAt.month == now.month &&
        loggedAt.day == now.day;
    final isYesterday = loggedAt.year == now.year &&
        loggedAt.month == now.month &&
        loggedAt.day == now.day - 1;
    final time = DateFormat('h:mm a').format(loggedAt);
    if (isToday) return 'Today, $time';
    if (isYesterday) return 'Yesterday, $time';
    return DateFormat('MMM d, h:mm a').format(loggedAt);
  }

  Widget _buildStatChip(
      IconData icon, String count, String label, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha:0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Text(
                count,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: context.palette.muted,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildTypeSelector() {
    return AnimatedCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'What kind?',
              style: TextStyle(
                color: context.palette.text,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Pick the type of diaper change',
              style: TextStyle(color: context.palette.muted, fontSize: 12),
            ),
            const SizedBox(height: 14),
            Row(
              children: _diaperTypes.map((type) {
                final isSelected = _selectedType == type.$1;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: type.$1 == 'wet' ? 0 : 5,
                      right: type.$1 == 'both' ? 0 : 5,
                    ),
                    child: GestureDetector(
                      onTap: () {
                        Haptics.selectionClick();
                        setState(() {
                          _selectedType = type.$1;
                          if (!_showColorPicker) {
                            _selectedColor = null;
                            _stoolType = null;
                          }
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primary.withValues(alpha: 0.12)
                              : context.palette.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primary
                                : context.palette.muted.withValues(alpha: 0.25),
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              type.$3,
                              size: 26,
                              color: isSelected
                                  ? AppColors.primary
                                  : context.palette.muted,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              type.$2,
                              style: TextStyle(
                                color: isSelected
                                    ? AppColors.primary
                                    : context.palette.text,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColorPicker() {
    return AnimatedCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Poop color',
              style: TextStyle(
                color: context.palette.text,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Helps spot digestion or health changes',
              style: TextStyle(color: context.palette.muted, fontSize: 12),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 16,
              runSpacing: 14,
              alignment: WrapAlignment.center,
              children: _poopColors.map((colorData) {
                final isSelected = _selectedColor == colorData.$1;
                return GestureDetector(
                  onTap: () {
                    Haptics.selectionClick();
                    setState(() {
                      _selectedColor =
                          _selectedColor == colorData.$1 ? null : colorData.$1;
                    });
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: colorData.$3,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primary
                                : context.palette.border,
                            width: isSelected ? 3 : 1.5,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: AppColors.primary.withValues(alpha:0.3),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : null,
                        ),
                        child: isSelected
                            ? const Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 20,
                              )
                            : null,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        colorData.$2,
                        style: TextStyle(
                          color: isSelected ? context.palette.text : context.palette.muted,
                          fontSize: 11,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Color _stoolAccent(CareScalePoint point) {
    if (!point.alert) return AppColors.primary;
    return point.value == 1 ? AppColors.warning : AppColors.error;
  }

  Widget _buildStoolTypePicker() {
    final selected =
        _stoolType == null ? null : CarePackData.stoolTypes[_stoolType! - 1];

    return AnimatedCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Stool type',
              style: TextStyle(
                color: context.palette.text,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Optional - 1 to 7, tap again to clear',
              style: TextStyle(color: context.palette.muted, fontSize: 12),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                for (final point in CarePackData.stoolTypes) ...[
                  if (point.value > 1) const SizedBox(width: 6),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Haptics.selectionClick();
                        setState(() => _stoolType =
                            _stoolType == point.value ? null : point.value);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        height: 44,
                        decoration: BoxDecoration(
                          color: _stoolType == point.value
                              ? _stoolAccent(point).withValues(alpha: 0.15)
                              : context.palette.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _stoolType == point.value
                                ? _stoolAccent(point)
                                : context.palette.muted
                                    .withValues(alpha: 0.25),
                            width: _stoolType == point.value ? 1.5 : 1,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            '${point.value}',
                            style: TextStyle(
                              color: _stoolType == point.value
                                  ? _stoolAccent(point)
                                  : context.palette.muted,
                              fontWeight: _stoolType == point.value
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (selected != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  if (selected.alert) ...[
                    Icon(Icons.warning_amber_rounded,
                        color: _stoolAccent(selected), size: 16),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(
                      selected.label,
                      style: TextStyle(
                        color: selected.alert
                            ? _stoolAccent(selected)
                            : context.palette.muted,
                        fontWeight: selected.alert
                            ? FontWeight.w700
                            : FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNotesField() {
    return AnimatedCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: _notesController,
          maxLines: 3,
          minLines: 1,
          decoration: InputDecoration(
            hintText: 'Add notes (optional)',
            hintStyle: TextStyle(color: context.palette.muted.withValues(alpha:0.6)),
            filled: true,
            fillColor: context.palette.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          style: TextStyle(color: context.palette.text),
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: _isSaving ? null : _save,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.primary.withValues(alpha:0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        child: _isSaving
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : const Text('Save Diaper'),
      ),
    );
  }

  Widget _buildRecentList(AsyncValue<List<dynamic>> recentDiapers) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Recent Diapers',
                style: TextStyle(
                  color: context.palette.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
            ),
            TextButton(
              onPressed: () => context.push('/history?domain=diaper'),
              child: const Text('View all'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        recentDiapers.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          ),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'Failed to load diapers',
                style: TextStyle(color: context.palette.muted),
              ),
            ),
          ),
          data: (diapers) {
            if (diapers.isEmpty) {
              return const EmptyState(
                icon: Icons.baby_changing_station,
                title: 'No diapers yet',
                description: 'Log your first diaper change above',
              );
            }
            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: diapers.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final diaper = diapers[index];
                return _buildDiaperItem(diaper);
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildDiaperItem(dynamic diaper) {
    final type = diaper.type as String;
    final loggedAt = diaper.loggedAt as DateTime;
    final color = diaper.color as String?;
    final diaperId = diaper.id as String;

    IconData icon;
    Color iconColor;
    String label;

    switch (type) {
      case 'wet':
        icon = Icons.water_drop_outlined;
        iconColor = Colors.blue;
        label = 'Wet';
        break;
      case 'dirty':
        icon = Icons.circle;
        iconColor = const Color(0xFF8B4513);
        label = 'Dirty';
        break;
      case 'both':
        icon = Icons.layers_outlined;
        iconColor = AppColors.primary;
        label = 'Both';
        break;
      default:
        icon = Icons.help_outline;
        iconColor = context.palette.muted;
        label = type;
    }

    Color? colorIndicator;
    if (color != null) {
      final match = _poopColors.where((c) => c.$1 == color);
      if (match.isNotEmpty) {
        colorIndicator = match.first.$3;
      }
    }

    return SwipeToDismiss(
      itemId: diaperId,
      onConfirmDismiss: _confirmDelete,
      onDismissed: () => _deleteDiaper(diaperId),
      child: ExpandableHistoryTile(
        notes: diaper.notes as String?,
        details: [
          ('Type', label),
          if (color != null) ('Colour', color),
          ('Time', _itemTimeLabel(loggedAt)),
        ],
        header: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: context.palette.text,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      if (colorIndicator != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: colorIndicator,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: context.palette.border, width: 1),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _itemTimeLabel(loggedAt),
                    style: TextStyle(
                      color: context.palette.muted,
                      fontSize: 13,
                    ),
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

class _CustomTimeTile extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CustomTimeTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.12)
              : context.palette.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : context.palette.muted.withValues(alpha: 0.3),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primary
                    : AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.event_rounded,
                size: 20,
                color: selected ? Colors.white : AppColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    selected ? 'Custom time' : 'Pick a specific date & time',
                    style: TextStyle(
                      color: selected ? AppColors.primary : context.palette.text,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: TextStyle(
                      color: context.palette.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: context.palette.muted,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

class _TimePill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TimePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.15)
              : context.palette.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : context.palette.muted.withValues(alpha: 0.3),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.primary : context.palette.text,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
