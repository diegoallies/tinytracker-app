import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/baby.dart';
import '../utils/care_pack_data.dart';
import '../utils/immunisation_data.dart';
import '../utils/who_growth_data.dart';
import 'report_math.dart';
import 'supabase_service.dart';

/// Builds the "Family Report" PDF: an owner-facing weekly or monthly summary
/// of everything logged for the baby - feeding, sleep, nappies, reflux,
/// health and medicine, growth, milestones, immunisations and journal
/// highlights - with deltas against the equal-length previous period.
///
/// Pure data, no AI calls. Every query degrades to an empty section instead
/// of crashing (Care Pack tables/columns may not have been migrated yet),
/// and every string that reaches the PDF is sanitized to the WinAnsi-safe
/// ASCII range so the built-in Helvetica fonts never choke on user content.
///
/// This class owns fetching and PDF layout only; every number it prints is
/// computed by the pure, unit-tested functions in report_math.dart.
class FamilyReportService {
  FamilyReportService._();

  // -------------------------------------------------------------------
  // Palette: purple primary, dark ink, muted grey + one accent/section.
  // -------------------------------------------------------------------
  static final PdfColor _primary = PdfColor.fromHex('#9b72cf');
  static final PdfColor _primarySoft = PdfColor.fromHex('#b89ce0');
  static final PdfColor _ink = PdfColor.fromHex('#2d2640');
  static final PdfColor _muted = PdfColor.fromHex('#8b85a0');
  static final PdfColor _rule = PdfColor.fromHex('#ddd6e8');
  static final PdfColor _zebra = PdfColor.fromHex('#f5f3f8');
  static final PdfColor _cellFill = PdfColor.fromHex('#f7f5fa');
  static final PdfColor _headerFill = PdfColor.fromHex('#ede4f7');
  static final PdfColor _bandDivider = PdfColor.fromHex('#463d5c');
  static final PdfColor _lavender = PdfColor.fromHex('#c9b8e8');
  static final PdfColor _good = PdfColor.fromHex('#4f9a58');
  static final PdfColor _bad = PdfColor.fromHex('#c0564f');
  static final PdfColor _barEmpty = PdfColor.fromHex('#ece8f2');

  // Section accents (exactly one per section header).
  static final PdfColor _accentGlance = PdfColor.fromHex('#9b72cf');
  static final PdfColor _accentFeeding = PdfColor.fromHex('#e09c3f');
  static final PdfColor _accentSleep = PdfColor.fromHex('#5b7fd4');
  static final PdfColor _accentNappies = PdfColor.fromHex('#5fa46b');
  static final PdfColor _accentReflux = PdfColor.fromHex('#cf6a5e');
  static final PdfColor _accentHealth = PdfColor.fromHex('#46a5a0');
  static final PdfColor _accentGrowth = PdfColor.fromHex('#7b52af');
  static final PdfColor _accentJournal = PdfColor.fromHex('#c578a8');

  // -------------------------------------------------------------------
  // Entry point
  // -------------------------------------------------------------------

  static Future<Uint8List> build({
    required Baby baby,
    required DateTime periodStart,
    required DateTime periodEnd,
    required bool isMonthly,
  }) async {
    // The equal-length previous period, for deltas.
    final DateTime prevStart;
    if (isMonthly) {
      prevStart = DateTime(periodStart.year, periodStart.month - 1, 1);
    } else {
      prevStart = DateTime(
          periodStart.year, periodStart.month, periodStart.day - 7);
    }
    final prevEnd = periodStart;

    final client = SupabaseService.client;

    // Generic period fetch. Selecting '*' means a missing column never fails
    // the request; the catch means a missing table degrades to an empty
    // section instead of crashing the whole report.
    Future<List<Map<String, dynamic>>> rows(
      String table,
      String timeCol,
      DateTime start,
      DateTime end, {
      bool dateOnly = false,
    }) async {
      try {
        final since =
            dateOnly ? dayKey(start) : start.toUtc().toIso8601String();
        final until = dateOnly ? dayKey(end) : end.toUtc().toIso8601String();
        final data = await client
            .from(table)
            .select('*')
            .eq('baby_id', baby.id)
            .isFilter('deleted_at', null)
            .gte(timeCol, since)
            .lt(timeCol, until)
            .order(timeCol, ascending: true);
        return List<Map<String, dynamic>>.from(data);
      } catch (_) {
        return const [];
      }
    }

    Future<List<Map<String, dynamic>>> milestonesAchieved() async {
      try {
        final data = await client
            .from('milestones')
            .select('*')
            .eq('baby_id', baby.id)
            .eq('achieved', true)
            .isFilter('deleted_at', null)
            .gte('achieved_at', periodStart.toUtc().toIso8601String())
            .lt('achieved_at', periodEnd.toUtc().toIso8601String())
            .order('achieved_at', ascending: true);
        return List<Map<String, dynamic>>.from(data);
      } catch (_) {
        return const [];
      }
    }

    Future<List<Map<String, dynamic>>> medicationCatalog() async {
      try {
        final data = await client
            .from('baby_medications')
            .select('*')
            .eq('baby_id', baby.id)
            .isFilter('deleted_at', null)
            .order('name', ascending: true);
        return List<Map<String, dynamic>>.from(data);
      } catch (_) {
        return const [];
      }
    }

    final results = await Future.wait([
      rows('feedings', 'logged_at', periodStart, periodEnd),
      rows('sleeps', 'start_time', periodStart, periodEnd),
      rows('diapers', 'logged_at', periodStart, periodEnd),
      rows('reflux_events', 'logged_at', periodStart, periodEnd),
      rows('daily_journals', 'journal_date', periodStart, periodEnd,
          dateOnly: true),
      rows('health_logs', 'logged_at', periodStart, periodEnd),
      rows('growth', 'measured_at', periodStart, periodEnd),
      rows('tummy_times', 'start_time', periodStart, periodEnd),
      milestonesAchieved(),
      rows('immunisations', 'given_on', periodStart, periodEnd,
          dateOnly: true),
      medicationCatalog(),
      // Previous period - only what the deltas and comparisons need.
      rows('feedings', 'logged_at', prevStart, prevEnd),
      rows('sleeps', 'start_time', prevStart, prevEnd),
      rows('diapers', 'logged_at', prevStart, prevEnd),
      rows('reflux_events', 'logged_at', prevStart, prevEnd),
      rows('health_logs', 'logged_at', prevStart, prevEnd),
      rows('tummy_times', 'start_time', prevStart, prevEnd),
    ]);

    final data = _ReportData(
      baby: baby,
      periodStart: periodStart,
      periodEnd: periodEnd,
      prevStart: prevStart,
      prevEnd: prevEnd,
      isMonthly: isMonthly,
      feedings: results[0],
      sleeps: results[1],
      diapers: results[2],
      reflux: results[3],
      journals: results[4],
      healthLogs: results[5],
      growth: results[6],
      tummyTimes: results[7],
      milestones: results[8],
      immunisations: results[9],
      medications: results[10],
      prevFeedings: results[11],
      prevSleeps: results[12],
      prevDiapers: results[13],
      prevReflux: results[14],
      prevHealthLogs: results[15],
      prevTummyTimes: results[16],
    );

    return _buildPdf(data);
  }

