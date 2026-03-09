import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../providers/baby_provider.dart';
import '../../providers/diaper_provider.dart';
import '../../utils/date_utils.dart';
import '../../utils/extensions.dart';
import '../../utils/haptics.dart';
import '../../widgets/common/animated_card.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/swipe_to_dismiss.dart';

class DiaperScreen extends ConsumerStatefulWidget {
  const DiaperScreen({super.key});

  @override
  ConsumerState<DiaperScreen> createState() => _DiaperScreenState();
}

class _DiaperScreenState extends ConsumerState<DiaperScreen> {
  String _selectedType = 'wet';
  String? _selectedColor;
  final TextEditingController _notesController = TextEditingController();
  bool _isSaving = false;

  static const _diaperTypes = [
    ('wet', 'Wet', Icons.water_drop_outlined),
    ('dirty', 'Dirty', Icons.circle),
    ('both', 'Both', Icons.layers_outlined),
  ];

  static const _poopColors = [
    ('yellow', 'Yellow', Color(0xFFDAA520)),
    ('green', 'Green', Color(0xFF228B22)),
    ('brown', 'Brown', Color(0xFF8B4513)),
    ('black', 'Black', Color(0xFF1A1A1A)),
    ('red', 'Red', Color(0xFFDC143C)),
    ('white', 'White', Color(0xFFF5F5DC)),
  ];

  bool get _showColorPicker =>
      _selectedType == 'dirty' || _selectedType == 'both';

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final baby = ref.read(selectedBabyProvider);
    if (baby == null) return;

    setState(() => _isSaving = true);

    try {
      await DiaperActions.logDiaper(
        babyId: baby.id,
        type: _selectedType,
        color: _showColorPicker ? _selectedColor : null,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );

      ref.invalidate(recentDiapersProvider);
      ref.invalidate(todayDiaperStatsProvider);

      setState(() {
        _selectedColor = null;
        _notesController.clear();
      });

      Haptics.mediumTap();

      if (mounted) {
        context.showSuccessSnackBar('Diaper logged successfully');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save diaper: $e'),
            backgroundColor: Colors.red.shade400,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<bool?> _confirmDelete() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Diaper'),
        content:
            const Text('Are you sure you want to delete this diaper entry?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteDiaper(String diaperId) async {
    try {
      await DiaperActions.deleteDiaper(diaperId);
      ref.invalidate(recentDiapersProvider);
      ref.invalidate(todayDiaperStatsProvider);
      if (mounted) {
        context.showSuccessSnackBar('Diaper entry deleted');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete: $e'),
            backgroundColor: Colors.red.shade400,
          ),
        );
      }
    }
  }

