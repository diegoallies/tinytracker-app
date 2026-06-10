import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../config/design_tokens.dart';
import '../../config/theme.dart';
import '../../services/auth_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/extensions.dart';
import '../../utils/haptics.dart';

class RegisterScreen extends StatefulWidget {
  /// Set when arriving from an email-bound invite link: the email gets
  /// prefilled and locked to the invited address.
  final String? inviteToken;

  const RegisterScreen({super.key, this.inviteToken});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;
  bool _emailLocked = false;
  String? _inviteBabyName;

  @override
  void initState() {
    super.initState();
    final token = widget.inviteToken;
    if (token != null && token.isNotEmpty) {
      _loadInvite(token);
    }
  }

  Future<void> _loadInvite(String token) async {
    try {
      final info = await SupabaseService.client
          .rpc('get_invite_info', params: {'invite_token': token});
      if (!mounted || info == null) return;
      final map = (info as Map).cast<String, dynamic>();
      final email = map['invited_email'] as String?;
      setState(() {
        if (email != null && email.isNotEmpty) {
          _emailController.text = email;
          _emailLocked = true;
        }
        _inviteBabyName = map['baby_name'] as String?;
      });
    } catch (e) {
      debugPrint('invite lookup failed: $e');
    }
  }

  Future<void> _signUp() async {
    final email = _emailController.text.trim();
    if (_nameController.text.trim().isEmpty ||
        email.isEmpty ||
        _passwordController.text.isEmpty) {
      context.showErrorSnackBar('Please fill in all fields');
      return;
    }
    if (!email.contains('@') || !email.contains('.')) {
      context.showErrorSnackBar('That doesn’t look like an email address');
      return;
    }
    if (_passwordController.text.length < 6) {
      context.showErrorSnackBar('Password must be at least 6 characters');
      return;
    }

    Haptics.lightTap();
    setState(() => _loading = true);
    try {
      final auth = AuthService();
      final response = await auth.signUp(
        email: email,
        password: _passwordController.text,
        displayName: _nameController.text.trim(),
      );
      Haptics.mediumTap();
      if (!mounted) return;
      if (response.session == null) {
        // Email confirmation is on: no session until the link is clicked.
        context.showSuccessSnackBar(
            'Almost there - check $email for a confirmation link, then sign in.');
        context.go('/login');
      } else {
        context.go('/onboarding');
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().contains('already registered')
            ? 'That email is already registered - try signing in instead.'
            : 'Couldn’t create your account. Check your connection and try again.';
        context.showErrorSnackBar(msg);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
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
              Center(
                child: ClipRRect(
                  borderRadius: AppRadius.xlAll,
                  child: Image.asset(
                    'assets/images/tinytrack_logo.jpg',
                    width: 88,
                    height: 88,
                    errorBuilder: (_, _, _) => Container(
                      width: 88,
                      height: 88,
                      decoration: const BoxDecoration(
                        color: AppColors.pastelPurple,
                        borderRadius: AppRadius.xlAll,
                      ),
                      child: const Icon(
                        Icons.child_care_rounded,
                        size: 48,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
              )
                  .animate()
                  .fadeIn(duration: AppMotion.entrance)
                  .scale(
                      begin: const Offset(0.85, 0.85),
                      curve: AppMotion.spring,
                      duration: AppMotion.entrance),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'Create Account',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineLarge,
              ).animate().fadeIn(delay: 100.ms, duration: AppMotion.entrance),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Start tracking your baby\'s journey',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: context.palette.muted),
              ).animate().fadeIn(delay: 150.ms, duration: AppMotion.entrance),
              const SizedBox(height: AppSpacing.xxl),
              if (_inviteBabyName != null) ...[
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.10),
                    borderRadius: AppRadius.mdAll,
                    border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.card_giftcard_rounded,
                          color: AppColors.primary, size: 20),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          'You\'ve been invited to help track '
                          '$_inviteBabyName! Create your account below.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              AutofillGroup(
                child: Column(
                  children: [
                    TextField(
                      controller: _nameController,
                      textInputAction: TextInputAction.next,
                      textCapitalization: TextCapitalization.words,
                      autofillHints: const [AutofillHints.name],
                      decoration: const InputDecoration(
                        labelText: 'Display Name',
                        prefixIcon: Icon(Icons.person_outlined),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      readOnly: _emailLocked,
                      autofillHints: const [AutofillHints.email],
                      decoration: InputDecoration(
                        labelText: 'Email',
                        helperText: _emailLocked
                            ? 'The invite is locked to this email'
                            : null,
                        prefixIcon: const Icon(Icons.email_outlined),
                        suffixIcon: _emailLocked
                            ? const Icon(Icons.lock_rounded, size: 18)
                            : null,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.newPassword],
                      onSubmitted: (_) => _signUp(),
                      decoration: InputDecoration(
                        labelText: 'Password (min 6 characters)',
                        prefixIcon: const Icon(Icons.lock_outlined),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 200.ms, duration: AppMotion.entrance),
              const SizedBox(height: AppSpacing.xl),
              ElevatedButton(
                onPressed: _loading ? null : _signUp,
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Create Account'),
              ).animate().fadeIn(delay: 250.ms, duration: AppMotion.entrance),
              const SizedBox(height: AppSpacing.md),
              TextButton(
                onPressed: () => context.go('/login'),
                child: RichText(
                  text: TextSpan(
                    text: 'Already have an account? ',
                    style: TextStyle(color: context.palette.muted),
                    children: const [
                      TextSpan(
                        text: 'Sign In',
                        style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
