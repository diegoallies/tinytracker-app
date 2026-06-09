import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/design_tokens.dart';
import '../../config/theme.dart';
import '../../models/baby_medication.dart';
import '../../providers/baby_medication_provider.dart';
import '../../providers/baby_provider.dart';
import '../../models/health_log.dart';
import '../../providers/health_provider.dart';
import '../../services/medication_guard.dart';
import '../../utils/date_utils.dart';
import '../../utils/extensions.dart';
import '../../utils/haptics.dart';
import '../../widgets/common/animated_card.dart';
import '../../widgets/common/app_dialogs.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/medications/add_medication_dialog.dart';
import '../../widgets/medications/dose_row.dart';
import '../../widgets/medications/give_dose_sheet.dart';

enum HealthTab { temperature, medication }

/// Provider to check if user can administer meds (owner or parent role)
final canAdministerMedsProvider = Provider<bool>((ref) {
  final babyState = ref.watch(babyProvider);
  // Only owner or parent role can administer meds (not logger/nanny/viewer)
  return babyState.isOwner || babyState.role == 'parent';
});

class HealthScreen extends ConsumerStatefulWidget {
  const HealthScreen({super.key});

  @override
  ConsumerState<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends ConsumerState<HealthScreen>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;
  bool? _lastCanAdministerMeds;

  final _tempController = TextEditingController();
  final _medicationController = TextEditingController();
  final _dosageController = TextEditingController();
  final _symptomsController = TextEditingController();
  final _notesController = TextEditingController();

  bool _isSaving = false;

  /// Whether the one-off "log a different medicine" form is expanded on the
  /// Medication tab. The daily checklist is the primary flow.
  bool _showOneOff = false;

  @override
  void initState() {
    super.initState();
    // TabController will be initialized in build based on role
  }

