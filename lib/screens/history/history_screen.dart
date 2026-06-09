import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../config/design_tokens.dart';
import '../../config/theme.dart';
import '../../providers/diaper_provider.dart';
import '../../providers/feeding_provider.dart';
import '../../providers/history_provider.dart';
import '../../providers/sleep_provider.dart';
import '../../utils/date_utils.dart';
import '../../utils/extensions.dart';
import '../../utils/haptics.dart';
import '../../widgets/common/animated_card.dart';
import '../../widgets/common/app_dialogs.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/loading_skeleton.dart';
import '../../widgets/common/swipe_to_dismiss.dart';

/// Unified, infinitely-scrolling history for feedings, diapers or sleep,
/// grouped by day. Reached via '/history?domain=feeding|diaper|sleep'.
class HistoryScreen extends ConsumerStatefulWidget {
  final HistoryDomain domain;

  const HistoryScreen({super.key, required this.domain});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final ScrollController _scrollController = ScrollController();

  /// How many pages we are currently watching (page 0.._pageCount-1).
  int _pageCount = 1;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  String get _title => switch (widget.domain) {
        HistoryDomain.feeding => 'Feeding History',
        HistoryDomain.diaper => 'Diaper History',
        HistoryDomain.sleep => 'Sleep History',
      };

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter > 400) return;
    _maybeRequestNextPage();
  }

  void _maybeRequestNextPage() {
    // Only ask for another page once the last requested one arrived full —
    // a short page means there is nothing left to fetch.
    final lastPage =
        ref.read(historyPageProvider((widget.domain, _pageCount - 1)));
    if (lastPage.isLoading) return;
    final entries = lastPage.valueOrNull;
    if (entries == null) return;
    if (entries.length < historyPageSize) return;
    setState(() => _pageCount++);
  }

  Future<bool?> _confirmDelete() {
    final what = switch (widget.domain) {
      HistoryDomain.feeding => 'Feeding',
      HistoryDomain.diaper => 'Diaper',
      HistoryDomain.sleep => 'Sleep Session',
    };
    return showDeleteDialog(context, what: what);
  }

  Future<void> _deleteEntry(HistoryEntry entry) async {
    try {
      switch (widget.domain) {
        case HistoryDomain.feeding:
          await FeedingActions.deleteFeeding(entry.id);
          ref.invalidate(recentFeedingsProvider);
        case HistoryDomain.diaper:
          await DiaperActions.deleteDiaper(entry.id);
          ref.invalidate(recentDiapersProvider);
        case HistoryDomain.sleep:
          await SleepActions.deleteSleep(entry.id);
          ref.invalidate(recentSleepsProvider);
      }
      _refreshLoadedPages();
      if (mounted) context.showSuccessSnackBar('Deleted');
    } catch (e) {
      // Restore the optimistically hidden row.
      _refreshLoadedPages();
      if (mounted) {
        context.showErrorSnackBar(
          'Couldn’t delete. Check your connection and try again.',
        );
      }
    }
  }

  /// Re-fetch every page we currently show so rows shift correctly across
  /// page boundaries after a delete.
  void _refreshLoadedPages() {
    for (var page = 0; page < _pageCount; page++) {
      ref.invalidate(historyPageProvider((widget.domain, page)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      for (var page = 0; page < _pageCount; page++)
        ref.watch(historyPageProvider((widget.domain, page))),
    ];

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
        ),
        centerTitle: true,
      ),
      body: SafeArea(child: _buildBody(pages)),
    );
  }

  Widget _buildBody(List<AsyncValue<List<HistoryEntry>>> pages) {
    final first = pages.first;

    if (first.isLoading && !first.hasValue) {
      return const PageSkeleton();
    }

    if (first.hasError && !first.hasValue) {
      return _ErrorState(
        onRetry: () =>
            ref.invalidate(historyPageProvider((widget.domain, 0))),
      );
    }

    final entries = <HistoryEntry>[
      for (final page in pages) ...page.valueOrNull ?? const [],
    ];

    if (entries.isEmpty) {
      return _buildEmptyState();
    }

    final lastPage = pages.last;
    final lastLoaded = lastPage.valueOrNull;
    final reachedEnd =
        lastLoaded != null && lastLoaded.length < historyPageSize;
    final loadingMore = lastPage.isLoading;
    final loadMoreFailed = lastPage.hasError && !lastPage.hasValue;

    final items = _groupByDay(entries);

    return ListView.builder(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics()),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      itemCount: items.length + 1,
      itemBuilder: (context, index) {
        if (index == items.length) {
          if (loadMoreFailed) {
            return _LoadMoreErrorRow(
              onRetry: () => ref.invalidate(
                  historyPageProvider((widget.domain, _pageCount - 1))),
            );
          }
          if (loadingMore) return const _LoaderRow();
          if (reachedEnd) return const _EndOfHistoryRow();
          return const SizedBox(height: AppSpacing.md);
        }
        final item = items[index];
        if (item is String) return _SectionHeader(label: item);
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
          child: _buildEntryRow(item as HistoryEntry),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return switch (widget.domain) {
      HistoryDomain.feeding => const EmptyState(
          icon: Icons.restaurant_outlined,
          illustrationType: 'feeding',
          title: 'No feedings yet',
          description: 'Logged feedings will show up here',
        ),
      HistoryDomain.diaper => const EmptyState(
          icon: Icons.baby_changing_station,
          illustrationType: 'diaper',
          title: 'No diapers yet',
          description: 'Logged diaper changes will show up here',
        ),
      HistoryDomain.sleep => const EmptyState(
          icon: Icons.bedtime_outlined,
          illustrationType: 'sleep',
          title: 'No sleep sessions yet',
          description: 'Completed sleep sessions will show up here',
        ),
    };
  }

  /// Flattens entries into [String] day headers followed by their entries.
  List<Object> _groupByDay(List<HistoryEntry> entries) {
    final items = <Object>[];
    DateTime? currentDay;
    for (final entry in entries) {
      final day = DateTime(
          entry.loggedAt.year, entry.loggedAt.month, entry.loggedAt.day);
      if (currentDay != day) {
        currentDay = day;
        items.add(_dayLabel(day));
      }
      items.add(entry);
    }
    return items;
  }

  String _dayLabel(DateTime day) {
    final today = AppDateUtils.todayStart;
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return DateFormat('EEE, d MMM').format(day);
  }

  Widget _buildEntryRow(HistoryEntry entry) {
    return SwipeToDismiss(
      itemId: entry.id,
      onConfirmDismiss: _confirmDelete,
      onDismissed: () => _deleteEntry(entry),
      child: AnimatedCard(
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: entry.iconColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(entry.icon, color: entry.iconColor, size: 22),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    style: TextStyle(
                      color: context.palette.text,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  if (entry.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      entry.subtitle,
                      style: TextStyle(
                        color: context.palette.muted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              AppDateUtils.formatTime(entry.loggedAt),
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;

  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.xxs, AppSpacing.md, AppSpacing.xxs, AppSpacing.xs),
      child: Text(
        label,
        style: TextStyle(
          color: context.palette.muted,
          fontWeight: FontWeight.w700,
          fontSize: 13,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

class _LoaderRow extends StatelessWidget {
  const _LoaderRow();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }
}

class _EndOfHistoryRow extends StatelessWidget {
  const _EndOfHistoryRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Text(
        'That’s everything',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: context.palette.muted,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _LoadMoreErrorRow extends StatelessWidget {
  final VoidCallback onRetry;

  const _LoadMoreErrorRow({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        children: [
          Text(
            'Couldn’t load more',
            style: TextStyle(color: context.palette.muted, fontSize: 13),
          ),
          TextButton(
            onPressed: () {
              Haptics.lightTap();
              onRetry();
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.cloud_off_rounded,
                size: 40,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Couldn’t load history',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: context.palette.text,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Check your connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: context.palette.muted),
            ),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton(
              onPressed: () {
                Haptics.lightTap();
                onRetry();
              },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(160, 48),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
