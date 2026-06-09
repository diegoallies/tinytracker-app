import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../providers/baby_provider.dart';
import '../../services/supabase_service.dart';
import '../../utils/date_utils.dart';
import '../../utils/extensions.dart';
import '../../widgets/common/animated_card.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/loading_skeleton.dart';

class InvitesScreen extends ConsumerStatefulWidget {
  const InvitesScreen({super.key});

  @override
  ConsumerState<InvitesScreen> createState() => _InvitesScreenState();
}

class _InvitesScreenState extends ConsumerState<InvitesScreen> {
  List<Map<String, dynamic>> _invites = [];
  bool _isLoading = true;
  bool _hasError = false;
  final Set<String> _acceptingIds = {};

  @override
  void initState() {
    super.initState();
    _loadInvites();
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

      // Fetch pending invites that haven't expired and haven't been accepted
      final response = await SupabaseService.client
          .from('baby_invites')
          .select('*, babies:baby_id(name)')
          .eq('status', 'pending')
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
      final userId = SupabaseService.client.auth.currentUser?.id;
      if (userId == null) throw Exception('Not authenticated');

      final babyId = invite['baby_id'] as String;
      final role = invite['role'] as String;

      // Create the baby_shares entry
      await SupabaseService.client.from('baby_shares').insert({
        'baby_id': babyId,
        'user_id': userId,
        'role': role,
      });

      // Mark invite as accepted
      await SupabaseService.client
          .from('baby_invites')
          .update({'status': 'accepted'})
          .eq('id', inviteId);

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
        return Colors.grey.shade100;
    }
  }

  Color _roleIconColor(String role) {
    switch (role) {
      case 'logger':
        return const Color(0xFF5b8cbf);
      case 'viewer':
        return const Color(0xFF5bbf8c);
      default:
        return AppColors.muted;
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

    if (_invites.isEmpty) {
      return const Center(
        child: EmptyState(
          icon: Icons.mail_outline_rounded,
          title: 'No Pending Invites',
          description: 'When someone shares a baby profile with you, the invite will appear here.',
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadInvites,
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: _invites.length,
        itemBuilder: (context, index) {
          final invite = _invites[index];
          return _buildInviteCard(invite);
        },
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
                          role.capitalize,
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