  Future<void> _onRefresh() async {
    Haptics.lightTap();
    ref.invalidate(recentDiapersProvider);
    ref.invalidate(todayDiaperStatsProvider);
    await ref.read(recentDiapersProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(todayDiaperStatsProvider);
    final recentDiapers = ref.watch(recentDiapersProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.text),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Diaper',
          style: TextStyle(
            color: AppColors.text,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _onRefresh,
          color: AppColors.primary,
          backgroundColor: AppColors.card,
          child: ListView(
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              _buildTodayStats(stats),
              const SizedBox(height: 16),
              _buildTypeSelector(),
              const SizedBox(height: 16),
              if (_showColorPicker) ...[
                _buildColorPicker(),
                const SizedBox(height: 16),
              ],
              _buildNotesField(),
              const SizedBox(height: 20),
              _buildSaveButton(),
              const SizedBox(height: 24),
              _buildRecentList(recentDiapers),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTodayStats(AsyncValue<dynamic> stats) {
    return AnimatedCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: stats.when(
          loading: () => const SizedBox(
            height: 48,
            child: Center(
              child: CircularProgressIndicator(
                  color: AppColors.primary, strokeWidth: 2),
            ),
          ),
          error: (_, __) => const Text(
            'Could not load today\'s stats',
            style: TextStyle(color: AppColors.muted),
          ),
          data: (data) {
            final wet = data.wet as int? ?? 0;
            final dirty = data.dirty as int? ?? 0;
            final both = data.both as int? ?? 0;

            return Row(
              children: [
                const Text(
                  'Today',
                  style: TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                _buildStatChip(
                    Icons.water_drop_outlined, '$wet', 'Wet', Colors.blue),
                const SizedBox(width: 12),
                _buildStatChip(Icons.circle, '$dirty', 'Dirty',
                    const Color(0xFF8B4513)),
                const SizedBox(width: 12),
                _buildStatChip(
                    Icons.layers_outlined, '$both', 'Both', AppColors.primary),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatChip(
      IconData icon, String count, String label, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha:0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Text(
                count,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildTypeSelector() {
    return AnimatedCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Diaper Type',
              style: TextStyle(
                color: AppColors.text,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: _diaperTypes.map((type) {
                final isSelected = _selectedType == type.$1;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: type.$1 == 'wet' ? 0 : 5,
                      right: type.$1 == 'both' ? 0 : 5,
                    ),
                    child: GestureDetector(
                      onTap: () {
                        Haptics.selectionClick();
                        setState(() {
                          _selectedType = type.$1;
                          if (!_showColorPicker) _selectedColor = null;
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        height: 48,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primary.withValues(alpha:0.15)
                              : AppColors.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.muted.withValues(alpha:0.3),
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              type.$3,
                              size: 18,
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.muted,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              type.$2,
                              style: TextStyle(
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.muted,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColorPicker() {
    return AnimatedCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Poop Color',
              style: TextStyle(
                color: AppColors.text,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 16,
              runSpacing: 14,
              alignment: WrapAlignment.center,
              children: _poopColors.map((colorData) {
                final isSelected = _selectedColor == colorData.$1;
                return GestureDetector(
                  onTap: () {
                    Haptics.selectionClick();
                    setState(() {
                      _selectedColor =
                          _selectedColor == colorData.$1 ? null : colorData.$1;
                    });
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: colorData.$3,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primary
                                : Colors.grey.shade300,
                            width: isSelected ? 3 : 1.5,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: AppColors.primary.withValues(alpha:0.3),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : null,
                        ),
                        child: isSelected
                            ? const Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 20,
                              )
                            : null,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        colorData.$2,
                        style: TextStyle(
                          color: isSelected ? AppColors.text : AppColors.muted,
                          fontSize: 11,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotesField() {
    return AnimatedCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: _notesController,
          maxLines: 3,
          minLines: 1,
          decoration: InputDecoration(
            hintText: 'Add notes (optional)',
            hintStyle: TextStyle(color: AppColors.muted.withValues(alpha:0.6)),
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          style: const TextStyle(color: AppColors.text),
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: _isSaving ? null : _save,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.primary.withValues(alpha:0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
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
            : const Text('Save Diaper'),
      ),
    );
  }

  Widget _buildRecentList(AsyncValue<List<dynamic>> recentDiapers) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent Diapers',
          style: TextStyle(
            color: AppColors.text,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 12),
        recentDiapers.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          ),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'Failed to load diapers',
                style: TextStyle(color: AppColors.muted),
              ),
            ),
          ),
          data: (diapers) {
            if (diapers.isEmpty) {
              return const EmptyState(
                icon: Icons.baby_changing_station,
                title: 'No diapers yet',
                description: 'Log your first diaper change above',
              );
            }
            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: diapers.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final diaper = diapers[index];
                return _buildDiaperItem(diaper);
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildDiaperItem(dynamic diaper) {
    final type = diaper.type as String;
    final createdAt = diaper.createdAt as DateTime;
    final color = diaper.color as String?;
    final diaperId = diaper.id as String;

    IconData icon;
    Color iconColor;
    String label;

    switch (type) {
      case 'wet':
        icon = Icons.water_drop_outlined;
        iconColor = Colors.blue;
        label = 'Wet';
        break;
      case 'dirty':
        icon = Icons.circle;
        iconColor = const Color(0xFF8B4513);
        label = 'Dirty';
        break;
      case 'both':
        icon = Icons.layers_outlined;
        iconColor = AppColors.primary;
        label = 'Both';
        break;
      default:
        icon = Icons.help_outline;
        iconColor = AppColors.muted;
        label = type;
    }

    Color? colorIndicator;
    if (color != null) {
      final match = _poopColors.where((c) => c.$1 == color);
      if (match.isNotEmpty) {
        colorIndicator = match.first.$3;
      }
    }

    return SwipeToDismiss(
      itemId: diaperId,
      onConfirmDismiss: _confirmDelete,
      onDismissed: () => _deleteDiaper(diaperId),
      child: AnimatedCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha:0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            color: AppColors.text,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        if (colorIndicator != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: colorIndicator,
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: Colors.grey.shade300, width: 1),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppDateUtils.timeAgo(createdAt),
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
