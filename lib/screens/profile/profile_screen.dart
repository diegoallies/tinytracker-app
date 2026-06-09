import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import '../../config/theme.dart';
import '../../providers/profile_provider.dart';
import '../../services/auth_service.dart';
import '../../utils/date_utils.dart';
import '../../utils/extensions.dart';
import '../../widgets/common/app_dialogs.dart';
import '../../widgets/common/loading_skeleton.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _displayNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _bioController = TextEditingController();
  final _imagePicker = ImagePicker();

  bool _isUploadingAvatar = false;
  bool _isLoggingOut = false;
  bool _initialized = false;

  // Per-field inline editing state
  String? _editingField;
  String? _savingField;
  final Map<String, String> _snapshot = {};

  @override
  void dispose() {
    _displayNameController.dispose();
    _phoneController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  void _initializeFields(dynamic profile) {
    if (!_initialized && profile != null) {
      _displayNameController.text = profile.displayName ?? '';
      _phoneController.text = profile.phone ?? '';
      _bioController.text = profile.bio ?? '';
      _initialized = true;
    }
  }

  TextEditingController _controllerFor(String field) {
    switch (field) {
      case 'displayName':
        return _displayNameController;
      case 'phone':
        return _phoneController;
      case 'bio':
        return _bioController;
    }
    throw ArgumentError('Unknown field: $field');
  }

  void _startEdit(String field) {
    if (_savingField != null) return;
    setState(() {
      _editingField = field;
      _snapshot[field] = _controllerFor(field).text;
    });
  }

  void _cancelEdit() {
    final field = _editingField;
    if (field == null) return;
    _controllerFor(field).text = _snapshot[field] ?? '';
    setState(() {
      _editingField = null;
      _snapshot.remove(field);
    });
  }

  Future<void> _saveField(String field) async {
    final value = _controllerFor(field).text.trim();

    if (field == 'displayName' && value.isEmpty) {
      context.showErrorSnackBar('Display name cannot be empty');
      return;
    }

    setState(() => _savingField = field);

    try {
      await ProfileActions.updateProfile(
        displayName: field == 'displayName' ? value : null,
        phone: field == 'phone' ? value : null,
        bio: field == 'bio' ? value : null,
      );
      _controllerFor(field).text = value;
      ref.invalidate(profileProvider);

      if (mounted) {
        setState(() {
          _editingField = null;
          _savingField = null;
          _snapshot.remove(field);
        });
        context.showSuccessSnackBar('Saved');
      }
    } catch (e) {
      if (mounted) {
        // Restore prior value on failure
        _controllerFor(field).text = _snapshot[field] ?? '';
        setState(() {
          _savingField = null;
        });
        context.showErrorSnackBar(
          'Couldn’t save your changes. Check your connection and try again.',
        );
      }
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
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
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'Change Profile Photo',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: context.palette.text,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _PhotoSourceTile(
                icon: Icons.camera_alt_rounded,
                color: AppColors.pastelPurple,
                iconColor: AppColors.primary,
                label: 'Take Photo',
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              const SizedBox(height: 8),
              _PhotoSourceTile(
                icon: Icons.photo_library_rounded,
                color: AppColors.pastelBlue,
                iconColor: const Color(0xFF5b8cbf),
                label: 'Choose from Gallery',
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );

    if (source == null) return;

    final pickedFile = await _imagePicker.pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );

    if (pickedFile == null) return;

    setState(() => _isUploadingAvatar = true);

    try {
      final file = File(pickedFile.path);
      final url = await ProfileActions.uploadAvatar(file);

      if (url != null) {
        await ProfileActions.updateProfile(avatarUrl: url);
        ref.invalidate(profileProvider);
      }
      if (mounted) {
        context.showSuccessSnackBar('Profile photo updated');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar(
          'Couldn’t update your profile photo. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
    }
  }

  Future<void> _logout() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Sign Out',
      message: 'Are you sure you want to sign out?',
      confirmLabel: 'Sign Out',
      destructive: true,
      icon: Icons.logout_rounded,
    );

    if (!confirmed) return;

    setState(() => _isLoggingOut = true);

    try {
      await AuthService().signOut();
      if (mounted) {
        context.go('/login');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoggingOut = false);
        context.showErrorSnackBar(
          'Couldn’t sign out. Check your connection and try again.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        systemOverlayStyle: null,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: profileAsync.when(
        loading: () => const _ProfileSkeleton(),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded, size: 48, color: Colors.red.shade300),
                const SizedBox(height: 16),
                Text(
                  'Failed to load profile',
                  style: TextStyle(fontSize: 16, color: Colors.red.shade400),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => ref.invalidate(profileProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (profile) {
          if (profile == null) {
            return const Center(child: Text('Profile not found'));
          }

          _initializeFields(profile);

          return SingleChildScrollView(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _ProfileHero(
                  profile: profile,
                  isUploading: _isUploadingAvatar,
                  onTapAvatar: _isUploadingAvatar ? null : _pickAndUploadAvatar,
                ),

                Transform.translate(
                  offset: const Offset(0, -28),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        _StatPill(
                          icon: Icons.calendar_today_rounded,
                          label: 'Member since',
                          value: AppDateUtils.formatFull(profile.createdAt),
                        ),

                        const SizedBox(height: 20),

                        _SectionCard(
                          title: 'Personal Information',
                          child: Column(
                            children: [
                              _ProfileField(
                                fieldKey: 'displayName',
                                controller: _displayNameController,
                                label: 'Display Name',
                                hint: 'Set your name',
                                icon: Icons.person_outline_rounded,
                                isEditing: _editingField == 'displayName',
                                isSaving: _savingField == 'displayName',
                                canEdit: _editingField == null ||
                                    _editingField == 'displayName',
                                onEdit: () => _startEdit('displayName'),
                                onCancel: _cancelEdit,
                                onSave: () => _saveField('displayName'),
                              ),
                              const _FieldDivider(),
                              _ProfileField(
                                fieldKey: 'email',
                                label: 'Email',
                                hint: '',
                                icon: Icons.email_outlined,
                                staticValue: profile.email ?? '',
                                isEditing: false,
                                isSaving: false,
                                canEdit: false,
                                readOnly: true,
                                onEdit: () {},
                                onCancel: () {},
                                onSave: () {},
                              ),
                              const _FieldDivider(),
                              _ProfileField(
                                fieldKey: 'phone',
                                controller: _phoneController,
                                label: 'Phone',
                                hint: 'Not set',
                                icon: Icons.phone_outlined,
                                keyboardType: TextInputType.phone,
                                isEditing: _editingField == 'phone',
                                isSaving: _savingField == 'phone',
                                canEdit:
                                    _editingField == null || _editingField == 'phone',
                                onEdit: () => _startEdit('phone'),
                                onCancel: _cancelEdit,
                                onSave: () => _saveField('phone'),
                              ),
                              const _FieldDivider(),
                              _ProfileField(
                                fieldKey: 'bio',
                                controller: _bioController,
                                label: 'Bio',
                                hint: 'Add a short note about you',
                                icon: Icons.info_outline_rounded,
                                maxLines: 3,
                                isEditing: _editingField == 'bio',
                                isSaving: _savingField == 'bio',
                                canEdit:
                                    _editingField == null || _editingField == 'bio',
                                onEdit: () => _startEdit('bio'),
                                onCancel: _cancelEdit,
                                onSave: () => _saveField('bio'),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        _AccountActionsCard(
                          isLoggingOut: _isLoggingOut,
                          onLogout: _logout,
                        ),

                        const SizedBox(height: 32),

                        Text(
                          'TinyTracker',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: context.palette.muted.withValues(alpha: 0.6),
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Hero header with gradient + avatar
// ──────────────────────────────────────────────────────────────────────

class _ProfileHero extends StatelessWidget {
  final dynamic profile;
  final bool isUploading;
  final VoidCallback? onTapAvatar;

  const _ProfileHero({
    required this.profile,
    required this.isUploading,
    required this.onTapAvatar,
  });

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        top: topPadding + kToolbarHeight + 8,
        bottom: 56,
        left: 24,
        right: 24,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary,
            AppColors.primaryLight,
          ],
        ),
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(40),
        ),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: onTapAvatar,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 124,
                  height: 124,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.25),
                  ),
                ),
                Container(
                  width: 112,
                  height: 112,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(4),
                  child: ClipOval(
                    child: profile.avatarUrl != null &&
                            (profile.avatarUrl as String).isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: profile.avatarUrl as String,
                            fit: BoxFit.cover,
                            placeholder: (_, _) => Container(
                              color: AppColors.pastelPurple,
                            ),
                            errorWidget: (_, _, _) =>
                                _initials(profile),
                          )
                        : _initials(profile),
                  ),
                ),
                if (isUploading)
                  Container(
                    width: 112,
                    height: 112,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black38,
                    ),
                    alignment: Alignment.center,
                    child: const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.camera_alt_rounded,
                      size: 18,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            (profile.displayName?.isNotEmpty == true)
                ? profile.displayName!
                : 'Set your name',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            profile.email ?? '',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }

  Widget _initials(dynamic profile) {
    final letter = (profile.displayName?.isNotEmpty == true
            ? profile.displayName![0]
            : (profile.email?.isNotEmpty == true ? profile.email![0] : 'U'))
        .toString()
        .toUpperCase();
    return Container(
      color: AppColors.pastelPurple,
      alignment: Alignment.center,
      child: Text(
        letter,
        style: const TextStyle(
          fontSize: 44,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Floating stat pill (member since)
// ──────────────────────────────────────────────────────────────────────

class _StatPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatPill({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.pastelGreen,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.calendar_today_rounded,
              size: 16,
              color: Color(0xFF5bbf8c),
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: context.palette.muted,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.palette.text,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Section card with title
// ──────────────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: context.palette.text,
                letterSpacing: -0.2,
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Per-field inline editable row with pencil/save/cancel
// ──────────────────────────────────────────────────────────────────────

class _ProfileField extends StatelessWidget {
  final String fieldKey;
  final TextEditingController? controller;
  final String label;
  final String hint;
  final IconData icon;
  final String? staticValue;
  final TextInputType? keyboardType;
  final int maxLines;
  final bool isEditing;
  final bool isSaving;
  final bool canEdit;
  final bool readOnly;
  final VoidCallback onEdit;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  const _ProfileField({
    required this.fieldKey,
    this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.staticValue,
    this.keyboardType,
    this.maxLines = 1,
    required this.isEditing,
    required this.isSaving,
    required this.canEdit,
    this.readOnly = false,
    required this.onEdit,
    required this.onCancel,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final value = staticValue ?? controller?.text ?? '';
    final hasValue = value.trim().isNotEmpty;
    final dimmed = !canEdit && !readOnly;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 22),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.pastelPurple.withValues(
                  alpha: dimmed ? 0.2 : 0.5,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 18,
                color: AppColors.primary.withValues(
                  alpha: dimmed ? 0.4 : 1.0,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.palette.muted.withValues(
                      alpha: dimmed ? 0.5 : 1.0,
                    ),
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 4),
                if (isEditing && controller != null)
                  TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: keyboardType,
                    maxLines: maxLines,
                    enabled: !isSaving,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: context.palette.text,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.only(bottom: 4),
                      hintText: hint,
                      hintStyle: TextStyle(
                        fontSize: 14,
                        color: context.palette.muted.withValues(alpha: 0.5),
                        fontWeight: FontWeight.w400,
                      ),
                      border: const UnderlineInputBorder(
                        borderSide: BorderSide(color: AppColors.primary),
                      ),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: AppColors.primary.withValues(alpha: 0.5),
                        ),
                      ),
                      focusedBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: AppColors.primary,
                          width: 1.5,
                        ),
                      ),
                      filled: false,
                    ),
                    onSubmitted: maxLines == 1 ? (_) => onSave() : null,
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      hasValue ? value : hint,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: hasValue ? FontWeight.w500 : FontWeight.w400,
                        color: hasValue
                            ? (dimmed
                                ? context.palette.text.withValues(alpha: 0.5)
                                : context.palette.text)
                            : context.palette.muted.withValues(
                                alpha: dimmed ? 0.5 : 0.7,
                              ),
                      ),
                      maxLines: maxLines,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
          if (!readOnly)
            Padding(
              padding: const EdgeInsets.only(top: 18, left: 4),
              child: _EditActions(
                isEditing: isEditing,
                isSaving: isSaving,
                enabled: canEdit,
                onEdit: onEdit,
                onCancel: onCancel,
                onSave: onSave,
              ),
            ),
        ],
      ),
    );
  }
}

class _EditActions extends StatelessWidget {
  final bool isEditing;
  final bool isSaving;
  final bool enabled;
  final VoidCallback onEdit;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  const _EditActions({
    required this.isEditing,
    required this.isSaving,
    required this.enabled,
    required this.onEdit,
    required this.onCancel,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    if (isSaving) {
      return const SizedBox(
        width: 36,
        height: 36,
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
      );
    }

    if (isEditing) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _IconButton(
            icon: Icons.close_rounded,
            color: context.palette.muted,
            background: Colors.grey.shade100,
            onTap: onCancel,
            tooltip: 'Cancel',
          ),
          const SizedBox(width: 6),
          _IconButton(
            icon: Icons.check_rounded,
            color: Colors.white,
            background: AppColors.primary,
            onTap: onSave,
            tooltip: 'Save',
          ),
        ],
      );
    }

    return _IconButton(
      icon: Icons.edit_rounded,
      color: enabled
          ? AppColors.primary
          : context.palette.muted.withValues(alpha: 0.4),
      background: enabled
          ? AppColors.pastelPurple.withValues(alpha: 0.5)
          : Colors.grey.shade100,
      onTap: enabled ? onEdit : null,
      tooltip: 'Edit',
    );
  }
}

class _IconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color background;
  final VoidCallback? onTap;
  final String tooltip;

  const _IconButton({
    required this.icon,
    required this.color,
    required this.background,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
        ),
      ),
    );
  }
}

