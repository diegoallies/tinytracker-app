import 'dart:io';
import 'dart:math';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../../config/theme.dart';
import '../../providers/baby_provider.dart';
import '../../models/baby_share.dart';
import '../../services/supabase_service.dart';
import '../../utils/date_utils.dart';
import '../../utils/extensions.dart';
import '../../utils/role_labels.dart';
import '../../widgets/common/animated_card.dart';
import '../../widgets/common/app_dialogs.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/loading_skeleton.dart';

class BabyScreen extends ConsumerStatefulWidget {
  const BabyScreen({super.key});

  @override
  ConsumerState<BabyScreen> createState() => _BabyScreenState();
}

class _BabyScreenState extends ConsumerState<BabyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _imagePicker = ImagePicker();
  DateTime? _selectedDob;
  String? _selectedGender;
  bool _isEditing = false;
  bool _isSaving = false;
  bool _isUploadingPhoto = false;
  bool _isLoadingShares = false;
  List<BabyShare> _shares = [];

  static const _genderOptions = ['male', 'female', 'other'];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDob ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: AppColors.primary,
            onPrimary: Colors.white,
            surface: context.palette.card,
            onSurface: context.palette.text,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _selectedDob = picked);
    }
  }

  Future<void> _createBaby() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDob == null) {
      context.showErrorSnackBar('Please select a date of birth');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final notifier = ref.read(babyProvider.notifier);
      await notifier.createBaby(
        name: _nameController.text.trim(),
        dateOfBirth: _selectedDob!,
        gender: _selectedGender,
      );

      if (mounted) {
        _nameController.clear();
        setState(() {
          _selectedDob = null;
          _selectedGender = null;
        });
        context.showSuccessSnackBar('Baby profile created!');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar(
          'Couldn’t create the baby profile. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _updateBaby(String babyId) async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDob == null) return;

    setState(() => _isSaving = true);

    try {
      final notifier = ref.read(babyProvider.notifier);
      await notifier.updateBaby(
        babyId: babyId,
        name: _nameController.text.trim(),
        dateOfBirth: _selectedDob!,
        gender: _selectedGender,
      );

      if (mounted) {
        setState(() => _isEditing = false);
        context.showSuccessSnackBar('Baby profile updated');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar(
          'Couldn’t update the baby profile. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _pickAndUploadBabyPhoto(String babyId) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: context.palette.card,
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
                    color: context.palette.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'Change Baby Photo',
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

    setState(() => _isUploadingPhoto = true);

    try {
      final url = await BabyActions.uploadPhoto(File(pickedFile.path));
      if (url != null) {
        await ref.read(babyProvider.notifier).updateBaby(
              babyId: babyId,
              photoUrl: url,
            );
      }
      if (mounted) {
        context.showSuccessSnackBar('Baby photo updated');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar(
          'Couldn’t upload the photo. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  Future<void> _loadShares(String babyId) async {
    setState(() => _isLoadingShares = true);
    try {
      final notifier = ref.read(babyProvider.notifier);
      final shares = await notifier.getShares(babyId);
      if (mounted) {
        setState(() => _shares = shares);
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar(
          'Couldn’t load shared access. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingShares = false);
    }
  }

  Future<void> _showChangeRoleSheet(BabyShare share, String babyId) async {
    if (share.isOwner) return;
    String selectedRole = share.role;

    final newRole = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                16,
                24,
                MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: context.palette.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Change Role',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: context.palette.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    share.userName ?? share.userEmail ?? 'This user',
                    style: TextStyle(fontSize: 14, color: context.palette.muted),
                  ),
                  const SizedBox(height: 20),
                  _RoleOption(
                    label: 'Nanny',
                    description: 'Can log feedings, diapers, sleep (no meds)',
                    icon: Icons.child_care_rounded,
                    color: AppColors.pastelPink,
                    iconColor: const Color(0xFFbf5b8c),
                    isSelected: selectedRole == 'logger',
                    onTap: () => setSheetState(() => selectedRole = 'logger'),
                  ),
                  const SizedBox(height: 8),
                  _RoleOption(
                    label: 'Family',
                    description: 'Can add entries and give medication',
                    icon: Icons.family_restroom_rounded,
                    color: AppColors.pastelBlue,
                    iconColor: const Color(0xFF5b8cbf),
                    isSelected: selectedRole == 'parent',
                    onTap: () => setSheetState(() => selectedRole = 'parent'),
                  ),
                  const SizedBox(height: 8),
                  _RoleOption(
                    label: 'Viewer',
                    description: 'Can only view entries',
                    icon: Icons.visibility_rounded,
                    color: AppColors.pastelGreen,
                    iconColor: const Color(0xFF5bbf8c),
                    isSelected: selectedRole == 'viewer',
                    onTap: () => setSheetState(() => selectedRole = 'viewer'),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: selectedRole == share.role
                          ? null
                          : () => Navigator.pop(context, selectedRole),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Save Role',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (newRole == null || newRole == share.role) return;

    try {
      await ref.read(babyProvider.notifier).updateShareRole(share.id, newRole);
      await _loadShares(babyId);
      if (mounted) {
        context.showSuccessSnackBar('Role updated');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar(
          'Couldn’t update the role. Check your connection and try again.',
        );
      }
    }
  }

  Future<void> _removeShare(String shareId, String babyId) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Remove Access',
      message: 'Are you sure you want to remove this person\'s access?',
      confirmLabel: 'Remove',
      destructive: true,
      icon: Icons.person_remove_rounded,
    );

    if (!confirmed) return;

    try {
      final notifier = ref.read(babyProvider.notifier);
      await notifier.removeShare(shareId);
      await _loadShares(babyId);
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar(
          'Couldn’t remove access. Check your connection and try again.',
        );
      }
    }
  }

  Future<void> _showCreateInviteSheet(String babyId) async {
    String selectedRole = 'logger';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                16,
                24,
                MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: context.palette.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Invite Someone',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: context.palette.text,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create an invite link to share access to your baby\'s profile.',
                    style: TextStyle(fontSize: 14, color: context.palette.muted),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Select Role',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.palette.text,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _RoleOption(
                    label: 'Nanny',
                    description: 'Can log feedings, diapers, sleep (no meds)',
                    icon: Icons.child_care_rounded,
                    color: AppColors.pastelPink,
                    iconColor: const Color(0xFFbf5b8c),
                    isSelected: selectedRole == 'logger',
                    onTap: () => setSheetState(() => selectedRole = 'logger'),
                  ),
                  const SizedBox(height: 8),
                  _RoleOption(
                    label: 'Family',
                    description: 'Can add entries and give medication',
                    icon: Icons.family_restroom_rounded,
                    color: AppColors.pastelBlue,
                    iconColor: const Color(0xFF5b8cbf),
                    isSelected: selectedRole == 'parent',
                    onTap: () => setSheetState(() => selectedRole = 'parent'),
                  ),
                  const SizedBox(height: 8),
                  _RoleOption(
                    label: 'Viewer',
                    description: 'Can only view entries',
                    icon: Icons.visibility_rounded,
                    color: AppColors.pastelGreen,
                    iconColor: const Color(0xFF5bbf8c),
                    isSelected: selectedRole == 'viewer',
                    onTap: () => setSheetState(() => selectedRole = 'viewer'),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () async {
                        await _createInvite(babyId, selectedRole);
                        if (context.mounted) Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Create Invite Link',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _createInvite(String babyId, String role) async {
    try {
      final userId = SupabaseService.client.auth.currentUser?.id;
      if (userId == null) return;

      final now = DateTime.now();
      final token = now.millisecondsSinceEpoch.toRadixString(36) +
          _generateRandomChars(8);
      final expiresAt = now.add(const Duration(days: 7));

      await SupabaseService.client.from('baby_invites').insert({
        'baby_id': babyId,
        'invited_by': userId,
        'token': token,
        'role': role,
        'expires_at': expiresAt.toUtc().toIso8601String(),
      });

      // Clickable https link (Edge Function bounces into the app); the raw
      // scheme still works for direct paste.
      final inviteLink =
          'https://ggbjcjmksxxkbjaxxogv.supabase.co/functions/v1/invite?t=$token';
      final baby = ref.read(selectedBabyProvider);
      final babyName = baby?.name ?? 'our baby';

      // The invite EXISTS from here on - clipboard, then best-effort share.
      await Clipboard.setData(ClipboardData(text: inviteLink));
      if (mounted) {
        context.showSuccessSnackBar('Invite created - link copied to clipboard');
      }

      // The share sheet is a bonus: it can throw on some iOS versions or
      // when dismissed - that must never read as "invite failed".
      try {
        await SharePlus.instance.share(ShareParams(
          text: 'You\'re invited to help track $babyName on TinyTrack! 🍼\n\n'
              'Open this link on your phone (or paste it in the app under '
              'More > Invites):\n$inviteLink\n\n'
              'The link expires in 7 days.',
        ));
      } catch (e) {
        debugPrint('share sheet failed (link already on clipboard): $e');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar(
          'Couldn\'t create the invite. Check your connection and try again.',
        );
      }
    }
  }

  String _generateRandomChars(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < length; i++) {
      buffer.write(chars[random.nextInt(chars.length)]);
    }
    return buffer.toString();
  }

  IconData _roleIcon(String role) {
    switch (role) {
      case 'owner':
        return Icons.shield_rounded;
      case 'logger':
        return Icons.edit_rounded;
      case 'viewer':
        return Icons.visibility_rounded;
      default:
        return Icons.person_rounded;
    }
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'owner':
        return AppColors.pastelPurple;
      case 'logger':
        return AppColors.pastelBlue;
      case 'viewer':
        return AppColors.pastelGreen;
      default:
        return context.palette.surface;
    }
  }

  Color _roleIconColor(String role) {
    switch (role) {
      case 'owner':
        return AppColors.primary;
      case 'logger':
        return const Color(0xFF5b8cbf);
      case 'viewer':
        return const Color(0xFF5bbf8c);
      default:
        return context.palette.muted;
    }
  }

  String _genderEmoji(String? gender) {
    switch (gender) {
      case 'male':
        return 'Boy';
      case 'female':
        return 'Girl';
      case 'other':
        return 'Other';
      default:
        return 'Not set';
    }
  }

  @override
  Widget build(BuildContext context) {
    final babyState = ref.watch(babyProvider);
    final baby = babyState.selectedBaby;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Baby'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (baby != null)
            IconButton(
              icon: Icon(_isEditing ? Icons.close_rounded : Icons.edit_rounded),
              onPressed: () {
                if (_isEditing) {
                  setState(() => _isEditing = false);
                } else {
                  _nameController.text = baby.name;
                  _selectedDob = baby.dateOfBirth;
                  _selectedGender = baby.gender;
                  setState(() => _isEditing = true);
                }
              },
            ),
        ],
      ),
      body: SafeArea(
        child: babyState.loading
            ? const _BabySkeleton()
            : baby == null
                ? _buildCreateForm()
                : _isEditing
                    ? _buildEditForm(baby)
                    : _buildBabyProfile(baby, babyState.isOwner),
      ),
    );
  }

  Widget _buildCreateForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            const EmptyState(
              icon: Icons.child_care_rounded,
              title: 'Add Your Baby',
              description: 'Create a profile for your little one to start tracking.',
            ),
            const SizedBox(height: 24),
            AnimatedCard(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Baby Details',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: context.palette.text,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _nameController,
                      style: TextStyle(fontSize: 15, color: context.palette.text),
                      decoration: _inputDecoration('Baby\'s Name', Icons.child_care_rounded),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Please enter a name' : null,
                    ),
                    const SizedBox(height: 14),
                    GestureDetector(
                      onTap: _selectDate,
                      child: AbsorbPointer(
                        child: TextFormField(
                          style: TextStyle(fontSize: 15, color: context.palette.text),
                          decoration: _inputDecoration(
                            'Date of Birth',
                            Icons.cake_rounded,
                          ).copyWith(
                            hintText: _selectedDob != null
                                ? AppDateUtils.formatDate(_selectedDob!)
                                : 'Tap to select',
                            hintStyle: TextStyle(
                              color: _selectedDob != null ? context.palette.text : context.palette.muted,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildGenderSelector(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _createBaby,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
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
                        'Create Baby Profile',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditForm(dynamic baby) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            Center(
              child: _EditableBabyAvatar(
                babyName: baby.name,
                photoUrl: baby.photoUrl,
                isUploading: _isUploadingPhoto,
                onTap: _isUploadingPhoto
                    ? null
                    : () => _pickAndUploadBabyPhoto(baby.id),
              ),
            ),
            const SizedBox(height: 20),
            AnimatedCard(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Edit Baby Details',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: context.palette.text,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _nameController,
                      style: TextStyle(fontSize: 15, color: context.palette.text),
                      decoration: _inputDecoration('Baby\'s Name', Icons.child_care_rounded),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Please enter a name' : null,
                    ),
                    const SizedBox(height: 14),
                    GestureDetector(
                      onTap: _selectDate,
                      child: AbsorbPointer(
                        child: TextFormField(
                          style: TextStyle(fontSize: 15, color: context.palette.text),
                          decoration: _inputDecoration(
                            'Date of Birth',
                            Icons.cake_rounded,
                          ).copyWith(
                            hintText: _selectedDob != null
                                ? AppDateUtils.formatDate(_selectedDob!)
                                : 'Tap to select',
                            hintStyle: TextStyle(
                              color: _selectedDob != null ? context.palette.text : context.palette.muted,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildGenderSelector(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isSaving ? null : () => _updateBaby(baby.id),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
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
                        'Save Changes',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBabyProfile(dynamic baby, bool isOwner) {
    // Load shares on first build for owners
    if (_shares.isEmpty && !_isLoadingShares && isOwner) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadShares(baby.id);
      });
    }

    final age = _calculateAge(baby.dateOfBirth);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Baby profile card
          AnimatedCard(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  _EditableBabyAvatar(
                    babyName: baby.name,
                    photoUrl: baby.photoUrl,
                    isUploading: _isUploadingPhoto,
                    onTap: _isUploadingPhoto
                        ? null
                        : () => _pickAndUploadBabyPhoto(baby.id),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    baby.name,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: context.palette.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    age,
                    style: TextStyle(fontSize: 16, color: context.palette.muted),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _InfoChip(
                        icon: Icons.cake_rounded,
                        label: AppDateUtils.formatDate(baby.dateOfBirth),
                        color: AppColors.pastelPink,
                      ),
                      const SizedBox(width: 10),
                      _InfoChip(
                        icon: Icons.person_rounded,
                        label: _genderEmoji(baby.gender),
                        color: AppColors.pastelBlue,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Sharing section (owners only)
          if (isOwner) ...[
            const SizedBox(height: 16),
            AnimatedCard(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Sharing',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: context.palette.text,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => _showCreateInviteSheet(baby.id),
                          icon: const Icon(Icons.person_add_rounded, size: 18),
                          label: const Text('Invite'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_isLoadingShares)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: AppColors.primary,
                          ),
                        ),
                      )
                    else if (_shares.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(
                                Icons.people_outline_rounded,
                                size: 40,
                                color: context.palette.muted,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'No one else has access yet',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: context.palette.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ...List.generate(_shares.length, (index) {
                        final share = _shares[index];
                        return Padding(
                          padding: EdgeInsets.only(
                            top: index == 0 ? 0 : 8,
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: context.palette.surface,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: _roleColor(share.role),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    _roleIcon(share.role),
                                    size: 18,
                                    color: _roleIconColor(share.role),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        share.userName ?? 'Unknown',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: context.palette.text,
                                        ),
                                      ),
                                      Text(
                                        share.userEmail ?? roleDisplayName(share.role),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: context.palette.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                GestureDetector(
                                  onTap: share.isOwner
                                      ? null
                                      : () => _showChangeRoleSheet(share, baby.id),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _roleColor(share.role),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          roleDisplayName(share.role),
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            color: _roleIconColor(share.role),
                                          ),
                                        ),
                                        if (!share.isOwner) ...[
                                          const SizedBox(width: 4),
                                          Icon(
                                            Icons.unfold_more_rounded,
                                            size: 12,
                                            color: _roleIconColor(share.role),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                                if (!share.isOwner) ...[
                                  const SizedBox(width: 4),
                                  IconButton(
                                    icon: Icon(
                                      Icons.close_rounded,
                                      size: 18,
                                      color: Colors.red.shade300,
                                    ),
                                    onPressed: () =>
                                        _removeShare(share.id, baby.id),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 32,
                                      minHeight: 32,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildGenderSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Gender',
          style: TextStyle(
            fontSize: 13,
            color: context.palette.muted,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: _genderOptions.map((gender) {
            final isSelected = _selectedGender == gender;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  right: gender != _genderOptions.last ? 8 : 0,
                ),
                child: GestureDetector(
                  onTap: () => setState(() => _selectedGender = gender),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.primary : context.palette.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? AppColors.primary : context.palette.border,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        gender.capitalize,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: isSelected ? Colors.white : context.palette.text,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: context.palette.muted, fontSize: 14),
      prefixIcon: Icon(icon, color: context.palette.muted, size: 20),
      filled: true,
      fillColor: context.palette.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.red.shade300),
      ),
    );
  }

  String _calculateAge(DateTime dob) {
    final now = DateTime.now();
    final diff = now.difference(dob);
    final months = (diff.inDays / 30.44).floor();
    final years = (months / 12).floor();
    final remainingMonths = months % 12;

    if (years > 0) {
      return '$years year${years > 1 ? 's' : ''}, $remainingMonths month${remainingMonths != 1 ? 's' : ''} old';
    } else if (months > 0) {
      return '$months month${months > 1 ? 's' : ''} old';
    } else {
      return '${diff.inDays} day${diff.inDays != 1 ? 's' : ''} old';
    }
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Chip background stays pastel (light) in both modes, so content
          // must be a fixed dark color for legibility.
          Icon(icon, size: 16, color: AppColors.text),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.text,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleOption extends StatelessWidget {
  final String label;
  final String description;
  final IconData icon;
  final Color color;
  final Color iconColor;
  final bool isSelected;
  final VoidCallback onTap;

  const _RoleOption({
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
    required this.iconColor,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? color : context.palette.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? iconColor : context.palette.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: iconColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      // Selected tile keeps its pastel (light) background, so
                      // text must stay dark there in both modes.
                      color: isSelected ? AppColors.text : context.palette.text,
                    ),
                  ),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12,
                      color: isSelected ? AppColors.muted : context.palette.muted,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle_rounded, color: iconColor, size: 22),
          ],
        ),
      ),
    );
  }
}

class _EditableBabyAvatar extends StatelessWidget {
  final String babyName;
  final String? photoUrl;
  final bool isUploading;
  final VoidCallback? onTap;

  const _EditableBabyAvatar({
    required this.babyName,
    required this.photoUrl,
    required this.isUploading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.pastelPurple,
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.3),
                width: 2,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: hasPhoto
                ? CachedNetworkImage(
                    imageUrl: photoUrl!,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => _fallback(),
                    placeholder: (_, _) => _fallback(),
                  )
                : _fallback(),
          ),
          if (isUploading)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.35),
                ),
                child: const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary,
                border: Border.all(color: context.palette.card, width: 2),
              ),
              child: const Icon(
                Icons.camera_alt_rounded,
                size: 14,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallback() {
    return Center(
      child: Text(
        babyName.isNotEmpty ? babyName[0].toUpperCase() : 'B',
        style: const TextStyle(
          fontSize: 36,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.palette.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.palette.border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 22),
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
            const Spacer(),
            Icon(Icons.chevron_right_rounded, color: context.palette.muted),
          ],
        ),
      ),
    );
  }
}

class _BabySkeleton extends StatelessWidget {
  const _BabySkeleton();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: const [
          LoadingSkeleton(width: double.infinity, height: 260, borderRadius: 16),
          SizedBox(height: 16),
          LoadingSkeleton(width: double.infinity, height: 200, borderRadius: 16),
        ],
      ),
    );
  }
}
