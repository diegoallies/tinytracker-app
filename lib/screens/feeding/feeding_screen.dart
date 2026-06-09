import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../config/theme.dart';
import '../../models/baby_medication.dart';
import '../../providers/baby_medication_provider.dart';
import '../../providers/baby_provider.dart';
import '../../providers/feeding_provider.dart';
import '../../providers/feeding_settings_provider.dart';
import '../../providers/health_provider.dart';
import '../../services/medication_guard.dart';
import '../../utils/date_utils.dart';
import '../../utils/extensions.dart';
import '../../utils/haptics.dart';
import '../../widgets/common/animated_card.dart';
import '../../widgets/common/app_dialogs.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/swipe_to_dismiss.dart';
import '../../widgets/medications/add_medication_dialog.dart';

class FeedingScreen extends ConsumerStatefulWidget {
  const FeedingScreen({super.key});

  @override
  ConsumerState<FeedingScreen> createState() => _FeedingScreenState();
}

class _FeedingScreenState extends ConsumerState<FeedingScreen> {
  final TextEditingController _amountController =
      TextEditingController(text: '60');
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _dosageController = TextEditingController();
  bool _isSaving = false;
  DateTime _loggedAt = DateTime.now();
  bool _addMeds = false;

  String _selectedType = 'bottle';
  int? _durationMinutes; // for breast feeds
  BabyMedication? _selectedMedication;
  int? _feedQuality; // optional 1–5 "how did the feed go?"
  bool _hadSpitup = false;

  static const _allFeedTypes = [
    ('breast_left', 'Left Breast', Icons.woman),
    ('breast_right', 'Right Breast', Icons.woman),
    ('bottle', 'Bottle', Icons.baby_changing_station),
    ('solids', 'Solids', Icons.restaurant),
  ];

  static const _bottleOnlyFeedTypes = [
    ('bottle', 'Bottle', Icons.baby_changing_station),
    ('solids', 'Solids', Icons.restaurant),
  ];

  static const _bottlePresetsMl = [30, 60, 90, 120, 180];
  static const _breastPresetsMin = [5, 10, 15, 20, 25, 30];

