import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/design_tokens.dart';
import '../../config/theme.dart';
import '../../providers/baby_provider.dart';
import '../../services/supabase_service.dart';
import '../../utils/date_utils.dart';
import '../../utils/extensions.dart';
import '../../utils/role_labels.dart';
import '../../widgets/common/animated_card.dart';
import '../../widgets/common/app_dialogs.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/loading_skeleton.dart';

class InvitesScreen extends ConsumerStatefulWidget {
  /// Invite token arriving via a `tinytracker://invite/...` deep link;
  /// pre-fills the join field and redeems automatically.
  final String? initialCode;

  const InvitesScreen({super.key, this.initialCode});

  @override
  ConsumerState<InvitesScreen> createState() => _InvitesScreenState();
}

class _InvitesScreenState extends ConsumerState<InvitesScreen> {
  List<Map<String, dynamic>> _invites = [];
  bool _isLoading = true;
  bool _hasError = false;
  bool _isRedeeming = false;
  final Set<String> _acceptingIds = {};
  final TextEditingController _codeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final code = widget.initialCode;
    if (code != null && code.isNotEmpty) {
      _codeController.text = code;
      // Sequence load → redeem so the redeem's reload can't be overwritten
      // by the initial (pre-redeem) load resolving late.
      _loadInvites().then((_) {
        if (mounted) _redeemCode();
      });
    } else {
      _loadInvites();
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  /// Accepts an invite from a pasted link/code, e.g.
  /// `tinytracker://invite/abc123` or just `abc123`.
  Future<void> _redeemCode() async {
    final raw = _codeController.text.trim();
    if (raw.isEmpty) return;
    final token = raw.contains('/') ? raw.split('/').last : raw;

    setState(() => _isRedeeming = true);
    try {
      final result = await _acceptByToken(token);
      if (!mounted) return;
      _codeController.clear();
      ref.invalidate(babyProvider);
      final babyName = (result?['baby_name'] as String?) ?? 'the baby';
      context.showSuccessSnackBar('You now have access to $babyName\'s profile!');
      await _loadInvites();
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar(
          'That invite link didn’t work — it may be expired or already used.',
        );
      }
    } finally {
      if (mounted) setState(() => _isRedeeming = false);
    }
  }

  /// Prefers the server-side accept_invite RPC (atomic, validates the token,
  /// uses the inviter-chosen role). Falls back to the legacy client-side flow
  /// until the DB migration that creates the RPC has been applied.
  Future<Map<String, dynamic>?> _acceptByToken(String token) async {
    final client = SupabaseService.client;
    try {
      final result = await client
          .rpc('accept_invite', params: {'invite_token': token});
      return (result as Map?)?.cast<String, dynamic>();
    } on PostgrestException catch (e) {
      final missingFn = e.code == '42883' || e.code == 'PGRST202';
      if (!missingFn) rethrow;
    }

    // Legacy fallback (pre-migration policies allow this).
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');
    final invite = await client
        .from('baby_invites')
        .select('id, baby_id, role, babies:baby_id(name)')
        .eq('token', token)
        .isFilter('used_by', null)
        .gte('expires_at', DateTime.now().toUtc().toIso8601String())
        .single();
    await client.from('baby_shares').insert({
      'baby_id': invite['baby_id'],
      'user_id': userId,
      'role': invite['role'],
    });
    await client.from('baby_invites').update({
      'used_by': userId,
      'used_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', invite['id']);
    final babies = invite['babies'];
    return {
      'baby_id': invite['baby_id'],
      'baby_name': babies is Map ? babies['name'] : null,
      'role': invite['role'],
    };
  }

  Future<void> _loadInvites() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final userId = SupabaseService.client.auth.currentUser?.id;
      if (userId == null) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
        return;
      }

