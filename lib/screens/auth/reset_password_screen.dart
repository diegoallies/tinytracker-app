import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/design_tokens.dart';
import '../../config/theme.dart';
import '../../services/supabase_service.dart';
import '../../utils/extensions.dart';
import '../../utils/haptics.dart';

/// Shown when the user arrives from a password-recovery email deep link
/// (tinytracker://reset-password). The recovery session is already active -
/// they just choose a new password.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscure = true;
  bool _saving = false;

  Future<void> _save() async {
    final password = _passwordController.text;
    if (password.length < 6) {
      context.showErrorSnackBar('Password must be at least 6 characters');
      return;
    }
    if (password != _confirmController.text) {
      context.showErrorSnackBar('Passwords don\'t match');
      return;
    }

    Haptics.lightTap();
    setState(() => _saving = true);
    try {
      await SupabaseService.client.auth
          .updateUser(UserAttributes(password: password));
      Haptics.mediumTap();
      if (!mounted) return;
      context.showSuccessSnackBar('Password updated - welcome back!');
      context.go('/dashboard');
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar(
          'Couldn\'t update the password. The reset link may have expired - '
          'request a new one from the login screen.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 60),
              Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: AppRadius.xlAll,
                ),
                child: const Icon(Icons.lock_reset_rounded,
                    size: 40, color: AppColors.primary),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'Set a new password',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'You\'re signed in from the reset link - choose a new password below.',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: context.palette.muted),
              ),
              const SizedBox(height: AppSpacing.xxl),
              TextField(
                controller: _passwordController,
                obscureText: _obscure,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: 'New password (min 6 characters)',
                  prefixIcon: const Icon(Icons.lock_outlined),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _confirmController,
                obscureText: _obscure,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
                decoration: const InputDecoration(
                  labelText: 'Confirm new password',
                  prefixIcon: Icon(Icons.lock_outlined),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Save new password'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