  bool get _isBreastFeeding =>
      _selectedType == 'breast_left' || _selectedType == 'breast_right';
  bool get _isBottle => _selectedType == 'bottle';

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();
    _dosageController.dispose();
    super.dispose();
  }

  void _adjustAmount(int delta) {
    Haptics.lightTap();
    final current = int.tryParse(_amountController.text) ?? 0;
    final next = (current + delta).clamp(0, 500);
    _amountController.text = next.toString();
  }

  Future<void> _save() async {
    final baby = ref.read(selectedBabyProvider);
    if (baby == null) return;

    final canLogMeds = ref.read(babyProvider).canLogMeds;

    if (_addMeds && canLogMeds && _selectedMedication == null) {
      context.showErrorSnackBar('Pick a medication first.');
      return;
    }

    if (_isBreastFeeding && (_durationMinutes == null || _durationMinutes! <= 0)) {
      context.showErrorSnackBar('Pick a duration first.');
      return;
    }

    if (_isBreastFeeding && _durationMinutes! > 120) {
      context.showErrorSnackBar(
          'That duration looks off — please enter 1–120 minutes.');
      return;
    }

    if (_isBottle) {
      final amount = int.tryParse(_amountController.text);
      if (amount == null || amount < 1 || amount > 500) {
        context.showErrorSnackBar(
            'That amount looks off — please enter 1–500 ml.');
        return;
      }
    }

    // Dose-safety check before anything is inserted. Cancelling only skips
    // the medication — the feeding itself still gets logged.
    var giveMed = _addMeds && canLogMeds && _selectedMedication != null;
    var medSkipped = false;
    if (giveMed) {
      final check = await MedicationGuard.check(
        babyId: baby.id,
        med: _selectedMedication!,
        at: _loggedAt,
      );
      if (!check.ok) {
        if (!mounted) return;
        final proceed = await showConfirmDialog(
          context,
          title: 'Double-check this dose',
          message: '${check.warning}\n\nGive it anyway?',
          confirmLabel: 'Give anyway',
          destructive: true,
          icon: Icons.medication_rounded,
        );
        if (!proceed) {
          giveMed = false;
          medSkipped = true;
        }
      }
      if (!mounted) return;
    }

    setState(() => _isSaving = true);

    try {
      await FeedingActions.logFeeding(
        babyId: baby.id,
        type: _selectedType,
        durationMinutes: _isBreastFeeding ? _durationMinutes : null,
        amountMl: _isBottle ? int.tryParse(_amountController.text) : null,
        quality: _feedQuality,
        hadSpitup: _hadSpitup,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        loggedAt: _loggedAt,
      );

      if (giveMed) {
        await HealthActions.logHealth(
          babyId: baby.id,
          medication: _selectedMedication!.name,
          dosage: _dosageController.text.trim().isEmpty
              ? null
              : _dosageController.text.trim(),
          loggedAt: _loggedAt,
        );
      }

      if (!mounted) return;
      ref.invalidate(recentFeedingsProvider);
      if (giveMed) ref.invalidate(medicationDosesTodayProvider);

      setState(() {
        _notesController.clear();
        _amountController.text = '60';
        _dosageController.clear();
        _durationMinutes = null;
        _selectedMedication = null;
        _addMeds = false;
        _feedQuality = null;
        _hadSpitup = false;
        _loggedAt = DateTime.now();
      });

      Haptics.mediumTap();

      if (mounted) {
        if (medSkipped) {
          context.showSnackBar('Feeding logged without the medication.');
        } else {
          context.showSuccessSnackBar('Feeding logged');
        }
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar(
          'Couldn’t save the feeding. Check your connection and try again.',
          onRetry: _save,
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<bool?> _confirmDelete() {
    return showDeleteDialog(context, what: 'Feeding');
  }

  Future<void> _deleteFeeding(String feedingId) async {
    try {
      await FeedingActions.deleteFeeding(feedingId);
      ref.invalidate(recentFeedingsProvider);
      if (mounted) {
        context.showSuccessSnackBar('Feeding deleted');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar(
          'Couldn’t delete the feeding. Check your connection and try again.',
        );
      }
    }
  }

  Future<void> _onRefresh() async {
    Haptics.lightTap();
    ref.invalidate(recentFeedingsProvider);
    await ref.read(recentFeedingsProvider.future);
  }

  Future<void> _pickTime({required bool allowDateChange}) async {
    final now = DateTime.now();
    DateTime baseDate = _loggedAt;

    if (allowDateChange) {
      final date = await showDatePicker(
        context: context,
        initialDate: _loggedAt,
        firstDate: now.subtract(const Duration(days: 30)),
        lastDate: now,
      );
      if (date == null || !mounted) return;
      baseDate = date;
    } else {
      baseDate = DateTime(now.year, now.month, now.day);
    }

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_loggedAt),
    );
    if (time == null) return;

    final picked = DateTime(
        baseDate.year, baseDate.month, baseDate.day, time.hour, time.minute);
    if (picked.isAfter(DateTime.now())) {
      if (mounted) context.showErrorSnackBar('Can’t log a time in the future.');
      return;
    }
    Haptics.selectionClick();
    setState(() => _loggedAt = picked);
  }

  void _setRelativeTime(Duration ago) {
    Haptics.selectionClick();
    setState(() => _loggedAt = DateTime.now().subtract(ago));
  }

  bool _matchesAgo(Duration target) {
    final actual = DateTime.now().difference(_loggedAt);
    return (actual - target).abs() < const Duration(seconds: 30);
  }

  Future<void> _showCustomDurationSheet() async {
    Haptics.selectionClick();
    final controller = TextEditingController(
      text: (_durationMinutes ?? 10).toString(),
    );
    final value = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          24, 16, 24, MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: ctx.palette.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'Custom duration',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: ctx.palette.text,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(3),
              ],
              autofocus: true,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: ctx.palette.text,
              ),
              decoration: InputDecoration(
                suffixText: 'min',
                filled: true,
                fillColor: ctx.palette.surface,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () =>
                  Navigator.pop(ctx, int.tryParse(controller.text)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Set'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (value == null || value <= 0) return;
    setState(() => _durationMinutes = value);
  }

  Future<void> _showCustomAmountSheet() async {
    Haptics.selectionClick();
    final controller = TextEditingController(text: _amountController.text);
    final value = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 16, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: ctx.palette.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'Custom amount',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: ctx.palette.text,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(3),
              ],
              autofocus: true,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: ctx.palette.text,
              ),
              decoration: InputDecoration(
                suffixText: 'ml',
                filled: true,
                fillColor: ctx.palette.surface,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx, int.tryParse(controller.text));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Set'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (value == null) return;
    setState(() => _amountController.text = value.toString());
  }

  Future<void> _pickMedication() async {
    final baby = ref.read(selectedBabyProvider);
    if (baby == null) return;
    final isOwner = ref.read(babyProvider).isOwner;

    final picked = await showModalBottomSheet<BabyMedication>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.palette.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _MedicationPickerSheet(
        babyId: baby.id,
        isOwner: isOwner,
      ),
    );

    if (picked != null) {
      setState(() {
        _selectedMedication = picked;
        if (picked.defaultDosage != null && _dosageController.text.isEmpty) {
          _dosageController.text = picked.defaultDosage!;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final recentFeedings = ref.watch(recentFeedingsWithMedsProvider);

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Feeding',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _onRefresh,
          color: AppColors.primary,
          child: ListView(
            physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics()),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              _buildTypeSelector(),
              const SizedBox(height: 16),
              if (_isBreastFeeding) ...[
                _buildDurationPicker(),
                const SizedBox(height: 16),
              ],
              if (_isBottle) ...[
                _buildAmountInput(),
                const SizedBox(height: 16),
              ],
              _buildTimeSelector(),
              const SizedBox(height: 16),
              _buildMedsSection(),
              const SizedBox(height: 16),
              _buildFeedQualitySection(),
              const SizedBox(height: 16),
              _buildNotesField(),
              const SizedBox(height: 20),
              _buildSaveButton(),
              const SizedBox(height: 24),
              _buildRecentList(recentFeedings),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypeSelector() {
    final showBreast = ref.watch(showBreastFeedingProvider);
    final feedTypes = showBreast ? _allFeedTypes : _bottleOnlyFeedTypes;

    return AnimatedCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Feed Type',
              style: TextStyle(
                color: context.palette.text,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.8,
              children: feedTypes.map((type) {
                final isSelected = _selectedType == type.$1;
                return GestureDetector(
                  onTap: () {
                    Haptics.selectionClick();
                    setState(() {
                      _selectedType = type.$1;
                      _durationMinutes = null;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary.withValues(alpha: 0.15)
                          : context.palette.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primary
                            : context.palette.muted.withValues(alpha: 0.3),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          type.$3,
                          size: 18,
                          color: isSelected
                              ? AppColors.primary
                              : context.palette.muted,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            type.$2,
                            style: TextStyle(
                              color: isSelected
                                  ? AppColors.primary
                                  : context.palette.muted,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
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

  Widget _buildDurationPicker() {
    return AnimatedCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Duration',
                  style: TextStyle(
                    color: context.palette.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                if (_durationMinutes != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$_durationMinutes min',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in _breastPresetsMin)
                  _Pill(
                    label: '${m}m',
                    selected: _durationMinutes == m,
                    onTap: () {
                      Haptics.selectionClick();
                      setState(() => _durationMinutes = m);
                    },
                  ),
                _Pill(
                  label: 'Custom',
                  icon: Icons.edit_rounded,
                  selected: _durationMinutes != null &&
                      !_breastPresetsMin.contains(_durationMinutes),
                  onTap: _showCustomDurationSheet,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAmountInput() {
    final currentMl = int.tryParse(_amountController.text);
    return AnimatedCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Amount',
              style: TextStyle(
                color: context.palette.text,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final ml in _bottlePresetsMl)
                  _Pill(
                    label: '${ml}ml',
                    selected: currentMl == ml,
                    onTap: () {
                      Haptics.selectionClick();
                      setState(() => _amountController.text = ml.toString());
                    },
                  ),
                _Pill(
                  label: 'Custom',
                  icon: Icons.edit_rounded,
                  selected: currentMl != null &&
                      !_bottlePresetsMl.contains(currentMl),
                  onTap: _showCustomAmountSheet,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _StepButton(icon: Icons.remove, onTap: () => _adjustAmount(-10)),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(3),
                    ],
                    textAlign: TextAlign.center,
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: context.palette.text,
                    ),
                    decoration: InputDecoration(
                      suffixText: 'ml',
                      suffixStyle: TextStyle(
                        fontSize: 16,
                        color: context.palette.muted,
                      ),
                      filled: true,
                      fillColor: context.palette.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _StepButton(icon: Icons.add, onTap: () => _adjustAmount(10)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeSelector() {
    final isOwner = ref.watch(babyProvider).isOwner;
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

            // Quick options — most-used live here.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Pill(
                  label: 'Now',
                  selected: isNow,
                  onTap: () => _setRelativeTime(Duration.zero),
                ),
                _Pill(
                  label: '15m ago',
                  selected: _matchesAgo(const Duration(minutes: 15)),
                  onTap: () => _setRelativeTime(const Duration(minutes: 15)),
                ),
                _Pill(
                  label: '30m ago',
                  selected: _matchesAgo(const Duration(minutes: 30)),
                  onTap: () => _setRelativeTime(const Duration(minutes: 30)),
                ),
                _Pill(
                  label: '1h ago',
                  selected: _matchesAgo(const Duration(hours: 1)),
                  onTap: () => _setRelativeTime(const Duration(hours: 1)),
                ),
              ],
            ),

            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Divider(
                      color: context.palette.muted.withValues(alpha: 0.2)),
                ),
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
                Expanded(
                  child: Divider(
                      color: context.palette.muted.withValues(alpha: 0.2)),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Separate, prominent custom-time tile.
            _CustomTimeTile(
              label: fullLabel,
              selected: isCustom,
              isOwner: isOwner,
              onTap: () => _pickTime(allowDateChange: isOwner),
            ),
            if (!isOwner)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'Only the owner can log on past days.',
                  style: TextStyle(
                    fontSize: 11,
                    color: context.palette.muted.withValues(alpha: 0.8),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMedsSection() {
    final canLogMeds = ref.watch(babyProvider).canLogMeds;
    if (!canLogMeds) return const SizedBox.shrink();

    return AnimatedCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.pastelPink,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.medical_services_rounded,
                    size: 18,
                    color: Color(0xFFE91E63),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Give medication',
                        style: TextStyle(
                          color: context.palette.text,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        'Logged at the same time as this feeding',
                        style: TextStyle(
                          color: context.palette.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value: _addMeds,
                  onChanged: (v) {
                    Haptics.selectionClick();
                    setState(() {
                      _addMeds = v;
                      if (!v) {
                        _selectedMedication = null;
                        _dosageController.clear();
                      }
                    });
                  },
                  activeTrackColor: AppColors.primary.withValues(alpha: 0.5),
                  activeThumbColor: AppColors.primary,
                ),
              ],
            ),
            if (_addMeds) ...[
              const SizedBox(height: 14),
              _MedicationSelector(
                selected: _selectedMedication,
                onTap: _pickMedication,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _dosageController,
                decoration: InputDecoration(
                  hintText: 'Dosage (e.g. 2.5 ml)',
                  hintStyle: TextStyle(
                      color: context.palette.muted.withValues(alpha: 0.6)),
                  filled: true,
                  fillColor: context.palette.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                ),
                style: TextStyle(color: context.palette.text),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFeedQualitySection() {
    return AnimatedCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How did the feed go?',
              style: TextStyle(
                color: context.palette.text,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Optional — tap a star again to clear',
              style: TextStyle(color: context.palette.muted, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (var star = 1; star <= 5; star++)
                  GestureDetector(
                    onTap: () {
                      Haptics.selectionClick();
                      setState(() =>
                          _feedQuality = _feedQuality == star ? null : star);
                    },
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Icon(
                        Icons.star_rounded,
                        size: 32,
                        color: _feedQuality != null && star <= _feedQuality!
                            ? AppColors.warning
                            : context.palette.muted.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _SpitupChip(
              selected: _hadSpitup,
              onTap: () {
                Haptics.selectionClick();
                setState(() => _hadSpitup = !_hadSpitup);
              },
            ),
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
            hintStyle: TextStyle(
                color: context.palette.muted.withValues(alpha: 0.6)),
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
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
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
            : const Text('Save Feeding'),
      ),
    );
  }

  Widget _buildRecentList(AsyncValue<List<dynamic>> recentFeedings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Recent Feedings',
                style: TextStyle(
                  color: context.palette.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
            ),
            TextButton(
              onPressed: () => context.push('/history?domain=feeding'),
              child: const Text('View all'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        recentFeedings.when(
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
                'Failed to load feedings\n$error',
                textAlign: TextAlign.center,
                style:
                    TextStyle(color: context.palette.muted, fontSize: 13),
              ),
            ),
          ),
          data: (feedings) {
            if (feedings.isEmpty) {
              return const EmptyState(
                icon: Icons.restaurant_outlined,
                title: 'No feedings yet',
                description: 'Log your first feeding above',
              );
            }
            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: feedings.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final feeding = feedings[index];
                return _buildFeedingItem(feeding);
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildFeedingItem(dynamic item) {
    final feeding = item.feeding;
    final type = feeding.type as String;
    final loggedAt = (feeding.loggedAt as DateTime).toLocal();
    final feedingId = feeding.id as String;
    final medication = item.medication as String?;
    final dosage = item.dosage as String?;
    final hasMed = medication != null && medication.isNotEmpty;

    IconData icon;
    String label;
    String detail;

    switch (type) {
      case 'breast_left':
        icon = Icons.woman;
        label = 'Left Breast';
        detail = feeding.durationMinutes != null
            ? '${feeding.durationMinutes} min'
            : '';
        break;
      case 'breast_right':
        icon = Icons.woman;
        label = 'Right Breast';
        detail = feeding.durationMinutes != null
            ? '${feeding.durationMinutes} min'
            : '';
        break;
      case 'bottle':
        icon = Icons.baby_changing_station;
        label = 'Bottle';
        detail = feeding.amountMl != null ? '${feeding.amountMl} ml' : '';
        break;
      case 'solids':
        icon = Icons.restaurant;
        label = 'Solids';
        detail = '';
        break;
      default:
        icon = Icons.restaurant;
        label = type;
        detail = '';
    }

    return SwipeToDismiss(
      itemId: feedingId,
      onConfirmDismiss: _confirmDelete,
      onDismissed: () => _deleteFeeding(feedingId),
      child: AnimatedCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.pastelPurple,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: context.palette.text,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _itemTimeLabel(loggedAt),
                      style: TextStyle(
                        color: context.palette.muted,
                        fontSize: 13,
                      ),
                    ),
                    if (hasMed) ...[
                      const SizedBox(height: 6),
                      _MedBadge(medication: medication, dosage: dosage),
                    ],
                  ],
                ),
              ),
              if (detail.isNotEmpty)
                Text(
                  detail,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
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
}

// ──────────────────────────────────────────────────────────────────────
// Small badge showing the medication + dosage given with this feeding
// ──────────────────────────────────────────────────────────────────────

class _MedBadge extends StatelessWidget {
  final String? medication;
  final String? dosage;

  const _MedBadge({required this.medication, required this.dosage});

  @override
  Widget build(BuildContext context) {
    final med = medication ?? '';
    final dose = dosage?.trim() ?? '';
    final label = dose.isEmpty ? med : '$med · $dose';
    const accent = Color(0xFFE91E63);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.pastelPink.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.medical_services_rounded,
            size: 12,
            color: accent,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Medication selector field (looks like a dropdown row)
// ──────────────────────────────────────────────────────────────────────

class _MedicationSelector extends StatelessWidget {
  final BabyMedication? selected;
  final VoidCallback onTap;

  const _MedicationSelector({required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: context.palette.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                Icons.medication_rounded,
                size: 20,
                color: selected != null
                    ? AppColors.primary
                    : context.palette.muted.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  selected?.name ?? 'Select medication',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: selected != null
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: selected != null
                        ? context.palette.text
                        : context.palette.muted.withValues(alpha: 0.7),
                  ),
                ),
              ),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: context.palette.muted.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Medication picker bottom sheet (with owner-only Add)
// ──────────────────────────────────────────────────────────────────────

class _MedicationPickerSheet extends ConsumerStatefulWidget {
  final String babyId;
  final bool isOwner;

  const _MedicationPickerSheet({required this.babyId, required this.isOwner});

  @override
  ConsumerState<_MedicationPickerSheet> createState() =>
      _MedicationPickerSheetState();
}

class _MedicationPickerSheetState
    extends ConsumerState<_MedicationPickerSheet> {
  Future<void> _showAddDialog() async {
    final added = await showDialog<BabyMedication>(
      context: context,
      builder: (_) => AddMedicationDialog(babyId: widget.babyId),
    );

    if (added != null) {
      ref.invalidate(babyMedicationsProvider);
      if (mounted) Navigator.pop(context, added);
    }
  }

  Future<void> _deleteMedication(BabyMedication med) async {
    final confirmed = await showDeleteDialog(
      context,
      what: 'Medication',
      message: 'Remove "${med.name}" from the baby\'s medications?',
    );

    if (!confirmed) return;

    try {
      await BabyMedicationActions.delete(med.id);
      ref.invalidate(babyMedicationsProvider);
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar(
          'Couldn’t delete the medication. Check your connection and try again.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final medsAsync = ref.watch(babyMedicationsProvider);
    final dosesToday = ref.watch(medicationDosesTodayProvider).asData?.value ??
        const <String, List<DateTime>>{};

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: context.palette.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Text(
                  'Medications',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: context.palette.text,
                  ),
                ),
                const Spacer(),
                if (widget.isOwner)
                  TextButton.icon(
                    onPressed: _showAddDialog,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              child: medsAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Failed to load: $e',
                    style: TextStyle(color: Colors.red.shade400, fontSize: 13),
                  ),
                ),
                data: (meds) {
                  if (meds.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Column(
                        children: [
                          Icon(
                            Icons.medication_outlined,
                            size: 48,
                            color: context.palette.muted,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No medications yet',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: context.palette.text,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.isOwner
                                ? 'Tap Add to create one'
                                : 'Ask the owner to add medications',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.palette.muted,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: meds.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (ctx, i) => _MedicationListTile(
                      med: meds[i],
                      dosesToday: dosesToday[
                              meds[i].name.trim().toLowerCase()] ??
                          const [],
                      isOwner: widget.isOwner,
                      onTap: () => Navigator.pop(context, meds[i]),
                      onDelete: () => _deleteMedication(meds[i]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MedicationListTile extends StatelessWidget {
  final BabyMedication med;
  final List<DateTime> dosesToday;
  final bool isOwner;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _MedicationListTile({
    required this.med,
    required this.dosesToday,
    required this.isOwner,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final status = MedicationGuard.todayStatus(med, dosesToday);
    final statusColor =
        status.done ? AppColors.success : context.palette.muted;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: context.palette.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.pastelPink,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.medication_rounded,
                  size: 18,
                  color: Color(0xFFE91E63),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      med.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: context.palette.text,
                      ),
                    ),
                    if (med.defaultDosage != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        med.defaultDosage!,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.palette.muted,
                        ),
                      ),
                    ],
                    if (med.instructions != null &&
                        med.instructions!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        med.instructions!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: context.palette.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  status.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
              if (isOwner)
                IconButton(
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: 20,
                    color: Colors.red.shade300,
                  ),
                  onPressed: onDelete,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Prominent "Pick a specific date & time" tile shown below the quick pills
// ──────────────────────────────────────────────────────────────────────

class _CustomTimeTile extends StatelessWidget {
  final String label;
  final bool selected;
  final bool isOwner;
  final VoidCallback onTap;

  const _CustomTimeTile({
    required this.label,
    required this.selected,
    required this.isOwner,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final headline = selected
        ? 'Custom time'
        : (isOwner ? 'Pick a specific date & time' : 'Pick a specific time');

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
                isOwner ? Icons.event_rounded : Icons.schedule_rounded,
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
                    headline,
                    style: TextStyle(
                      color: selected
                          ? AppColors.primary
                          : context.palette.text,
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

// ──────────────────────────────────────────────────────────────────────
// Reusable shared pill + step button
// ──────────────────────────────────────────────────────────────────────

class _Pill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 14,
                color: selected ? AppColors.primary : context.palette.muted,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? AppColors.primary : context.palette.text,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpitupChip extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;

  const _SpitupChip({required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.warning.withValues(alpha: 0.15)
              : context.palette.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? AppColors.warning
                : context.palette.muted.withValues(alpha: 0.3),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.water_drop_outlined,
              size: 16,
              color: selected ? AppColors.warning : context.palette.muted,
            ),
            const SizedBox(width: 6),
            Text(
              'Spit-up after feed',
              style: TextStyle(
                color: selected ? AppColors.warning : context.palette.text,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _StepButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.pastelPurple,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(icon, color: AppColors.primary),
        ),
      ),
    );
  }
}