      // Fetch pending invites that haven't expired and haven't been used.
      // (The table has no 'status' column — an invite is pending while
      // used_by is null.)
      final response = await SupabaseService.client
          .from('baby_invites')
          .select('*, babies:baby_id(name)')
          .isFilter('used_by', null)
          .gte('expires_at', DateTime.now().toUtc().toIso8601String())
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _invites = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  Future<void> _acceptInvite(Map<String, dynamic> invite) async {
    final inviteId = invite['id'] as String;

    setState(() => _acceptingIds.add(inviteId));

    try {
      await _acceptByToken(invite['token'] as String);

      // Refresh the baby provider to pick up the new share
      ref.invalidate(babyProvider);

      if (mounted) {
        setState(() {
          _invites.removeWhere((i) => i['id'] == inviteId);
          _acceptingIds.remove(inviteId);
        });

        final babyName = _getBabyName(invite);
        context.showSuccessSnackBar(
            'You now have access to $babyName\'s profile!');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _acceptingIds.remove(inviteId));
        context.showErrorSnackBar(
          'Couldn’t accept the invite. Check your connection and try again.',
        );
      }
    }
  }

  /// Revokes (deletes) an invite the current user sent, after confirmation.
  Future<void> _revokeInvite(Map<String, dynamic> invite) async {
    final confirmed = await showDeleteDialog(context, what: 'invite');
    if (!confirmed || !mounted) return;

    try {
      await SupabaseService.client
          .from('baby_invites')
          .delete()
          .eq('id', invite['id'] as String);
      if (!mounted) return;
      context.showSuccessSnackBar('Invite revoked');
      await _loadInvites();
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar(
          'Couldn’t revoke the invite. Check your connection and try again.',
        );
      }
    }
  }

  String _getBabyName(Map<String, dynamic> invite) {
    final babies = invite['babies'];
    if (babies is Map && babies['name'] != null) {
      return babies['name'] as String;
    }
    return 'Unknown';
  }

  IconData _roleIcon(String role) {
    switch (role) {
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
      case 'logger':
        return const Color(0xFF5b8cbf);
      case 'viewer':
        return const Color(0xFF5bbf8c);
      default:
        return context.palette.muted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Invites'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _isLoading ? null : _loadInvites,
          ),
        ],
      ),
      body: SafeArea(
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const _InvitesSkeleton();
    }

    if (_hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 48, color: Colors.red.shade300),
              const SizedBox(height: 16),
              Text(
                'Failed to load invites',
                style: TextStyle(fontSize: 16, color: Colors.red.shade400),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _loadInvites,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final userId = SupabaseService.client.auth.currentUser?.id;
    final incoming =
        _invites.where((i) => i['invited_by'] != userId).toList();
    final sent = _invites.where((i) => i['invited_by'] == userId).toList();

    return RefreshIndicator(
      onRefresh: _loadInvites,
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildRedeemCard(),
          const SizedBox(height: AppSpacing.md),
          if (_invites.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.xxl),
              child: EmptyState(
                icon: Icons.mail_outline_rounded,
                title: 'No Pending Invites',
                description:
                    'Got an invite link? Paste it above to join. Invites you’ve sent will appear here.',
              ),
            )
          else ...[
            ...incoming.map(_buildInviteCard),
            if (sent.isNotEmpty) ...[
              if (incoming.isNotEmpty) const SizedBox(height: AppSpacing.md),
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text(
                  'Invites you’ve sent',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ...sent.map(_buildSentInviteCard),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildRedeemCard() {
    return AnimatedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Have an invite link?',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Paste the link or code someone shared with you.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _codeController,
                  decoration: const InputDecoration(
                    hintText: 'tinytracker://invite/…',
                    isDense: true,
                  ),
                  autocorrect: false,
                  onSubmitted: (_) => _redeemCode(),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _isRedeeming ? null : _redeemCode,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(80, 48),
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  ),
                  child: _isRedeeming
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text('Join'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInviteCard(Map<String, dynamic> invite) {
    final inviteId = invite['id'] as String;
    final babyName = _getBabyName(invite);
    final role = invite['role'] as String? ?? 'viewer';
    final expiresAt = invite['expires_at'] != null
        ? DateTime.tryParse(invite['expires_at'] as String)
        : null;
    final isAccepting = _acceptingIds.contains(inviteId);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AnimatedCard(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.pastelPurple,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.child_care_rounded,
                      color: AppColors.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          babyName,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: context.palette.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'You\'ve been invited to track this baby',
                          style: TextStyle(
                            fontSize: 13,
                            color: context.palette.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _roleColor(role),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_roleIcon(role), size: 14, color: _roleIconColor(role)),
                        const SizedBox(width: 6),
                        Text(
                          roleDisplayName(role),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _roleIconColor(role),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (expiresAt != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.pastelYellow,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.timer_outlined,
                            size: 14,
                            color: Color(0xFFb0a040),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Expires ${AppDateUtils.formatDate(expiresAt)}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFFb0a040),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  onPressed: isAccepting ? null : () => _acceptInvite(invite),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: isAccepting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Accept Invite',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A pending invite the current user sent: no Accept button (accepting it
  /// would burn the invite), just details and a revoke action.
  Widget _buildSentInviteCard(Map<String, dynamic> invite) {
    final babyName = _getBabyName(invite);
    final role = invite['role'] as String? ?? 'viewer';
    final expiresAt = invite['expires_at'] != null
        ? DateTime.tryParse(invite['expires_at'] as String)
        : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AnimatedCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.pastelPurple,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.child_care_rounded,
                  color: AppColors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      babyName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: context.palette.text,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _roleColor(role),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(_roleIcon(role),
                                  size: 12, color: _roleIconColor(role)),
                              const SizedBox(width: 4),
                              Text(
                                roleDisplayName(role),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _roleIconColor(role),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (expiresAt != null)
                          Text(
                            'Expires ${AppDateUtils.formatDate(expiresAt)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.palette.muted,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.red.shade300,
                ),
                tooltip: 'Revoke invite',
                onPressed: () => _revokeInvite(invite),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InvitesSkeleton extends StatelessWidget {
  const _InvitesSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: const [
          LoadingSkeleton(width: double.infinity, height: 180, borderRadius: 16),
          SizedBox(height: 12),
          LoadingSkeleton(width: double.infinity, height: 180, borderRadius: 16),
        ],
      ),
    );
  }
}