  void _initTabController(bool canAdministerMeds) {
    if (_lastCanAdministerMeds != canAdministerMeds || _tabController == null) {
      _tabController?.dispose();
      _tabController = TabController(
        length: canAdministerMeds ? 2 : 1,
        vsync: this,
      );
      _tabController!.addListener(() => setState(() {}));
      _lastCanAdministerMeds = canAdministerMeds;
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _tempController.dispose();
    _medicationController.dispose();
    _dosageController.dispose();
    _symptomsController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  ({Color color, String label, IconData icon}) _getTempStatus(double temp) {
    if (temp < 36.0) {
      return (
        color: Colors.blue,
        label: 'Low',
        icon: Icons.ac_unit,
      );
    } else if (temp <= 37.5) {
      return (
        color: const Color(0xFF4CAF50),
        label: 'Normal',
        icon: Icons.check_circle_outline,
      );
    } else if (temp <= 38.5) {
      return (
        color: Colors.orange,
        label: 'Fever',
        icon: Icons.warning_amber,
      );
    } else {
      return (
        color: Colors.red,
        label: 'High Fever',
        icon: Icons.local_fire_department,
      );
    }
  }

  Future<void> _saveHealth() async {
    final baby = ref.read(selectedBabyProvider);
    if (baby == null) return;

    final temp = double.tryParse(_tempController.text);
    final medication = _medicationController.text.trim();
    final dosage = _dosageController.text.trim();
    final symptoms = _symptomsController.text.trim();
    final notes = _notesController.text.trim();

    final isTemperatureTab = _tabController!.index == 0;

    if (isTemperatureTab && temp == null) {
      context.showErrorSnackBar('Please enter a valid temperature');
      return;
    }

    // Sanity bounds — a real body temperature stays well inside this range.
    if (isTemperatureTab && temp != null && (temp < 30 || temp > 43)) {
      context.showErrorSnackBar(
          'That temperature looks off — please enter 30–43 °C.');
      return;
    }

    if (!isTemperatureTab && medication.isEmpty) {
      context.showErrorSnackBar('Please enter a medication name');
      return;
    }

    // Dose-safety check before the medication log is inserted.
    if (!isTemperatureTab && medication.isNotEmpty) {
      var catalog = const <BabyMedication>[];
      try {
        catalog = await ref.read(babyMedicationsProvider.future);
      } catch (_) {
        // No catalog (offline?) — the guard simply won't match anything.
      }
      final check = await MedicationGuard.checkByName(
        babyId: baby.id,
        name: medication,
        catalog: catalog,
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
        if (!proceed) return;
      }
      if (!mounted) return;
    }

    setState(() => _isSaving = true);

    try {
      await HealthActions.logHealth(
        babyId: baby.id,
        temperatureC: isTemperatureTab ? temp : null,
        medication: !isTemperatureTab && medication.isNotEmpty
            ? medication
            : null,
        dosage: !isTemperatureTab && dosage.isNotEmpty ? dosage : null,
        symptoms: symptoms.isNotEmpty ? symptoms : null,
        notes: notes.isNotEmpty ? notes : null,
      );

      ref.invalidate(healthLogsProvider);
      ref.invalidate(medicationDosesTodayProvider);
      ref.invalidate(medDoseLogsTodayProvider);

      _tempController.clear();
      _medicationController.clear();
      _dosageController.clear();
      _symptomsController.clear();
      _notesController.clear();

      if (mounted) {
        context.showSuccessSnackBar('Health log saved');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar(
          'Couldn’t save the health log. Check your connection and try again.',
          onRetry: _saveHealth,
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final healthLogs = ref.watch(healthLogsProvider);
    final canAdministerMeds = ref.watch(canAdministerMedsProvider);

    // Initialize/update tab controller based on role
    _initTabController(canAdministerMeds);

    return Scaffold(
      backgroundColor: context.palette.surface,
      appBar: AppBar(
        title: const Text('Health'),
        backgroundColor: context.palette.card,
        foregroundColor: context.palette.text,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _buildInputCard(),
            const SizedBox(height: 24),
            healthLogs.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(
                    color: Color(0xFF9B72CF),
                  ),
                ),
              ),
              error: (error, _) => Center(
                child: Text('Error: $error'),
              ),
              data: (logs) {
                if (logs.isEmpty) {
                  return const EmptyState(
                    icon: Icons.medical_services_outlined,
                    title: 'No health logs yet',
                    description: 'Log a temperature or medication above',
                  );
                }
                return _buildLogsList(logs);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputCard() {
    final canAdministerMeds = ref.watch(canAdministerMedsProvider);

    return AnimatedCard(
      child: Column(
        children: [
          // Only show tabs if user can administer meds
          if (canAdministerMeds)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              decoration: BoxDecoration(
                color: context.palette.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: const Color(0xFF9B72CF),
                  borderRadius: BorderRadius.circular(10),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerHeight: 0,
                labelColor: Colors.white,
                unselectedLabelColor: context.palette.muted,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
                padding: const EdgeInsets.all(4),
                tabs: const [
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.thermostat, size: 18),
                        SizedBox(width: 6),
                        Text('Temperature'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.medication, size: 18),
                        SizedBox(width: 6),
                        Text('Medication'),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else
            // Header for non-parents (temperature only)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.thermostat,
                      size: 20, color: Color(0xFF9B72CF)),
                  const SizedBox(width: 8),
                  Text(
                    'Temperature',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: context.palette.text,
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SizeTransition(
                    sizeFactor: animation,
                    child: child,
                  ),
                );
              },
              child: (!canAdministerMeds || _tabController?.index == 0)
                  ? Column(
                      key: const ValueKey('temperature'),
                      children: [
                        _buildTemperatureInput(),
                        const SizedBox(height: 12),
                        _buildSharedInputs(),
                        const SizedBox(height: 20),
                        _buildSaveButton(),
                      ],
                    )
                  : _buildMedicationInput(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: _isSaving ? null : _saveHealth,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF9B72CF),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
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
            : const Text(
                'Save Health Log',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }

  Widget _buildTemperatureInput() {
    final temp = double.tryParse(_tempController.text);
    final status = temp != null ? _getTempStatus(temp) : null;

    return Column(
      children: [
        TextFormField(
          controller: _tempController,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d{0,2}\.?\d{0,1}')),
          ],
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Temperature',
            suffixText: '\u00B0C',
            prefixIcon: Icon(
              Icons.thermostat,
              size: 20,
              color: status?.color ?? context.palette.muted,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.palette.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.palette.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: status?.color ?? const Color(0xFF9B72CF),
                width: 2,
              ),
            ),
            filled: true,
            fillColor: context.palette.surface,
          ),
        ),
        if (status != null)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: status.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: status.color.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(status.icon, color: status.color, size: 20),
                const SizedBox(width: 10),
                Text(
                  status.label,
                  style: TextStyle(
                    color: status.color,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const Spacer(),
                Text(
                  '${temp!.toStringAsFixed(1)}\u00B0C',
                  style: TextStyle(
                    color: status.color,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _addSavedMed() async {
    final baby = ref.read(selectedBabyProvider);
    if (baby == null) return;
    Haptics.lightTap();
    final added = await showDialog<BabyMedication>(
      context: context,
      builder: (_) => AddMedicationDialog(babyId: baby.id),
    );
    if (added != null) {
      ref.invalidate(babyMedicationsProvider);
    }
  }

  /// Opens the detail/give-dose sheet for one catalog med.
  void _openMedSheet(BabyMedication med) {
    final baby = ref.read(selectedBabyProvider);
    if (baby == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => GiveDoseSheet(
        babyId: baby.id,
        med: med,
        canEdit: ref.read(babyProvider).isOwner,
      ),
    );
  }

  Widget _buildTodaysDoses() {
    final medsAsync = ref.watch(babyMedicationsProvider);
    final isOwner = ref.watch(babyProvider).isOwner;
    final dosesToday = ref.watch(medicationDosesTodayProvider).asData?.value ??
        const <String, List<DateTime>>{};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.today_rounded,
                size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(
              'Today’s doses',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.palette.text,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        medsAsync.when(
          loading: () => const SizedBox(
            height: 64,
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
          error: (_, _) => const SizedBox.shrink(),
          data: (meds) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (meds.isEmpty)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                    padding: const EdgeInsets.symmetric(
                        vertical: 14, horizontal: 12),
                    decoration: BoxDecoration(
                      color: context.palette.surface,
                      borderRadius: AppRadius.mdAll,
                      border: Border.all(color: context.palette.border),
                    ),
                    child: Text(
                      isOwner
                          ? 'No daily meds yet — add the first one below.'
                          : 'No daily meds saved yet — ask the owner to add some.',
                      style: TextStyle(
                          fontSize: 12, color: context.palette.muted),
                    ),
                  ),
                ...meds.map((m) => MedDoseRow(
                      med: m,
                      dosesToday:
                          dosesToday[m.name.trim().toLowerCase()] ?? const [],
                      onOpen: () => _openMedSheet(m),
                    )),
                if (isOwner) _AddDailyMedRow(onTap: _addSavedMed),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildMedicationInput() {
    return Column(
      key: const ValueKey('medication'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTodaysDoses(),
        const SizedBox(height: AppSpacing.xxs),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              Haptics.selectionClick();
              setState(() => _showOneOff = !_showOneOff);
            },
            icon: AnimatedRotation(
              turns: _showOneOff ? 0.5 : 0,
              duration: AppMotion.fast,
              child: const Icon(Icons.expand_more_rounded, size: 20),
            ),
            label: const Text('Log a different medicine'),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox(width: double.infinity),
          secondChild: _buildOneOffForm(),
          crossFadeState: _showOneOff
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: AppMotion.normal,
          sizeCurve: AppMotion.ease,
        ),
      ],
    );
  }

  /// One-off medicine form — anything not in the daily catalog
  /// (still guarded by [MedicationGuard.checkByName] on save).
  Widget _buildOneOffForm() {
    return Column(
      children: [
        const SizedBox(height: AppSpacing.xxs),
        TextFormField(
          controller: _medicationController,
          decoration: InputDecoration(
            labelText: 'Medication name',
            prefixIcon: const Icon(Icons.medication, size: 20),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.palette.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.palette.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFF9B72CF),
                width: 2,
              ),
            ),
            filled: true,
            fillColor: context.palette.surface,
          ),
          textCapitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _dosageController,
          decoration: InputDecoration(
            labelText: 'Dosage (e.g., 5ml, 100mg)',
            prefixIcon: const Icon(Icons.science_outlined, size: 20),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.palette.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.palette.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFF9B72CF),
                width: 2,
              ),
            ),
            filled: true,
            fillColor: context.palette.surface,
          ),
        ),
        const SizedBox(height: 12),
        _buildSharedInputs(),
        const SizedBox(height: 20),
        _buildSaveButton(),
      ],
    );
  }

  Widget _buildSharedInputs() {
    return Column(
      children: [
        TextFormField(
          controller: _symptomsController,
          decoration: InputDecoration(
            labelText: 'Symptoms (optional)',
            prefixIcon: const Icon(Icons.sick_outlined, size: 20),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.palette.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.palette.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFF9B72CF),
                width: 2,
              ),
            ),
            filled: true,
            fillColor: context.palette.surface,
          ),
          textCapitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _notesController,
          decoration: InputDecoration(
            labelText: 'Notes (optional)',
            prefixIcon: const Icon(Icons.notes, size: 20),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.palette.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.palette.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFF9B72CF),
                width: 2,
              ),
            ),
            filled: true,
            fillColor: context.palette.surface,
          ),
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
        ),
      ],
    );
  }

  Widget _buildLogsList(List<HealthLog> logs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent Logs',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: context.palette.text,
          ),
        ),
        const SizedBox(height: 12),
        ...logs.map((log) => _buildLogItem(log)),
      ],
    );
  }

  Widget _buildLogItem(HealthLog log) {
    final hasTemp = log.temperatureC != null;
    final hasMed = log.medication != null && log.medication!.isNotEmpty;
    final tempStatus =
        hasTemp ? _getTempStatus(log.temperatureC!) : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AnimatedCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    AppDateUtils.formatDate(log.loggedAt),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.palette.text,
                    ),
                  ),
                  Text(
                    AppDateUtils.formatTime(log.loggedAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: context.palette.muted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (hasTemp)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: tempStatus!.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color:
                              tempStatus.color.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.thermostat,
                            size: 14,
                            color: tempStatus.color,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${log.temperatureC!.toStringAsFixed(1)}\u00B0C',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: tempStatus.color,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            tempStatus.label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: tempStatus.color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (hasMed)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8D5F5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.medication,
                            size: 14,
                            color: Color(0xFF9B72CF),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            log.medication!,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF9B72CF),
                            ),
                          ),
                          if (log.dosage != null &&
                              log.dosage!.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            Text(
                              '(${log.dosage})',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF8B85A0),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
              if (log.symptoms != null &&
                  log.symptoms!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.sick_outlined,
                      size: 14,
                      color: context.palette.muted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        log.symptoms!,
                        style: TextStyle(
                          fontSize: 13,
                          color: context.palette.muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (log.notes != null && log.notes!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.notes,
                      size: 14,
                      color: context.palette.muted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        log.notes!,
                        style: TextStyle(
                          fontSize: 13,
                          color: context.palette.muted,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-width "Add daily med" row at the bottom of the checklist.
class _AddDailyMedRow extends StatelessWidget {
  final VoidCallback onTap;
  const _AddDailyMedRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: AppRadius.lgAll,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.lgAll,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: AppRadius.lgAll,
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.45),
              width: 1.2,
            ),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_rounded, size: 18, color: AppColors.primary),
              SizedBox(width: 6),
              Text(
                'Add daily med',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
