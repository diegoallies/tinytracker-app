import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/design_tokens.dart';
import '../../config/theme.dart';
import '../../models/care_pack_models.dart';
import '../../providers/baby_provider.dart';
import '../../providers/care_pack_provider.dart';
import '../../utils/care_pack_data.dart';
import '../../utils/extensions.dart';
import '../../utils/haptics.dart';
import '../../widgets/common/animated_card.dart';
import '../../widgets/common/app_dialogs.dart';
import '../../widgets/common/loading_skeleton.dart';

/// The always-available safety reference: red flags, the quick scales used
/// across the app, and the emergency-contact "fridge sheet".
class CareGuideScreen extends ConsumerStatefulWidget {
  const CareGuideScreen({super.key});

  @override
  ConsumerState<CareGuideScreen> createState() => _CareGuideScreenState();
}

class _CareGuideScreenState extends ConsumerState<CareGuideScreen> {
  bool _seeding = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Care Guide')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.md,
              AppSpacing.gutter, AppSpacing.xxl),
          children: [
            const _RedFlagsCard(
              index: 0,
              icon: Icons.emergency_rounded,
              title: 'Red flags - call immediately',
              intro: 'Don\'t wait for the weekly report. When in doubt, call '
                  '- better to call for nothing than to wait.',
              flags: CarePackData.redFlags,
            ),
            const SizedBox(height: AppSpacing.md),
            const _RedFlagsCard(
              index: 1,
              icon: Icons.sick_rounded,
              title: 'Tummy red flags',
              intro: 'Digestion problems worth a same-day call.',
              flags: CarePackData.tummyRedFlags,
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('Quick scales', style: context.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'The shared language used when logging reflux, nappies, and '
              'cramps.',
              style: context.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            const _ScaleCard(
              icon: Icons.water_drop_rounded,
              title: 'Reflux severity (1-5)',
              points: CarePackData.refluxSeverity,
            ),
            const SizedBox(height: AppSpacing.sm),
            const _ScaleCard(
              icon: Icons.baby_changing_station_rounded,
              title: 'Stool types (1-7)',
              points: CarePackData.stoolTypes,
            ),
            const SizedBox(height: AppSpacing.sm),
            const _ScaleCard(
              icon: Icons.air_rounded,
              title: 'Cramps & gas (0-3)',
              points: CarePackData.crampsGasScale,
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('Emergency contacts', style: context.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'The digital fridge sheet - keep it filled in so it’s there '
              'the day you need it.',
              style: context.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            _buildContactsSection(),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Emergency contacts
  // ---------------------------------------------------------------------

  Widget _buildContactsSection() {
    final baby = ref.watch(selectedBabyProvider);
    if (baby == null) {
      return AnimatedCard(
        index: 2,
        child: Text('Select a baby to set up the contact sheet.',
            style: context.textTheme.bodyMedium),
      );
    }

    final contactsAsync = ref.watch(emergencyContactsProvider);
    return contactsAsync.when(
      loading: () => const CardSkeleton(),
      error: (e, _) => e is SchemaNotReadyException
          ? const _SchemaPendingCard()
          : _ErrorCard(
              onRetry: () => ref.invalidate(emergencyContactsProvider),
            ),
      data: (contacts) {
        if (contacts.isEmpty) {
          return AnimatedCard(
            index: 2,
            child: Column(
              children: [
                const Icon(Icons.contact_phone_rounded,
                    size: 40, color: AppColors.primary),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'No contact sheet yet',
                  style: context.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Create the standard fridge-sheet rows (parents, '
                  'paediatrician, hospital, ambulance…) and fill them in.',
                  style: context.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.md),
                ElevatedButton.icon(
                  onPressed: _seeding ? null : () => _seedDefaults(baby.id),
                  icon: const Icon(Icons.playlist_add_rounded, size: 20),
                  label: Text(
                      _seeding ? 'Setting up…' : 'Set up the fridge sheet'),
                ),
              ],
            ),
          );
        }

        return AnimatedCard(
          index: 2,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            children: [
              for (final (i, contact) in contacts.indexed) ...[
                if (i > 0)
                  Divider(height: 1, indent: AppSpacing.md,
                      endIndent: AppSpacing.md),
                _ContactRow(
                  contact: contact,
                  onTap: () => _editContact(contact),
                  onCall: contact.phone == null
                      ? null
                      : () => _call(contact.phone!),
                  onLongPress: () => _deleteContact(contact),
                ),
              ],
              const Divider(height: 1),
              _AddContactRow(onTap: () => _addContact(baby.id)),
            ],
          ),
        );
      },
    );
  }

  Future<void> _seedDefaults(String babyId) async {
    Haptics.mediumTap();
    setState(() => _seeding = true);
    try {
      await EmergencyContactActions.seedDefaults(babyId);
      ref.invalidate(emergencyContactsProvider);
      if (mounted) context.showSuccessSnackBar('Fridge sheet created');
    } catch (_) {
      if (mounted) {
        context.showErrorSnackBar('Couldn’t create the sheet. Try again.');
      }
    } finally {
      if (mounted) setState(() => _seeding = false);
    }
  }

  Future<void> _call(String phone) async {
    Haptics.lightTap();
    final sanitized = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri(scheme: 'tel', path: sanitized);
    try {
      final ok = await launchUrl(uri);
      if (!ok && mounted) {
        context.showErrorSnackBar('Couldn’t start a call to $phone.');
      }
    } catch (_) {
      if (mounted) {
        context.showErrorSnackBar('Couldn’t start a call to $phone.');
      }
    }
  }

  Future<void> _deleteContact(EmergencyContact contact) async {
    Haptics.heavyTap();
    final confirmed = await showDeleteDialog(context, what: 'contact');
    if (!confirmed) return;
    try {
      await EmergencyContactActions.delete(contact.id);
      ref.invalidate(emergencyContactsProvider);
      if (mounted) context.showSuccessSnackBar('Contact deleted');
    } catch (_) {
      if (mounted) {
        context.showErrorSnackBar('Couldn’t delete the contact. Try again.');
      }
    }
  }

  Future<void> _editContact(EmergencyContact contact) async {
    Haptics.lightTap();
    final result = await _showContactSheet(
      title: contact.label,
      initialName: contact.name,
      initialPhone: contact.phone,
      initialNotes: contact.notes,
      showNotes: true,
    );
    if (result == null) return;
    try {
      await EmergencyContactActions.update(
        id: contact.id,
        name: result.name,
        phone: result.phone,
        notes: result.notes,
      );
      ref.invalidate(emergencyContactsProvider);
      if (mounted) context.showSuccessSnackBar('Contact updated');
    } catch (_) {
      if (mounted) {
        context.showErrorSnackBar('Couldn’t save the contact. Try again.');
      }
    }
  }

  Future<void> _addContact(String babyId) async {
    Haptics.lightTap();
    final result = await _showContactSheet(
      title: 'Add contact',
      showLabel: true,
    );
    if (result == null || (result.label ?? '').trim().isEmpty) return;
    try {
      await EmergencyContactActions.add(
        babyId: babyId,
        label: result.label!.trim(),
        name: result.name,
        phone: result.phone,
      );
      ref.invalidate(emergencyContactsProvider);
      if (mounted) context.showSuccessSnackBar('Contact added');
    } catch (_) {
      if (mounted) {
        context.showErrorSnackBar('Couldn’t add the contact. Try again.');
      }
    }
  }

  Future<_ContactSheetResult?> _showContactSheet({
    required String title,
    String? initialName,
    String? initialPhone,
    String? initialNotes,
    bool showLabel = false,
    bool showNotes = false,
  }) {
    return showModalBottomSheet<_ContactSheetResult>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _ContactEditSheet(
        title: title,
        initialName: initialName,
        initialPhone: initialPhone,
        initialNotes: initialNotes,
        showLabel: showLabel,
        showNotes: showNotes,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Red flag cards
// ---------------------------------------------------------------------------

class _RedFlagsCard extends StatelessWidget {
  final int index;
  final IconData icon;
  final String title;
  final String intro;
  final List<String> flags;

  const _RedFlagsCard({
    required this.index,
    required this.icon,
    required this.title,
    required this.intro,
    required this.flags,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedCard(
      index: index,
      color: AppColors.error.withValues(
          alpha: context.theme.brightness == Brightness.dark ? 0.14 : 0.06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 22, color: AppColors.error),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  title,
                  style: context.textTheme.titleMedium
                      ?.copyWith(color: AppColors.error),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(intro, style: context.textTheme.bodySmall),
          const SizedBox(height: AppSpacing.sm),
          for (final flag in flags)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(Icons.warning_amber_rounded,
                        size: 16, color: AppColors.error),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(flag, style: context.textTheme.bodyMedium),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quick scale cards
// ---------------------------------------------------------------------------

class _ScaleCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final List<CareScalePoint> points;

  const _ScaleCard({
    required this.icon,
    required this.title,
    required this.points,
  });

  @override
  State<_ScaleCard> createState() => _ScaleCardState();
}

class _ScaleCardState extends State<_ScaleCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AnimatedCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          InkWell(
            borderRadius: AppRadius.xlAll,
            onTap: () {
              Haptics.selectionClick();
              setState(() => _expanded = !_expanded);
            },
            child: Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              child: Row(
                children: [
                  Icon(widget.icon, size: 20, color: AppColors.primary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(widget.title,
                        style: context.textTheme.titleMedium),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: AppMotion.fast,
                    child: Icon(Icons.expand_more_rounded,
                        color: palette.muted),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: AppMotion.normal,
            curve: AppMotion.ease,
            alignment: Alignment.topCenter,
            child: !_expanded
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0,
                        AppSpacing.md, AppSpacing.md),
                    child: Column(
                      children: [
                        for (final point in widget.points)
                          Padding(
                            padding:
                                const EdgeInsets.only(bottom: AppSpacing.xs),
                            child: _ScaleRow(point: point),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ScaleRow extends StatelessWidget {
  final CareScalePoint point;

  const _ScaleRow({required this.point});

  @override
  Widget build(BuildContext context) {
    final accent = point.alert ? AppColors.error : AppColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: point.alert ? 0.1 : 0.05),
        borderRadius: AppRadius.mdAll,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Text(
              '${point.value}',
              style: context.textTheme.labelLarge?.copyWith(color: accent),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                point.label,
                style: context.textTheme.bodyMedium?.copyWith(
                  color: point.alert ? AppColors.error : null,
                  fontWeight: point.alert ? FontWeight.w600 : null,
                ),
              ),
            ),
          ),
          if (point.alert)
            const Padding(
              padding: EdgeInsets.only(top: 3),
              child: Icon(Icons.warning_amber_rounded,
                  size: 18, color: AppColors.error),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Contact rows + edit sheet
// ---------------------------------------------------------------------------

class _ContactRow extends StatelessWidget {
  final EmergencyContact contact;
  final VoidCallback onTap;
  final VoidCallback? onCall;
  final VoidCallback onLongPress;

  const _ContactRow({
    required this.contact,
    required this.onTap,
    required this.onCall,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final detail = [
      if (contact.name?.isNotEmpty ?? false) contact.name!,
      if (contact.phone?.isNotEmpty ?? false) contact.phone!,
    ].join(' · ');
    final notes = contact.notes;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contact.label,
                    style: context.textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail.isEmpty
                        ? (notes?.isNotEmpty ?? false
                            ? notes!
                            : 'Tap to fill in')
                        : detail,
                    style: detail.isEmpty &&
                            !(notes?.isNotEmpty ?? false)
                        ? context.textTheme.bodyMedium?.copyWith(
                            color: palette.muted,
                            fontStyle: FontStyle.italic,
                          )
                        : context.textTheme.bodyMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (detail.isNotEmpty && (notes?.isNotEmpty ?? false))
                    Text(
                      notes!,
                      style: context.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (onCall != null)
              IconButton(
                onPressed: onCall,
                icon: const Icon(Icons.call_rounded, size: 22),
                color: AppColors.success,
                constraints:
                    const BoxConstraints(minWidth: 44, minHeight: 44),
                tooltip: 'Call',
              ),
          ],
        ),
      ),
    );
  }
}

class _AddContactRow extends StatelessWidget {
  final VoidCallback onTap;

  const _AddContactRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(AppRadius.xl)),
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Row(
          children: [
            const Icon(Icons.add_circle_outline_rounded,
                size: 20, color: AppColors.primary),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Add contact',
              style: context.textTheme.bodyMedium?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactSheetResult {
  final String? label;
  final String? name;
  final String? phone;
  final String? notes;

  const _ContactSheetResult({this.label, this.name, this.phone, this.notes});
}

class _ContactEditSheet extends StatefulWidget {
  final String title;
  final String? initialName;
  final String? initialPhone;
  final String? initialNotes;
  final bool showLabel;
  final bool showNotes;

  const _ContactEditSheet({
    required this.title,
    this.initialName,
    this.initialPhone,
    this.initialNotes,
    required this.showLabel,
    required this.showNotes,
  });

  @override
  State<_ContactEditSheet> createState() => _ContactEditSheetState();
}

class _ContactEditSheetState extends State<_ContactEditSheet> {
  late final TextEditingController _labelCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _notesCtrl;

  @override
  void initState() {
    super.initState();
    _labelCtrl = TextEditingController();
    _nameCtrl = TextEditingController(text: widget.initialName ?? '');
    _phoneCtrl = TextEditingController(text: widget.initialPhone ?? '');
    _notesCtrl = TextEditingController(text: widget.initialNotes ?? '');
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _save() {
    Haptics.mediumTap();
    Navigator.of(context).pop(_ContactSheetResult(
      label: widget.showLabel ? _labelCtrl.text : null,
      name: _nameCtrl.text,
      phone: _phoneCtrl.text,
      notes: _notesCtrl.text,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: AppSpacing.sheet,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: context.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.md),
            if (widget.showLabel) ...[
              TextField(
                controller: _labelCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Label (e.g. After-hours clinic)',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            TextField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'Name'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(hintText: 'Phone number'),
            ),
            if (widget.showNotes) ...[
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _notesCtrl,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Notes (member number, address, dose…)',
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton(
              onPressed: _save,
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Status cards (contacts section only - the rest of the guide is static)
// ---------------------------------------------------------------------------

class _SchemaPendingCard extends StatelessWidget {
  const _SchemaPendingCard();

  @override
  Widget build(BuildContext context) {
    return AnimatedCard(
      index: 2,
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
            'The contact sheet needs a small database upgrade that hasn’t '
            'been applied yet. The safety guide above still works.',
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
      index: 2,
      child: Column(
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 40, color: AppColors.error),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Couldn’t load the contact sheet',
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
