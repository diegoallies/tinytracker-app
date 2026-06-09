import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../models/baby_medication.dart';
import '../../providers/baby_medication_provider.dart';
import '../../utils/extensions.dart';

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
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _dosageCtrl.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Add Medication'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
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
        ],
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
