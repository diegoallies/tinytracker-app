import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthApiException;
import '../../app/deep_links.dart';
import '../../config/design_tokens.dart';
import '../../config/theme.dart';
import '../../services/auth_service.dart';
import '../../utils/extensions.dart';
import '../../utils/haptics.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;

  Future<void> _signIn() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || _passwordController.text.isEmpty) {
      context.showErrorSnackBar('Please fill in all fields');
      return;
    }
    if (!email.contains('@') || !email.contains('.')) {
      context.showErrorSnackBar('That doesn’t look like an email address');
      return;
    }

    Haptics.lightTap();
    setState(() => _loading = true);
    try {
      final auth = AuthService();
      await auth.signIn(email: email, password: _passwordController.text);
      TextInput.finishAutofillContext();
      Haptics.mediumTap();
      if (mounted) {
        // An invite link tapped while logged out resumes after sign-in
        // (survives app restarts via SharedPreferences).
        final inviteToken = await consumePendingInvite();
        if (!mounted) return;
        if (inviteToken != null) {
          context.go('/invites?code=$inviteToken');
        } else {
          context.go('/dashboard');
        }
      }
    } catch (e) {
      if (mounted) {
        final notConfirmed = e is AuthApiException &&
            (e.code == 'email_not_confirmed' ||
                e.message.toLowerCase().contains('not confirmed'));
        if (notConfirmed) {
          _showConfirmEmailSheet(email);
        } else {
          context.showErrorSnackBar('Invalid email or password');
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Shown when the credentials are right but the account hasn't clicked its
  /// confirmation link yet - a generic "wrong password" here would be a lie.
  void _showConfirmEmailSheet(String email) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.md,
          AppSpacing.gutter,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.mark_email_unread_rounded,
                size: 44, color: AppColors.primary),
            const SizedBox(height: AppSpacing.sm),
            Text('Confirm your email first',
                style: Theme.of(ctx).textTheme.titleLarge,
                textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Your account exists, but we sent a confirmation link to '
              '$email and it hasn\'t been clicked yet. Open that email, tap '
              'the link, then sign in again.',
              style: Theme.of(ctx).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            ElevatedButton.icon(
              icon: const Icon(Icons.send_rounded, size: 18),
              label: const Text('Resend confirmation email'),
              onPressed: () async {
                Navigator.pop(ctx);
                final ok = await AuthService().resendConfirmation(email);
                if (!mounted) return;
                if (ok) {
                  context.showSuccessSnackBar(
                      'Confirmation email sent to $email');
                } else {
                  context.showErrorSnackBar(
                      'Couldn\'t resend right now. Wait a minute and try again.');
                }
              },
            ),
            const SizedBox(height: AppSpacing.xs),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('I\'ll check my inbox'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _forgotPassword() async {
    Haptics.lightTap();
    final controller =
        TextEditingController(text: _emailController.text.trim());
    final email = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.xs,
          AppSpacing.gutter,
          MediaQuery.of(ctx).viewInsets.bottom + AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Reset password',
                style: Theme.of(ctx).textTheme.titleLarge,
                textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'We’ll email you a link to set a new password.',
              style: Theme.of(ctx).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: controller,
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email_outlined),
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
            ),
            const SizedBox(height: AppSpacing.md),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Send reset link'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();

    if (email == null || email.isEmpty || !mounted) return;
    final ok = await AuthService().resetPassword(email);
    if (!mounted) return;
    if (ok) {
      context.showSuccessSnackBar('Reset link sent - check your inbox');
    } else {
      context.showErrorSnackBar('Couldn’t send the reset link. Try again.');
    }
  }

  @override
  void dispose() {
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
              // Logo
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
                'Welcome back',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineLarge,
              ).animate().fadeIn(delay: 100.ms, duration: AppMotion.entrance),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Sign in to continue tracking',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: context.palette.muted),
              ).animate().fadeIn(delay: 150.ms, duration: AppMotion.entrance),
              const SizedBox(height: AppSpacing.xxl),
              AutofillGroup(
                child: Column(
                  children: [
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      onSubmitted: (_) => _signIn(),
                      decoration: InputDecoration(
                        labelText: 'Password',
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
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _forgotPassword,
                  child: const Text('Forgot password?'),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              ElevatedButton(
                onPressed: _loading ? null : _signIn,
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Sign In'),
              ).animate().fadeIn(delay: 250.ms, duration: AppMotion.entrance),
              const SizedBox(height: AppSpacing.md),
              TextButton(
                onPressed: () => context.go('/register'),
                child: RichText(
                  text: TextSpan(
                    text: "Don't have an account? ",
                    style: TextStyle(color: context.palette.muted),
                    children: const [
                      TextSpan(
                        text: 'Register',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
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