  // -------------------------------------------------------------------
  // PDF assembly
  // -------------------------------------------------------------------

  static Future<Uint8List> _buildPdf(_ReportData d) async {
    final pdf = pw.Document();
    final periodLabel = _periodLabel(d);
    final footerText =
        _ascii('TinyTrack - ${d.baby.name} - $periodLabel');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(40, 36, 40, 36),
        header: (context) => context.pageNumber == 1
            ? pw.SizedBox()
            : pw.Container(
                margin: const pw.EdgeInsets.only(bottom: 16),
                padding: const pw.EdgeInsets.only(bottom: 6),
                decoration: pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: _rule, width: 0.75),
                  ),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'TinyTrack Family Report',
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: _ink,
                      ),
                    ),
                    pw.Text(
                      _ascii('${d.baby.name} - $periodLabel'),
                      style: pw.TextStyle(fontSize: 9, color: _muted),
                    ),
                  ],
                ),
              ),
        footer: (context) => pw.Container(
          margin: const pw.EdgeInsets.only(top: 10),
          padding: const pw.EdgeInsets.only(top: 6),
          decoration: pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: _rule, width: 0.75)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(footerText,
                  style: pw.TextStyle(fontSize: 8, color: _muted)),
              pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: pw.TextStyle(fontSize: 8, color: _muted),
              ),
            ],
          ),
        ),
        build: (context) => [
          _coverBand(d, periodLabel),
          pw.SizedBox(height: 22),
          ..._atAGlanceSection(d),
          pw.SizedBox(height: 20),
          ..._dayByDaySection(d),
          ..._feedingSection(d),
          pw.SizedBox(height: 20),
          ..._sleepSection(d),
          pw.SizedBox(height: 20),
          ..._nappiesSection(d),
          pw.SizedBox(height: 20),
          ..._refluxSection(d),
          pw.SizedBox(height: 20),
          ..._healthSection(d),
          ..._growthSection(d),
          pw.SizedBox(height: 20),
          ..._journalSection(d),
        ],
      ),
    );

    return pdf.save();
  }

  // -------------------------------------------------------------------
  // 1. Cover band
  // -------------------------------------------------------------------

  static pw.Widget _coverBand(_ReportData d, String periodLabel) {
    final generated =
        DateFormat('d MMMM yyyy, HH:mm').format(DateTime.now());
    final smallStyle = pw.TextStyle(fontSize: 9, color: _lavender);

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.fromLTRB(28, 26, 28, 22),
      decoration: pw.BoxDecoration(
        color: _ink,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              pw.Container(width: 26, height: 3, color: _primary),
              pw.SizedBox(width: 8),
              pw.Text(
                'TINYTRACK FAMILY REPORT',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  letterSpacing: 2,
                  color: _lavender,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            _ascii(d.baby.name),
            style: pw.TextStyle(
              fontSize: 30,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            '${d.isMonthly ? 'Monthly' : 'Weekly'} Report   |   $periodLabel',
            style: pw.TextStyle(fontSize: 13, color: _primarySoft),
          ),
          pw.SizedBox(height: 14),
          pw.Container(height: 0.75, color: _bandDivider),
          pw.SizedBox(height: 10),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Age during this period: ${_ageDuring(d)}',
                  style: smallStyle),
              pw.Text('Generated $generated', style: smallStyle),
            ],
          ),
        ],
      ),
    );
  }

  static String _periodLabel(_ReportData d) {
    if (d.isMonthly) {
      return DateFormat('MMMM yyyy').format(d.periodStart);
    }
    final endInclusive = DateTime(
        d.periodEnd.year, d.periodEnd.month, d.periodEnd.day - 1);
    final sameMonth = d.periodStart.month == endInclusive.month &&
        d.periodStart.year == endInclusive.year;
    final startFmt = sameMonth
        ? DateFormat('EEE d').format(d.periodStart)
        : DateFormat('EEE d MMM').format(d.periodStart);
    final endFmt = DateFormat('EEE d MMMM yyyy').format(endInclusive);
    return '$startFmt - $endFmt';
  }

  static String _ageDuring(_ReportData d) {
    final dob = DateTime(d.baby.dateOfBirth.year, d.baby.dateOfBirth.month,
        d.baby.dateOfBirth.day);
    // Age at the last elapsed day of the period (never a future date).
    var ref = DateTime(
        d.periodEnd.year, d.periodEnd.month, d.periodEnd.day - 1);
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    if (ref.isAfter(todayDate)) ref = todayDate;
    final days = daysBetween(dob, ref);
    if (days < 0) return 'not yet born';
    final months = days ~/ 30;
    final rem = days % 30;
    if (months <= 0) return '$days days';
    return '$months mo${rem > 0 ? ', $rem d' : ''}';
  }

  // -------------------------------------------------------------------
  // 2. At a glance
  // -------------------------------------------------------------------

  static List<pw.Widget> _atAGlanceSection(_ReportData d) {
    final cur = GlanceAggregates.of(
      feedings: d.feedings,
      sleeps: d.sleeps,
      diapers: d.diapers,
      tummyTimes: d.tummyTimes,
      reflux: d.reflux,
      healthLogs: d.healthLogs,
    );
    final prev = GlanceAggregates.of(
      feedings: d.prevFeedings,
      sleeps: d.prevSleeps,
      diapers: d.prevDiapers,
      tummyTimes: d.prevTummyTimes,
      reflux: d.prevReflux,
      healthLogs: d.prevHealthLogs,
    );
    final days = d.activeDays.toDouble();
    final prevDays = d.prevDays.toDouble();

    pw.Widget cell(
      String value,
      String label,
      double curMetric,
      double prevMetric, {
      bool downIsGood = false,
    }) {
      final delta = deltaLabel(curMetric, prevMetric);
      PdfColor deltaColor = _muted;
      if (delta.startsWith('+') || delta == 'new') {
        deltaColor = downIsGood ? _bad : _good;
      } else if (delta.startsWith('-')) {
        deltaColor = downIsGood ? _good : _bad;
      }
      return pw.Expanded(
        child: pw.Container(
          margin: const pw.EdgeInsets.symmetric(horizontal: 3),
          padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: pw.BoxDecoration(
            color: _cellFill,
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Column(
            children: [
              pw.Text(
                value,
                style: pw.TextStyle(
                  fontSize: 15,
                  fontWeight: pw.FontWeight.bold,
                  color: _ink,
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                label.toUpperCase(),
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: 6.5,
                  letterSpacing: 0.6,
                  color: _muted,
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                delta == 'no change' ? 'no change' : '$delta vs prev',
                style: pw.TextStyle(fontSize: 7, color: deltaColor),
              ),
            ],
          ),
        ),
      );
    }

    return [
      _sectionHeader('At a glance', _accentGlance),
      pw.Row(children: [
        cell(_num1(cur.feeds / days), 'Feeds / day', cur.feeds / days,
            prev.feeds / prevDays),
        cell(cur.avgMl == null ? '-' : '${cur.avgMl!.round()} ml',
            'Avg ml / feed', cur.avgMl ?? 0, prev.avgMl ?? 0),
        cell(_num1(cur.sleepMinutes / days / 60), 'Sleep h / day',
            cur.sleepMinutes / days, prev.sleepMinutes / prevDays),
        cell(
            cur.longestSleepMin > 0
                ? _hm(cur.longestSleepMin)
                : '-',
            'Longest sleep',
            cur.longestSleepMin.toDouble(),
            prev.longestSleepMin.toDouble()),
      ]),
      pw.SizedBox(height: 6),
      pw.Row(children: [
        cell(_num1(cur.nappies / days), 'Nappies / day', cur.nappies / days,
            prev.nappies / prevDays),
        cell(cur.tummyMinutes > 0 ? _hm(cur.tummyMinutes) : '-',
            'Tummy time total', cur.tummyMinutes / days,
            prev.tummyMinutes / prevDays),
        cell('${cur.refluxEvents}', 'Reflux events', cur.refluxEvents / days,
            prev.refluxEvents / prevDays,
            downIsGood: true),
        cell('${cur.medicineDoses}', 'Medicine doses',
            cur.medicineDoses / days, prev.medicineDoses / prevDays,
            downIsGood: true),
      ]),
      pw.SizedBox(height: 6),
      pw.Text(
        'Changes are compared with the previous '
        '${d.isMonthly ? 'calendar month' : 'week'} '
        '(${_rangeShort(d.prevStart, d.prevEnd)}), per-day rates.',
        style: pw.TextStyle(fontSize: 7.5, color: _muted),
      ),
    ];
  }

  // -------------------------------------------------------------------
  // 3. Feeding
  // -------------------------------------------------------------------

  static List<pw.Widget> _feedingSection(_ReportData d) {
    final widgets = <pw.Widget>[
      _sectionHeader('Feeding', _accentFeeding),
    ];
    if (d.feedings.isEmpty) {
      widgets.add(_noData('No feeds recorded this period.'));
      return widgets;
    }

    final stats = FeedingStats.fromRows(d.feedings);
    final counts = bucketTotals(
      d.feedings,
      timeField: 'logged_at',
      periodStart: d.periodStart,
      isMonthly: d.isMonthly,
      bucketCount: d.bucketCount,
    );

    widgets.add(_barChart(
      values: counts,
      labels: d.bucketLabels,
      color: _accentFeeding,
      format: (v) => v.round().toString(),
    ));
    widgets.add(pw.SizedBox(height: 4));
    widgets.add(_chartCaption(
        'Feeds per ${d.isMonthly ? 'week' : 'day'} this period'));
    widgets.add(pw.SizedBox(height: 10));

    // Busiest day.
    var busiest = '-';
    if (stats.busiestDay != null) {
      final dt = DateTime.tryParse(stats.busiestDay!);
      if (dt != null) {
        busiest = '${DateFormat('EEE d MMM').format(dt)} '
            '(${stats.busiestDayCount} feeds)';
      }
    }

    final avgMl =
        stats.avgMl == null ? '-' : '${stats.avgMl!.round()} ml';
    final avgQuality = stats.avgQuality == null
        ? '-'
        : '${stats.avgQuality!.toStringAsFixed(1)} / 5';
    final spitupRate = stats.spitUpRate == null
        ? '-'
        : '${(stats.spitUpRate! * 100).round()}%';

    widgets.add(_zebraTable(
      ['Total feeds', 'Avg / day', 'Avg amount', 'Avg quality',
          'Spit-up rate', 'Busiest day'],
      [
        [
          '${stats.total}',
          _num1(perDay(stats.total, d.activeDays)),
          avgMl,
          avgQuality,
          spitupRate,
          busiest,
        ],
      ],
    ));

    // One computed insight, only when the data genuinely supports it.
    if (stats.total >= 8 && stats.daypartCounts.isNotEmpty) {
      final top = stats.daypartCounts.entries
          .reduce((a, b) => a.value >= b.value ? a : b);
      final share = top.value / stats.total;
      if (share >= 0.35) {
        widgets.add(pw.SizedBox(height: 8));
        widgets.add(_insight(
          'Feeds were most frequent in the ${top.key} '
          '(${(share * 100).round()}% of all feeds).',
          _accentFeeding,
        ));
      }
    }
    return widgets;
  }

  // -------------------------------------------------------------------
  // 4. Sleep
  // -------------------------------------------------------------------

  static List<pw.Widget> _sleepSection(_ReportData d) {
    final widgets = <pw.Widget>[
      _sectionHeader('Sleep', _accentSleep),
    ];

    final stats = SleepStats.fromRows(d.sleeps);
    if (stats.stretchCount == 0) {
      widgets.add(_noData('No completed sleep sessions this period.'));
      return widgets;
    }

    final completed = d.sleeps.where((s) => s['end_time'] != null).toList();
    final hours = bucketTotals(
      completed,
      timeField: 'start_time',
      periodStart: d.periodStart,
      isMonthly: d.isMonthly,
      bucketCount: d.bucketCount,
      weight: (s) => sessionMinutes(s) / 60.0,
    );

    widgets.add(_barChart(
      values: hours,
      labels: d.bucketLabels,
      color: _accentSleep,
      format: (v) => v >= 10 ? v.round().toString() : v.toStringAsFixed(1),
    ));
    widgets.add(pw.SizedBox(height: 4));
    widgets.add(_chartCaption(
        'Hours of sleep per ${d.isMonthly ? 'week' : 'day'} this period'));
    widgets.add(pw.SizedBox(height: 10));

    widgets.add(_zebraTable(
      ['Total sleep', 'Avg / day', 'Longest stretch', 'Stretches / day',
          'Night (starts 19:00-07:00)', 'Day (starts 07:00-19:00)'],
      [
        [
          _hm(stats.totalMinutes),
          '${_num1(perDay(stats.totalMinutes, d.activeDays) / 60)} h',
          _hm(stats.longestMinutes),
          _num1(perDay(stats.stretchCount, d.activeDays)),
          '${_hm(stats.nightMinutes)} (${stats.nightPct}%)',
          '${_hm(stats.dayMinutes)} (${stats.dayPct}%)',
        ],
      ],
    ));
    widgets.add(pw.SizedBox(height: 4));
    widgets.add(pw.Text(
      'Each stretch counts as night or day by its start time; stretches '
      'crossing 19:00 or 07:00 are not split.',
      style: pw.TextStyle(fontSize: 7.5, color: _muted),
    ));
    return widgets;
  }

  // -------------------------------------------------------------------
  // 5. Nappies & digestion
  // -------------------------------------------------------------------

  static List<pw.Widget> _nappiesSection(_ReportData d) {
    final widgets = <pw.Widget>[
      _sectionHeader('Nappies & digestion', _accentNappies),
    ];

    if (d.diapers.isEmpty && d.journals.isEmpty) {
      widgets.add(_noData('No nappies or journal entries this period.'));
      return widgets;
    }

    final stats = NappyStats.fromRows(d.diapers);

    if (d.diapers.isNotEmpty) {
      // Wet = wet or both; dirty = dirty or both ('both' counts in each).
      double typeWeight(Map<String, dynamic> dp, String wanted) {
        final type = (dp['type'] ?? '').toString();
        return (type == wanted || type == 'both') ? 1 : 0;
      }

      final wet = bucketTotals(
        d.diapers,
        timeField: 'logged_at',
        periodStart: d.periodStart,
        isMonthly: d.isMonthly,
        bucketCount: d.bucketCount,
        weight: (dp) => typeWeight(dp, 'wet'),
      );
      final dirty = bucketTotals(
        d.diapers,
        timeField: 'logged_at',
        periodStart: d.periodStart,
        isMonthly: d.isMonthly,
        bucketCount: d.bucketCount,
        weight: (dp) => typeWeight(dp, 'dirty'),
      );

      widgets.add(_pairedBarChart(
        seriesA: wet,
        seriesB: dirty,
        labels: d.bucketLabels,
        colorA: _accentNappies,
        colorB: PdfColor.fromHex('#b8d4be'),
      ));
      widgets.add(pw.SizedBox(height: 4));
      widgets.add(pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          _legendSwatch(_accentNappies, 'Wet'),
          pw.SizedBox(width: 14),
          _legendSwatch(PdfColor.fromHex('#b8d4be'), 'Dirty'),
          pw.SizedBox(width: 14),
          pw.Text(
            'per ${d.isMonthly ? 'week' : 'day'}, "both" counts in each',
            style: pw.TextStyle(fontSize: 7.5, color: _muted),
          ),
        ],
      ));
      widgets.add(pw.SizedBox(height: 10));
    }

    // Stool type distribution (Bristol-style; column ships with Care Pack).
    final stoolCounts = stats.stoolTypeCounts;
    if (stoolCounts.isNotEmpty) {
      widgets.add(_zebraTable(
        ['Stool type', 'Description', 'Count'],
        [
          for (final type in stoolCounts.keys.toList()..sort())
            [
              'Type $type',
              _ascii(CarePackData.stoolTypes
                      .where((s) => s.value == type)
                      .map((s) => s.label)
                      .firstOrNull ??
                  '-'),
              '${stoolCounts[type]}',
            ],
        ],
        widths: {
          0: const pw.FixedColumnWidth(55),
          1: const pw.FlexColumnWidth(),
          2: const pw.FixedColumnWidth(40),
        },
      ));
      widgets.add(pw.SizedBox(height: 8));
    }

    // Cramps/gas from the daily journals (0-3 scale; >= 2 is notable).
    if (d.journals.isNotEmpty) {
      widgets.add(pw.Text(
        'Days with cramps or gas rated 2+ (on the 0-3 scale): '
        '${uncomfortableDayCount(d.journals)} of ${d.journals.length} '
        'journalled days.',
        style: pw.TextStyle(fontSize: 9, color: _ink),
      ));
    }
    return widgets;
  }

  // -------------------------------------------------------------------
  // 6. Reflux
  // -------------------------------------------------------------------

  static List<pw.Widget> _refluxSection(_ReportData d) {
    final widgets = <pw.Widget>[
      _sectionHeader('Reflux', _accentReflux),
    ];

    if (d.reflux.isEmpty && d.prevReflux.isEmpty) {
      widgets.add(_noData('No reflux events recorded this period.'));
      return widgets;
    }

    final stats = RefluxStats.fromRows(d.reflux);
    final counts = bucketTotals(
      d.reflux,
      timeField: 'logged_at',
      periodStart: d.periodStart,
      isMonthly: d.isMonthly,
      bucketCount: d.bucketCount,
    );

    widgets.add(_barChart(
      values: counts,
      labels: d.bucketLabels,
      color: _accentReflux,
      format: (v) => v.round().toString(),
    ));
    widgets.add(pw.SizedBox(height: 4));
    widgets.add(_chartCaption(
        'Reflux events per ${d.isMonthly ? 'week' : 'day'} this period'));
    widgets.add(pw.SizedBox(height: 10));

    if (d.reflux.isNotEmpty) {
      widgets.add(_zebraTable(
        ['Severity', 'Description', 'Events'],
        [
          for (final point in CarePackData.refluxSeverity)
            [
              '${point.value}',
              _ascii(point.label),
              '${stats.severityCounts[point.value] ?? 0}',
            ],
        ],
        widths: {
          0: const pw.FixedColumnWidth(48),
          1: const pw.FlexColumnWidth(),
          2: const pw.FixedColumnWidth(42),
        },
      ));
      widgets.add(pw.SizedBox(height: 8));

      final lines = <String>[
        'Painful episodes (crying with the event): ${stats.painfulCount} of '
            '${stats.total}.',
      ];
      if (stats.triggerCounts.isNotEmpty) {
        final top = stats.topTriggers;
        lines.add('Top noticed triggers: '
            '${top.take(3).map((e) => '${_ascii(e.key)} (${e.value})').join(', ')}.');
      }
      for (final line in lines) {
        widgets.add(pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: pw.Text(line, style: pw.TextStyle(fontSize: 9, color: _ink)),
        ));
      }
    }

    // Improving / worse vs the previous period (per-day rates).
    final curRate = perDay(d.reflux.length, d.activeDays);
    final prevRate = perDay(d.prevReflux.length, d.prevDays);
    String? statement;
    if (prevRate == 0 && curRate > 0) {
      statement = 'Reflux events appeared this period; none were recorded '
          'in the previous ${d.isMonthly ? 'month' : 'week'}.';
    } else if (prevRate > 0) {
      final pct = ((curRate - prevRate) / prevRate * 100).round();
      if (pct <= -10) {
        statement = 'Reflux is improving: ${_num1(curRate)}/day vs '
            '${_num1(prevRate)}/day in the previous period ($pct%).';
      } else if (pct >= 10) {
        statement = 'Reflux is more frequent: ${_num1(curRate)}/day vs '
            '${_num1(prevRate)}/day in the previous period (+$pct%).';
      } else {
        statement = 'Reflux is about the same as the previous period '
            '(${_num1(curRate)}/day vs ${_num1(prevRate)}/day).';
      }
    }
    if (statement != null) {
      widgets.add(pw.SizedBox(height: 5));
      widgets.add(_insight(statement, _accentReflux));
    }
    return widgets;
  }

  // -------------------------------------------------------------------
  // 7. Health & medicine
  // -------------------------------------------------------------------

  static List<pw.Widget> _healthSection(_ReportData d) {
    final widgets = <pw.Widget>[
      _sectionHeader('Health & medicine', _accentHealth),
    ];

    final temps = d.healthLogs
        .where((h) => h['temperature_c'] != null)
        .toList();
    final doseCount = medicationDoseCount(d.healthLogs);

    if (temps.isEmpty && doseCount == 0 && d.medications.isEmpty) {
      widgets.add(_noData(
          'No temperature readings or medicine doses this period.'));
      return widgets;
    }

    // Temperature readings.
    if (temps.isNotEmpty) {
      widgets.add(_subLabel('Temperature readings'));
      widgets.add(_zebraTable(
        ['Date', 'Time', 'Temp (C)', 'Status', 'Symptoms'],
        [
          for (final h in temps)
            [
              _fmtDate(parseTimestamp(h['logged_at'])),
              _fmtTime(parseTimestamp(h['logged_at'])),
              '${h['temperature_c']}',
              temperatureStatus((h['temperature_c'] as num).toDouble()),
              _orDash(h['symptoms']),
            ],
        ],
      ));
      widgets.add(pw.SizedBox(height: 10));
    }

    // Adherence math (expected = schedule x counted days) lives in
    // report_math so it is unit-tested; this just renders the rows.
    final adherence = MedicationAdherence.compute(
      catalog: d.medications,
      healthLogs: d.healthLogs,
      days: d.activeDays,
    );

    final scheduled = [
      for (final s in adherence.scheduled)
        [
          _ascii(s.name),
          '${s.frequencyPerDay}x / day',
          '${s.given} of ${s.expected}',
          s.adherence == null ? '-' : '${(s.adherence! * 100).round()}%',
          _orDash(s.source['default_dosage'] ?? s.source['instructions']),
        ],
    ];
    final asNeeded = [
      for (final a in adherence.asNeeded)
        [
          _ascii(a.name),
          a.inCatalog ? 'As needed' : 'Not in catalog',
          '${a.given}',
          _orDash(a.source['default_dosage'] ?? a.source['instructions']),
        ],
    ];

    if (scheduled.isNotEmpty) {
      final isLive = DateTime.now().isBefore(d.periodEnd);
      widgets.add(_subLabel('Scheduled medication adherence'));
      widgets.add(_zebraTable(
        ['Medication', 'Schedule', 'Doses given', 'Adherence',
            'Default dose'],
        scheduled,
      ));
      widgets.add(pw.SizedBox(height: 4));
      widgets.add(pw.Text(
        'Expected doses = schedule x ${d.activeDays} '
        '${isLive ? 'day(s) elapsed so far in this period' : 'day(s) in this period'}.',
        style: pw.TextStyle(fontSize: 7.5, color: _muted),
      ));
      widgets.add(pw.SizedBox(height: 8));
    }
    if (asNeeded.isNotEmpty) {
      widgets.add(_subLabel('As-needed medicine'));
      widgets.add(_zebraTable(
        ['Medication', 'Type', 'Doses given', 'Default dose'],
        asNeeded,
      ));
    }
    if (scheduled.isEmpty && asNeeded.isEmpty && temps.isEmpty) {
      widgets.add(_noData('No medicine activity this period.'));
    }
    return widgets;
  }

  // -------------------------------------------------------------------
  // 8. Growth & development
  // -------------------------------------------------------------------

  static List<pw.Widget> _growthSection(_ReportData d) {
    final hasData = d.growth.isNotEmpty ||
        d.milestones.isNotEmpty ||
        d.immunisations.isNotEmpty;
    // Weekly reports only carry this section when something happened;
    // monthly reports always include it.
    if (!d.isMonthly && !hasData) return const [];

    final widgets = <pw.Widget>[
      pw.SizedBox(height: 20),
      _sectionHeader('Growth & development', _accentGrowth),
    ];
    if (!hasData) {
      widgets.add(_noData(
          'No measurements, milestones or immunisations this period.'));
      return widgets;
    }

    if (d.growth.isNotEmpty) {
      String withPercentile(dynamic value, String kind, DateTime? at) {
        if (value is! num) return '-';
        final v = value.toDouble();
        if (at == null) return _num1(v);
        final ageMonths =
            daysBetween(d.baby.dateOfBirth, at) / 30.44;
        if (ageMonths < 0 || ageMonths > 24.5) return _num1(v);
        final p = WhoGrowthData.getPercentiles(
          ageMonths: ageMonths,
          gender: d.baby.gender ?? 'boy',
          weightKg: kind == 'weight' ? v : null,
          heightCm: kind == 'height' ? v : null,
          headCm: kind == 'head' ? v : null,
        )[kind];
        return p == null ? _num1(v) : '${_num1(v)} (P${p.round()})';
      }

      widgets.add(_subLabel('Measurements (WHO percentiles)'));
      widgets.add(_zebraTable(
        ['Date', 'Weight (kg)', 'Height (cm)', 'Head (cm)'],
        [
          for (final g in d.growth)
            [
              _fmtDate(parseTimestamp(g['measured_at'])),
              withPercentile(g['weight_kg'], 'weight', parseTimestamp(g['measured_at'])),
              withPercentile(g['height_cm'], 'height', parseTimestamp(g['measured_at'])),
              withPercentile(g['head_cm'], 'head', parseTimestamp(g['measured_at'])),
            ],
        ],
      ));
      widgets.add(pw.SizedBox(height: 10));
    }

    if (d.milestones.isNotEmpty) {
      widgets.add(_subLabel('Milestones achieved'));
      for (final m in d.milestones) {
        final when = _fmtDate(parseTimestamp(m['achieved_at']));
        final category = _orDash(m['category']);
        widgets.add(_bullet(
          '${_ascii((m['title'] ?? '').toString())} - $when '
          '${category == '-' ? '' : '($category)'}',
          _accentGrowth,
        ));
      }
      widgets.add(pw.SizedBox(height: 8));
    }

    if (d.immunisations.isNotEmpty) {
      final names = {
        for (final visit in ImmunisationData.schedule)
          for (final v in visit.vaccines) v.key: v.name,
      };
      widgets.add(_subLabel('Immunisations given'));
      for (final imm in d.immunisations) {
        final key = (imm['vaccine_key'] ?? '').toString();
        final name = names[key] ?? key;
        final given = DateTime.tryParse((imm['given_on'] ?? '').toString());
        widgets.add(_bullet(
          '${_ascii(name)} - ${given == null ? '-' : DateFormat('EEE d MMM yyyy').format(given)}',
          _accentGrowth,
        ));
      }
    }
    return widgets;
  }

  // -------------------------------------------------------------------
  // 2b. Day by day - one ledger row per day, nothing escapes the report
  // -------------------------------------------------------------------

  static const _moodLabels = {
    'happy': 'Happy',
    'okay': 'Okay',
    'fussy': 'Fussy',
    'very_fussy': 'Very fussy',
  };

  static List<pw.Widget> _dayByDaySection(_ReportData d) {
    final ledger = dailyLedger(
      start: d.periodStart,
      days: d.activeDays,
      feedings: d.feedings,
      sleeps: d.sleeps,
      diapers: d.diapers,
      reflux: d.reflux,
      healthLogs: d.healthLogs,
      tummyTimes: d.tummyTimes,
      journals: d.journals,
    );
    if (ledger.every((l) => l.isEmpty)) return const [];

    return [
      _sectionHeader('Day by day', _accentGlance),
      _zebraTable(
        [
          'Date', 'Feeds', 'Milk (ml)', 'Sleep', 'Nappies', 'Reflux',
          'Medicine', 'Tummy', 'Mood',
        ],
        [
          for (final l in ledger)
            [
              DateFormat('EEE d MMM').format(l.day),
              l.feeds == 0 ? '-' : '${l.feeds}',
              l.milkMl == 0 ? '-' : '${l.milkMl.round()}',
              l.sleepMinutes == 0 ? '-' : _hm(l.sleepMinutes),
              l.nappies == 0 ? '-' : '${l.nappies}',
              l.refluxEvents == 0 ? '-' : '${l.refluxEvents}',
              l.medicineDoses == 0 ? '-' : '${l.medicineDoses}',
              l.tummyMinutes == 0 ? '-' : '${l.tummyMinutes}m',
              _moodLabels[l.mood] ?? '-',
            ],
        ],
      ),
      pw.SizedBox(height: 4),
      pw.Text(
        'Sleep and tummy time count on the day the session started. '
        'Mood comes from the daily journal.',
        style: pw.TextStyle(fontSize: 7.5, color: _muted),
      ),
      pw.SizedBox(height: 20),
    ];
  }

  // -------------------------------------------------------------------
  // 9. Journal highlights
  // -------------------------------------------------------------------

  static List<pw.Widget> _journalSection(_ReportData d) {
    final widgets = <pw.Widget>[
      _sectionHeader('Journal highlights', _accentJournal),
    ];
    if (d.journals.isEmpty) {
      widgets.add(_noData('No journal entries this period.'));
      return widgets;
    }

    // Mood distribution.
    const moodLabels = {
      'happy': 'Happy',
      'okay': 'Okay',
      'fussy': 'Fussy',
      'very_fussy': 'Very fussy',
    };
    final moods = moodCounts(d.journals);
    if (moods.isNotEmpty) {
      widgets.add(_subLabel(
          'Mood across ${d.journals.length} journalled day(s)'));
      widgets.add(pw.Row(
        children: [
          for (final entry in moodLabels.entries)
            pw.Expanded(
              child: pw.Container(
                margin: const pw.EdgeInsets.symmetric(horizontal: 3),
                padding: const pw.EdgeInsets.symmetric(vertical: 8),
                decoration: pw.BoxDecoration(
                  color: _cellFill,
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Column(
                  children: [
                    pw.Text(
                      '${moods[entry.key] ?? 0}',
                      style: pw.TextStyle(
                        fontSize: 13,
                        fontWeight: pw.FontWeight.bold,
                        color: _ink,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      entry.value,
                      style: pw.TextStyle(fontSize: 7.5, color: _muted),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ));
      widgets.add(pw.SizedBox(height: 10));
    }

    // The journal in full: every journalled day with everything written
    // that day, nothing summarised away.
    const fields = [
      ('activities', 'Playtime activities'),
      ('new_things', 'New things tried or noticed'),
      ('upsets', 'Upsets'),
      ('fussy_times', 'Fussy / crying times'),
      ('notes', 'Notes'),
    ];

    widgets.add(_subLabel('The journal, day by day'));
    for (final j in d.journals) {
      final date = DateTime.tryParse((j['journal_date'] ?? '').toString());
      final when =
          date == null ? '' : DateFormat('EEEE d MMMM').format(date);
      final mood = _moodLabels[(j['mood'] ?? '').toString()];
      final cramps = (j['cramps'] as num?)?.toInt();
      final gas = (j['gas'] as num?)?.toInt();
      final headline = [
        if (mood != null) 'Mood: $mood',
        if (cramps != null) 'Cramps $cramps/3',
        if (gas != null) 'Gas $gas/3',
      ].join('    ');

      final lines = <pw.Widget>[];
      for (final (key, label) in fields) {
        final text = _ascii((j[key] ?? '').toString().trim());
        if (text.isEmpty) continue;
        lines.add(pw.Padding(
          padding: const pw.EdgeInsets.only(top: 3),
          child: pw.RichText(
            text: pw.TextSpan(
              children: [
                pw.TextSpan(
                  text: '$label:  ',
                  style: pw.TextStyle(
                    fontSize: 8.5,
                    fontWeight: pw.FontWeight.bold,
                    color: _muted,
                  ),
                ),
                pw.TextSpan(
                  text: text,
                  style: pw.TextStyle(fontSize: 8.5, color: _ink),
                ),
              ],
            ),
          ),
        ));
      }

      widgets.add(pw.Container(
        width: double.infinity,
        margin: const pw.EdgeInsets.only(bottom: 6),
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: pw.BoxDecoration(
          color: _cellFill,
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  when,
                  style: pw.TextStyle(
                    fontSize: 9.5,
                    fontWeight: pw.FontWeight.bold,
                    color: _ink,
                  ),
                ),
                if (headline.isNotEmpty)
                  pw.Text(
                    headline,
                    style: pw.TextStyle(fontSize: 8.5, color: _muted),
                  ),
              ],
            ),
            if (lines.isEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 3),
                child: pw.Text(
                  'Nothing written this day.',
                  style: pw.TextStyle(
                      fontSize: 8.5,
                      color: _muted,
                      fontStyle: pw.FontStyle.italic),
                ),
              )
            else
              ...lines,
          ],
        ),
      ));
    }
    return widgets;
  }

  // -------------------------------------------------------------------
  // Layout building blocks
  // -------------------------------------------------------------------

  static pw.Widget _sectionHeader(String title, PdfColor accent) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.only(bottom: 5),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _rule, width: 0.75)),
      ),
      child: pw.Row(
        children: [
          pw.Container(
            width: 8,
            height: 8,
            decoration: pw.BoxDecoration(
              color: accent,
              borderRadius: pw.BorderRadius.circular(2),
            ),
          ),
          pw.SizedBox(width: 7),
          pw.Text(
            title.toUpperCase(),
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 1.2,
              color: _ink,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _subLabel(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 5),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
          color: _ink,
        ),
      ),
    );
  }

  static pw.Widget _noData(String message) {
    return pw.Text(message, style: pw.TextStyle(fontSize: 9, color: _muted));
  }

  static pw.Widget _chartCaption(String text) {
    return pw.Text(
      text,
      textAlign: pw.TextAlign.center,
      style: pw.TextStyle(fontSize: 7.5, color: _muted),
    );
  }

  static pw.Widget _insight(String text, PdfColor accent) {
    // Accent strip drawn as a nested container: the pdf package does not
    // allow a borderRadius together with a non-uniform Border.
    return pw.Container(
      width: double.infinity,
      decoration: pw.BoxDecoration(
        color: accent,
        borderRadius: pw.BorderRadius.circular(4),
      ),
      padding: const pw.EdgeInsets.only(left: 2.5),
      child: pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: pw.BoxDecoration(
          color: _zebra,
          borderRadius: const pw.BorderRadius.horizontal(
            right: pw.Radius.circular(4),
          ),
        ),
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: 9,
            fontStyle: pw.FontStyle.italic,
            color: _ink,
          ),
        ),
      ),
    );
  }

  static pw.Widget _bullet(String text, PdfColor accent) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 4,
            height: 4,
            margin: const pw.EdgeInsets.only(top: 3.5, right: 7, left: 1),
            decoration: pw.BoxDecoration(
              color: accent,
              borderRadius: pw.BorderRadius.circular(2),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              text,
              style: pw.TextStyle(fontSize: 9, color: _ink),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _legendSwatch(PdfColor color, String label) {
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Container(
          width: 7,
          height: 7,
          decoration: pw.BoxDecoration(
            color: color,
            borderRadius: pw.BorderRadius.circular(2),
          ),
        ),
        pw.SizedBox(width: 4),
        pw.Text(label, style: pw.TextStyle(fontSize: 7.5, color: _muted)),
      ],
    );
  }

  /// Zebra-striped table with a light purple header row.
  static pw.Widget _zebraTable(
    List<String> headers,
    List<List<String>> rows, {
    Map<int, pw.TableColumnWidth>? widths,
  }) {
    pw.Widget cell(String text, {bool header = false}) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        child: pw.Text(
          text,
          maxLines: 3,
          style: header
              ? pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                  color: _ink,
                )
              : pw.TextStyle(fontSize: 8.5, color: _ink),
        ),
      );
    }

    return pw.Table(
      columnWidths: widths,
      border: pw.TableBorder.all(color: _rule, width: 0.5),
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: _headerFill),
          children: [for (final h in headers) cell(h, header: true)],
        ),
        for (var i = 0; i < rows.length; i++)
          pw.TableRow(
            decoration:
                i.isOdd ? pw.BoxDecoration(color: _zebra) : null,
            children: [for (final c in rows[i]) cell(c)],
          ),
      ],
    );
  }

  static const double _chartHeight = 62;

  /// One bar per bucket, drawn with plain containers. Renders a baseline and
  /// "No data recorded" when every value is zero - never fabricates a bar.
  static pw.Widget _barChart({
    required List<double> values,
    required List<String> labels,
    required PdfColor color,
    required String Function(double) format,
  }) {
    final maxV = values.fold<double>(0, (m, v) => v > m ? v : m);

    final pw.Widget plot;
    if (maxV <= 0) {
      plot = pw.Container(
        height: _chartHeight + 12,
        alignment: pw.Alignment.center,
        decoration: pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: _rule, width: 0.75)),
        ),
        child: pw.Text('No data recorded',
            style: pw.TextStyle(fontSize: 8, color: _muted)),
      );
    } else {
      plot = pw.Container(
        height: _chartHeight + 12,
        decoration: pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: _rule, width: 0.75)),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            for (final v in values)
              pw.Expanded(
                child: pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.end,
                  children: [
                    if (v > 0)
                      pw.Text(format(v),
                          style: pw.TextStyle(fontSize: 6.5, color: _muted)),
                    pw.SizedBox(height: 2),
                    pw.Container(
                      height: v <= 0 ? 1.5 : (v / maxV) * _chartHeight,
                      margin:
                          const pw.EdgeInsets.symmetric(horizontal: 5),
                      decoration: pw.BoxDecoration(
                        color: v <= 0 ? _barEmpty : color,
                        borderRadius: const pw.BorderRadius.vertical(
                            top: pw.Radius.circular(2)),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }

    return pw.Column(
      children: [
        plot,
        pw.SizedBox(height: 3),
        pw.Row(
          children: [
            for (final label in labels)
              pw.Expanded(
                child: pw.Text(
                  label,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(fontSize: 7, color: _muted),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// Two side-by-side mini bars per bucket (wet vs dirty nappies).
  static pw.Widget _pairedBarChart({
    required List<double> seriesA,
    required List<double> seriesB,
    required List<String> labels,
    required PdfColor colorA,
    required PdfColor colorB,
  }) {
    var maxV = 0.0;
    for (final v in [...seriesA, ...seriesB]) {
      if (v > maxV) maxV = v;
    }

    if (maxV <= 0) {
      return _barChart(
        values: seriesA,
        labels: labels,
        color: colorA,
        format: (v) => v.round().toString(),
      );
    }

    pw.Widget bar(double v, PdfColor color) {
      return pw.Expanded(
        child: pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.end,
          children: [
            if (v > 0)
              pw.Text('${v.round()}',
                  style: pw.TextStyle(fontSize: 6, color: _muted)),
            pw.SizedBox(height: 1.5),
            pw.Container(
              height: v <= 0 ? 1.5 : (v / maxV) * _chartHeight,
              margin: const pw.EdgeInsets.symmetric(horizontal: 1.5),
              decoration: pw.BoxDecoration(
                color: v <= 0 ? _barEmpty : color,
                borderRadius: const pw.BorderRadius.vertical(
                    top: pw.Radius.circular(2)),
              ),
            ),
          ],
        ),
      );
    }

    return pw.Column(
      children: [
        pw.Container(
          height: _chartHeight + 12,
          decoration: pw.BoxDecoration(
            border:
                pw.Border(bottom: pw.BorderSide(color: _rule, width: 0.75)),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < seriesA.length; i++)
                pw.Expanded(
                  child: pw.Padding(
                    padding:
                        const pw.EdgeInsets.symmetric(horizontal: 4),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        bar(seriesA[i], colorA),
                        bar(seriesB[i], colorB),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Row(
          children: [
            for (final label in labels)
              pw.Expanded(
                child: pw.Text(
                  label,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(fontSize: 7, color: _muted),
                ),
              ),
          ],
        ),
      ],
    );
  }

  // -------------------------------------------------------------------
  // Small helpers
  // -------------------------------------------------------------------

  /// Strips anything outside printable ASCII so the WinAnsi-encoded built-in
  /// fonts never receive emoji or other multi-byte characters.
  static String _ascii(String input) {
    final out = StringBuffer();
    for (final code in input.runes) {
      if (code == 0x0A || (code >= 0x20 && code <= 0x7E)) {
        out.writeCharCode(code);
      }
    }
    // Collapse whitespace runs created by stripped characters.
    return out
        .toString()
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
        .trim();
  }

  static String _orDash(dynamic value) {
    final s = _ascii(value?.toString() ?? '');
    return s.isEmpty ? '-' : s;
  }

  static String _fmtDate(DateTime? dt) =>
      dt == null ? '-' : DateFormat('EEE d MMM').format(dt);

  static String _fmtTime(DateTime? dt) =>
      dt == null ? '-' : DateFormat('HH:mm').format(dt);

  static String _rangeShort(DateTime start, DateTime end) {
    final endInclusive = DateTime(end.year, end.month, end.day - 1);
    return '${DateFormat('d MMM').format(start)} - '
        '${DateFormat('d MMM').format(endInclusive)}';
  }

  static String _num1(double v) {
    final s = v.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  static String _hm(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0) return m > 0 ? '${h}h ${m}m' : '${h}h';
    return '${m}m';
  }

}

// ---------------------------------------------------------------------
// Internal data holder
// ---------------------------------------------------------------------

class _ReportData {
  final Baby baby;
  final DateTime periodStart;
  final DateTime periodEnd;
  final DateTime prevStart;
  final DateTime prevEnd;
  final bool isMonthly;

  final List<Map<String, dynamic>> feedings;
  final List<Map<String, dynamic>> sleeps;
  final List<Map<String, dynamic>> diapers;
  final List<Map<String, dynamic>> reflux;
  final List<Map<String, dynamic>> journals;
  final List<Map<String, dynamic>> healthLogs;
  final List<Map<String, dynamic>> growth;
  final List<Map<String, dynamic>> tummyTimes;
  final List<Map<String, dynamic>> milestones;
  final List<Map<String, dynamic>> immunisations;
  final List<Map<String, dynamic>> medications;

  final List<Map<String, dynamic>> prevFeedings;
  final List<Map<String, dynamic>> prevSleeps;
  final List<Map<String, dynamic>> prevDiapers;
  final List<Map<String, dynamic>> prevReflux;
  final List<Map<String, dynamic>> prevHealthLogs;
  final List<Map<String, dynamic>> prevTummyTimes;

  _ReportData({
    required this.baby,
    required this.periodStart,
    required this.periodEnd,
    required this.prevStart,
    required this.prevEnd,
    required this.isMonthly,
    required this.feedings,
    required this.sleeps,
    required this.diapers,
    required this.reflux,
    required this.journals,
    required this.healthLogs,
    required this.growth,
    required this.tummyTimes,
    required this.milestones,
    required this.immunisations,
    required this.medications,
    required this.prevFeedings,
    required this.prevSleeps,
    required this.prevDiapers,
    required this.prevReflux,
    required this.prevHealthLogs,
    required this.prevTummyTimes,
  });

  /// Total calendar days in the period.
  int get totalDays => periodLengthDays(periodStart, periodEnd);

  /// The divisor for every "/ day" average: days elapsed so far when the
  /// period includes today, the full period length when it is in the past.
  int get activeDays =>
      divisorDays(periodStart: periodStart, periodEnd: periodEnd);

  int get prevDays => periodLengthDays(prevStart, prevEnd);

  /// Weekly: 7 day buckets. Monthly: W1..W5 week buckets.
  int get bucketCount => bucketCountFor(
      periodStart: periodStart, periodEnd: periodEnd, isMonthly: isMonthly);

  List<String> get bucketLabels {
    if (!isMonthly) {
      return [
        for (var i = 0; i < 7; i++)
          DateFormat('EEE').format(DateTime(
              periodStart.year, periodStart.month, periodStart.day + i)),
      ];
    }
    return [for (var i = 1; i <= bucketCount; i++) 'W$i'];
  }
}
