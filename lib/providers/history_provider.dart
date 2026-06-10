import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/theme.dart';
import '../models/diaper.dart';
import '../models/feeding.dart';
import '../models/sleep_session.dart';
import '../services/supabase_service.dart';
import '../utils/date_utils.dart';
import '../utils/extensions.dart';
import 'baby_provider.dart';

/// Which tracking domain a history page belongs to.
enum HistoryDomain { feeding, diaper, sleep }

/// Rows fetched per page from Supabase.
const int historyPageSize = 30;

/// A display-ready wrapper around a feeding/diaper/sleep row, so the
/// history screen can render every domain with one row widget.
class HistoryEntry {
  final String id;
  final HistoryDomain domain;

  /// Local time used for day grouping and the trailing time label.
  final DateTime loggedAt;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;

  const HistoryEntry({
    required this.id,
    required this.domain,
    required this.loggedAt,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
  });
}

/// One page of history for a domain, newest first. The screen accumulates
/// pages locally; each page stays cached while it is being watched.
final historyPageProvider = FutureProvider.autoDispose
    .family<List<HistoryEntry>, (HistoryDomain, int)>((ref, args) async {
  final (domain, page) = args;
  final baby = ref.watch(selectedBabyProvider);
  if (baby == null) return const [];

  final from = page * historyPageSize;
  final to = from + historyPageSize - 1;

  switch (domain) {
    case HistoryDomain.feeding:
      final data = await SupabaseService.client
          .from('feedings')
          .select('*')
          .eq('baby_id', baby.id)
          .isFilter('deleted_at', null)
          .order('logged_at', ascending: false)
          .range(from, to);
      return data
          .map<HistoryEntry>((json) => _feedingEntry(Feeding.fromJson(json)))
          .toList();

    case HistoryDomain.diaper:
      final data = await SupabaseService.client
          .from('diapers')
          .select('*')
          .eq('baby_id', baby.id)
          .isFilter('deleted_at', null)
          .order('logged_at', ascending: false)
          .range(from, to);
      return data
          .map<HistoryEntry>((json) =>
              _diaperEntry(Diaper.fromJson(json), json['stool_type'] as int?))
          .toList();

    case HistoryDomain.sleep:
      final data = await SupabaseService.client
          .from('sleeps')
          .select('*')
          .eq('baby_id', baby.id)
          .not('end_time', 'is', null)
          .isFilter('deleted_at', null)
          .order('start_time', ascending: false)
          .range(from, to);
      return data
          .map<HistoryEntry>((json) => _sleepEntry(SleepSession.fromJson(json)))
          .toList();
  }
});

HistoryEntry _feedingEntry(Feeding feeding) {
  final IconData icon;
  String detail;
  switch (feeding.type) {
    case 'breast_left':
    case 'breast_right':
      icon = Icons.woman;
      detail =
          feeding.durationMinutes != null ? '${feeding.durationMinutes} min' : '';
    case 'bottle':
      icon = Icons.local_drink_rounded;
      detail = feeding.amountMl != null ? '${feeding.amountMl} ml' : '';
    case 'solids':
      icon = Icons.restaurant;
      detail = '';
    default:
      icon = Icons.restaurant;
      detail = '';
  }

  return HistoryEntry(
    id: feeding.id,
    domain: HistoryDomain.feeding,
    loggedAt: feeding.loggedAt.toLocal(),
    title: feeding.typeDisplay,
    subtitle: detail,
    icon: icon,
    iconColor: AppColors.primary,
  );
}

HistoryEntry _diaperEntry(Diaper diaper, int? stoolType) {
  final IconData icon;
  final Color iconColor;
  switch (diaper.type) {
    case 'wet':
      icon = Icons.water_drop_outlined;
      iconColor = AppColors.info;
    case 'dirty':
      icon = Icons.circle;
      iconColor = AppColors.poopBrown;
    case 'both':
      icon = Icons.layers_outlined;
      iconColor = AppColors.primary;
    default:
      icon = Icons.help_outline;
      iconColor = AppColors.muted;
  }

  final details = <String>[
    if (diaper.color != null) diaper.color!.capitalize,
    if (stoolType != null) 'Stool type $stoolType',
  ];

  return HistoryEntry(
    id: diaper.id,
    domain: HistoryDomain.diaper,
    loggedAt: diaper.loggedAt.toLocal(),
    title: diaper.typeDisplay,
    subtitle: details.join(' · '),
    icon: icon,
    iconColor: iconColor,
  );
}

HistoryEntry _sleepEntry(SleepSession sleep) {
  final start = sleep.startTime.toLocal();
  // Completed sessions only (the query filters out end_time null), but stay
  // defensive so a bad row can't crash the whole page.
  final end = sleep.endTime?.toLocal();
  final range = end != null
      ? '${AppDateUtils.formatTime(start)} - ${AppDateUtils.formatTime(end)}'
      : 'Started ${AppDateUtils.formatTime(start)}';

  return HistoryEntry(
    id: sleep.id,
    domain: HistoryDomain.sleep,
    loggedAt: start,
    title: sleep.durationDisplay,
    subtitle: range,
    icon: Icons.bedtime_outlined,
    iconColor: AppColors.primary,
  );
}
