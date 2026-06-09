import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/baby_provider.dart';
import '../../models/health_log.dart';
import '../../providers/health_provider.dart';
import '../../utils/date_utils.dart';
import '../../widgets/common/animated_card.dart';
import '../../widgets/common/empty_state.dart';

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid temperature'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (!isTemperatureTab && medication.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a medication name'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
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

      _tempController.clear();
      _medicationController.clear();
      _dosageController.clear();
      _symptomsController.clear();
      _notesController.clear();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Health log saved'),
            backgroundColor: const Color(0xFF4CAF50),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: Colors.red,
          ),
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
      backgroundColor: const Color(0xFFFAF8FC),
      appBar: AppBar(
        title: const Text('Health'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF2D2640),
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
                color: const Color(0xFFFAF8FC),
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
                unselectedLabelColor: const Color(0xFF8B85A0),
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
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.thermostat, size: 20, color: Color(0xFF9B72CF)),
                  SizedBox(width: 8),
                  Text(
                    'Temperature',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2D2640),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                AnimatedSwitcher(
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
                      ? _buildTemperatureInput()
                      : _buildMedicationInput(),
                ),
                const SizedBox(height: 12),
                _buildSharedInputs(),
                const SizedBox(height: 20),
                SizedBox(
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
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTemperatureInput() {
    final temp = double.tryParse(_tempController.text);
    final status = temp != null ? _getTempStatus(temp) : null;

    return Column(
      key: const ValueKey('temperature'),
      children: [
        TextFormField(
          controller: _tempController,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Temperature',
            suffixText: '\u00B0C',
            prefixIcon: Icon(
              Icons.thermostat,
              size: 20,
              color: status?.color ?? const Color(0xFF8B85A0),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE8D5F5)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE8D5F5)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: status?.color ?? const Color(0xFF9B72CF),
                width: 2,
              ),
            ),
            filled: true,
            fillColor: const Color(0xFFFAF8FC),
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

  Widget _buildMedicationInput() {
    return Column(
      key: const ValueKey('medication'),
      children: [
        TextFormField(
          controller: _medicationController,
          decoration: InputDecoration(
            labelText: 'Medication name',
            prefixIcon: const Icon(Icons.medication, size: 20),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE8D5F5)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE8D5F5)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFF9B72CF),
                width: 2,
              ),
            ),
            filled: true,
            fillColor: const Color(0xFFFAF8FC),
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
              borderSide: const BorderSide(color: Color(0xFFE8D5F5)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE8D5F5)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFF9B72CF),
                width: 2,
              ),
            ),
            filled: true,
            fillColor: const Color(0xFFFAF8FC),
          ),
        ),
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
              borderSide: const BorderSide(color: Color(0xFFE8D5F5)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE8D5F5)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFF9B72CF),
                width: 2,
              ),
            ),
            filled: true,
            fillColor: const Color(0xFFFAF8FC),
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
              borderSide: const BorderSide(color: Color(0xFFE8D5F5)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE8D5F5)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFF9B72CF),
                width: 2,
              ),
            ),
            filled: true,
            fillColor: const Color(0xFFFAF8FC),
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
        const Text(
          'Recent Logs',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF2D2640),
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
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2D2640),
                    ),
                  ),
                  Text(
                    AppDateUtils.formatTime(log.loggedAt),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF8B85A0),
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
                    const Icon(
                      Icons.sick_outlined,
                      size: 14,
                      color: Color(0xFF8B85A0),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        log.symptoms!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF8B85A0),
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
                    const Icon(
                      Icons.notes,
                      size: 14,
                      color: Color(0xFF8B85A0),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        log.notes!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF8B85A0),
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
