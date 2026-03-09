import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../providers/baby_provider.dart';
import '../../providers/feeding_provider.dart';
import '../../utils/date_utils.dart';
import '../../utils/extensions.dart';
import '../../widgets/common/animated_card.dart';
import '../../widgets/common/empty_state.dart';

class FeedingScreen extends ConsumerStatefulWidget {
  const FeedingScreen({super.key});

  @override
  ConsumerState<FeedingScreen> createState() => _FeedingScreenState();
}

class _FeedingScreenState extends ConsumerState<FeedingScreen>
    with SingleTickerProviderStateMixin {
  String _selectedType = 'breast_left';
  Timer? _timer;
  int _elapsedSeconds = 0;
  bool _isTimerRunning = false;
  final TextEditingController _amountController =
      TextEditingController(text: '60');
  final TextEditingController _notesController = TextEditingController();
  bool _isSaving = false;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  static const _feedTypes = [
    ('breast_left', 'Left Breast', Icons.woman),
    ('breast_right', 'Right Breast', Icons.woman),
    ('bottle', 'Bottle', Icons.baby_changing_station),
    ('solids', 'Solids', Icons.restaurant),
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _amountController.dispose();
    _notesController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  bool get _isBreastFeeding =>
      _selectedType == 'breast_left' || _selectedType == 'breast_right';

  bool get _isBottle => _selectedType == 'bottle';

  void _startTimer() {
    setState(() {
      _isTimerRunning = true;
      _elapsedSeconds = 0;
    });
    _pulseController.repeat(reverse: true);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _elapsedSeconds++;
      });
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _pulseController.stop();
    _pulseController.reset();
    setState(() {
      _isTimerRunning = false;
    });
  }

  String _formatTimer(int totalSeconds) {
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _adjustAmount(int delta) {
    final current = int.tryParse(_amountController.text) ?? 0;
    final next = (current + delta).clamp(0, 999);
    _amountController.text = next.toString();
  }

  Future<void> _save() async {
    final baby = ref.read(selectedBabyProvider);
    if (baby == null) return;

    setState(() => _isSaving = true);

    try {
      await FeedingActions.logFeeding(
        babyId: baby.id,
        type: _selectedType,
        durationMinutes: _isBreastFeeding ? (_elapsedSeconds ~/ 60) : null,
        amountMl: _isBottle ? int.tryParse(_amountController.text) : null,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );

      if (_isTimerRunning) _stopTimer();

      ref.invalidate(recentFeedingsProvider);

      setState(() {
        _elapsedSeconds = 0;
        _notesController.clear();
        _amountController.text = '60';
      });

      if (mounted) {
        context.showSuccessSnackBar('Feeding logged successfully');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save feeding: $e'),
            backgroundColor: Colors.red.shade400,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteFeeding(String feedingId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Feeding'),
        content: const Text('Are you sure you want to delete this feeding?'),
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

    if (confirmed == true) {
      try {
        await FeedingActions.deleteFeeding(feedingId);
        ref.invalidate(recentFeedingsProvider);
        if (mounted) {
          context.showSuccessSnackBar('Feeding deleted');
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
  }

  @override
  Widget build(BuildContext context) {
    final recentFeedings = ref.watch(recentFeedingsProvider);

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
          'Feeding',
          style: TextStyle(
            color: AppColors.text,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTypeSelector(),
              const SizedBox(height: 16),
              if (_isBreastFeeding) _buildTimer(),
              if (_isBottle) _buildAmountInput(),
              const SizedBox(height: 16),
              _buildNotesField(),
              const SizedBox(height: 20),
              _buildSaveButton(),
              const SizedBox(height: 24),
              _buildRecentList(recentFeedings),
            ],
          ),
        ),
      ),
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
              'Feed Type',
              style: TextStyle(
                color: AppColors.text,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.8,
              children: _feedTypes.map((type) {
                final isSelected = _selectedType == type.$1;
                return GestureDetector(
                  onTap: () {
                    if (_isTimerRunning) _stopTimer();
                    setState(() => _selectedType = type.$1);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
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
                          color:
                              isSelected ? AppColors.primary : AppColors.muted,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            type.$2,
                            style: TextStyle(
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.muted,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
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

  Widget _buildTimer() {
    return AnimatedCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              'Duration',
              style: TextStyle(
                color: AppColors.text,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 16),
            ScaleTransition(
              scale: _isTimerRunning ? _pulseAnimation : const AlwaysStoppedAnimation(1.0),
              child: Text(
                _formatTimer(_elapsedSeconds),
                style: TextStyle(
                  fontSize: 56,
                  fontWeight: FontWeight.w700,
                  color: _isTimerRunning ? AppColors.primary : AppColors.text,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _isTimerRunning ? _stopTimer : _startTimer,
                icon: Icon(
                    _isTimerRunning ? Icons.stop_rounded : Icons.play_arrow_rounded),
                label: Text(_isTimerRunning ? 'Stop' : 'Start'),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _isTimerRunning ? Colors.red.shade400 : AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAmountInput() {
    return AnimatedCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Amount (ml)',
              style: TextStyle(
                color: AppColors.text,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildAmountButton(Icons.remove, () => _adjustAmount(-10)),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                    decoration: InputDecoration(
                      suffixText: 'ml',
                      suffixStyle: const TextStyle(
                        fontSize: 16,
                        color: AppColors.muted,
                      ),
                      filled: true,
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _buildAmountButton(Icons.add, () => _adjustAmount(10)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAmountButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: AppColors.pastelPurple,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(icon, color: AppColors.primary),
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
            : const Text('Save Feeding'),
      ),
    );
  }

  Widget _buildRecentList(AsyncValue<List<dynamic>> recentFeedings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Recent Feedings',
          style: TextStyle(
            color: AppColors.text,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 12),
        recentFeedings.when(
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
                'Failed to load feedings',
                style: TextStyle(color: AppColors.muted),
              ),
            ),
          ),
          data: (feedings) {
            if (feedings.isEmpty) {
              return const EmptyState(
                icon: Icons.restaurant_outlined,
                title: 'No feedings yet',
                description: 'Log your first feeding above',
              );
            }
            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: feedings.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final feeding = feedings[index];
                return _buildFeedingItem(feeding);
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildFeedingItem(dynamic feeding) {
    final type = feeding.type as String;
    final createdAt = feeding.createdAt as DateTime;

    IconData icon;
    String label;
    String detail;

    switch (type) {
      case 'breast_left':
        icon = Icons.woman;
        label = 'Left Breast';
        detail = feeding.durationSeconds != null
            ? _formatTimer(feeding.durationSeconds as int)
            : '';
        break;
      case 'breast_right':
        icon = Icons.woman;
        label = 'Right Breast';
        detail = feeding.durationSeconds != null
            ? _formatTimer(feeding.durationSeconds as int)
            : '';
        break;
      case 'bottle':
        icon = Icons.baby_changing_station;
        label = 'Bottle';
        detail = feeding.amountMl != null ? '${feeding.amountMl} ml' : '';
        break;
      case 'solids':
        icon = Icons.restaurant;
        label = 'Solids';
        detail = '';
        break;
      default:
        icon = Icons.restaurant;
        label = type;
        detail = '';
    }

    return AnimatedCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.pastelPurple,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.primary, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: AppColors.text,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
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
            if (detail.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  detail,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            IconButton(
              icon: Icon(Icons.delete_outline,
                  color: AppColors.muted.withValues(alpha:0.6), size: 20),
              onPressed: () => _deleteFeeding(feeding.id as String),
              splashRadius: 20,
            ),
          ],
        ),
      ),
    );
  }
}
