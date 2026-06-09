import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/theme.dart';
import '../../models/baby_medication.dart';
import '../../providers/baby_medication_provider.dart';
import '../../utils/extensions.dart';
import '../../utils/haptics.dart';

/// Dialog for adding a baby's daily/recurring medication.
/// Returns the created [BabyMedication] via Navigator.pop on success.
class AddMedicationDialog extends StatefulWidget {
  final String babyId;
  const AddMedicationDialog({super.key, required this.babyId});

  @override
  State<AddMedicationDialog> createState() => _AddMedicationDialogState();
}

class _AddMedicationDialogState extends State<AddMedicationDialog> {
  final _nameCtrl = TextEditingController();
  final _dosageCtrl = TextEditingController();
  final _minHoursCtrl = TextEditingController();
  final _instructionsCtrl = TextEditingController();
  bool _saving = false;

  /// 1/2/3 for scheduled meds, null when unscheduled or as-needed.
  int? _frequencyPerDay;
  bool _asNeeded = false;

  static const _scheduleOptions = [
    ('Once a day', 1, false),
    ('2x', 2, false),
    ('3x', 3, false),
    ('As needed', null, true),
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _dosageCtrl.dispose();
    _minHoursCtrl.dispose();
    _instructionsCtrl.dispose();
    super.dispose();
  }

  void _selectSchedule(int? frequency, bool asNeeded) {
    Haptics.selectionClick();
    setState(() {
      final alreadySelected =
          _frequencyPerDay == frequency && _asNeeded == asNeeded;
      if (alreadySelected) {
        // Tap again to clear — schedule stays optional.
        _frequencyPerDay = null;
        _asNeeded = false;
        return;
      }
      _frequencyPerDay = frequency;
      _asNeeded = asNeeded;
      if (asNeeded && _minHoursCtrl.text.trim().isEmpty) {
        _minHoursCtrl.text = '4';
      }
    });
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    try {
      final created = await BabyMedicationActions.add(
        babyId: widget.babyId,
        name: name,
        defaultDosage: _dosageCtrl.text.trim(),
        frequencyPerDay: _frequencyPerDay,
        asNeeded: _asNeeded,
        minIntervalHours: double.tryParse(_minHoursCtrl.text.trim()),
        instructions: _instructionsCtrl.text.trim(),
      );
      if (mounted) Navigator.pop(context, created);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        context.showErrorSnackBar(
          'Couldn’t add the medication. Check your connection and try again.',
          onRetry: _save,
        );
      }
    }
  }

  Widget _scheduleChip(String label, int? frequency, bool asNeeded) {
    final selected = (frequency != null || asNeeded) &&
        _frequencyPerDay == frequency &&
        _asNeeded == asNeeded;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => _selectSchedule(frequency, asNeeded),
      selectedColor: AppColors.primary.withValues(alpha: 0.18),
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: selected ? AppColors.primary : context.palette.muted,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Add Medication'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Medication name',
                hintText: 'e.g. Panado',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _dosageCtrl,
              decoration: const InputDecoration(
                labelText: 'Default dosage (optional)',
                hintText: 'e.g. 2.5 ml',
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Schedule (optional)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.palette.muted,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (label, frequency, asNeeded) in _scheduleOptions)
                  _scheduleChip(label, frequency, asNeeded),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _minHoursCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                    RegExp(r'^\d{0,2}\.?\d{0,1}')),
              ],
              decoration: const InputDecoration(
                labelText: 'Minimum hours between doses (optional)',
                hintText: 'e.g. 4',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _instructionsCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Instructions (optional)',
                hintText: 'e.g. Only when needed — max 4 doses in 24h',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Add'),
        ),
      ],
    );
  }
}