class _FieldDivider extends StatelessWidget {
  const _FieldDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 60, right: 20),
      child: Container(
        height: 1,
        color: Colors.grey.shade100,
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Account actions card (sign out)
// ──────────────────────────────────────────────────────────────────────

class _AccountActionsCard extends StatelessWidget {
  final bool isLoggingOut;
  final VoidCallback onLogout;

  const _AccountActionsCard({
    required this.isLoggingOut,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: isLoggingOut ? null : onLogout,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.logout_rounded,
                    size: 20,
                    color: Colors.red.shade400,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sign Out',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.red.shade400,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'You\'ll need to log in again',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.palette.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isLoggingOut)
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.red.shade400,
                    ),
                  )
                else
                  Icon(
                    Icons.chevron_right_rounded,
                    color: context.palette.muted.withValues(alpha: 0.6),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Bottom sheet photo source tile
// ──────────────────────────────────────────────────────────────────────

class _PhotoSourceTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;

  const _PhotoSourceTile({
    required this.icon,
    required this.color,
    required this.iconColor,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.palette.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 14),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: context.palette.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
// Skeleton loader
// ──────────────────────────────────────────────────────────────────────

class _ProfileSkeleton extends StatelessWidget {
  const _ProfileSkeleton();

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return SingleChildScrollView(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Container(
            height: topPadding + 280,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primary, AppColors.primaryLight],
              ),
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(40),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                LoadingSkeleton(
                  width: double.infinity,
                  height: 320,
                  borderRadius: 24,
                ),
                SizedBox(height: 16),
                LoadingSkeleton(
                  width: double.infinity,
                  height: 76,
                  borderRadius: 24,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
