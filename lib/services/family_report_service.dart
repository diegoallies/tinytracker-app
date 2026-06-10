import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/baby.dart';
import '../utils/care_pack_data.dart';
import '../utils/immunisation_data.dart';
import '../utils/who_growth_data.dart';
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
            dateOnly ? _dateKey(start) : start.toUtc().toIso8601String();
        final until = dateOnly ? _dateKey(end) : end.toUtc().toIso8601String();
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
    final days = _daysBetween(dob, ref);
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
    final cur = _Aggregates.of(d.feedings, d.sleeps, d.diapers, d.tummyTimes,
        d.reflux, d.healthLogs);
    final prev = _Aggregates.of(d.prevFeedings, d.prevSleeps, d.prevDiapers,
        d.prevTummyTimes, d.prevReflux, d.prevHealthLogs);
    final days = d.activeDays.toDouble();
    final prevDays = d.prevDays.toDouble();

    pw.Widget cell(
      String value,
      String label,
      double curMetric,
      double prevMetric, {
      bool downIsGood = false,
    }) {
      final delta = _delta(curMetric, prevMetric);
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

    // Per-bucket feed counts.
    final counts = List<double>.filled(d.bucketCount, 0);
    final perDay = <String, int>{};
    final hourBuckets = <String, int>{};
    final mlValues = <double>[];
    final qualityValues = <double>[];
    var spitupKnown = 0;
    var spitupYes = 0;

    for (final f in d.feedings) {
      final dt = _ts(f['logged_at']);
      if (dt == null) continue;
      counts[d.bucketOf(dt)] += 1;
      perDay.update(_dateKey(dt), (v) => v + 1, ifAbsent: () => 1);
      final daypart = _daypartOf(dt.hour);
      hourBuckets.update(daypart, (v) => v + 1, ifAbsent: () => 1);
      final ml = f['amount_ml'];
      if (ml is num) mlValues.add(ml.toDouble());
      final q = f['quality'];
      if (q is num) qualityValues.add(q.toDouble());
      if (f.containsKey('had_spitup') && f['had_spitup'] is bool) {
        spitupKnown++;
        if (f['had_spitup'] == true) spitupYes++;
      }
    }

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
    String busiest = '-';
    var busiestCount = 0;
    perDay.forEach((day, c) {
      if (c > busiestCount) {
        busiestCount = c;
        busiest = day;
      }
    });
    if (busiestCount > 0) {
      final dt = DateTime.tryParse(busiest);
      if (dt != null) {
        busiest =
            '${DateFormat('EEE d MMM').format(dt)} ($busiestCount feeds)';
      }
    }

    final avgMl = mlValues.isEmpty
        ? '-'
        : '${(mlValues.reduce((a, b) => a + b) / mlValues.length).round()} ml';
    final avgQuality = qualityValues.isEmpty
        ? '-'
        : '${(qualityValues.reduce((a, b) => a + b) / qualityValues.length).toStringAsFixed(1)} / 5';
    final spitupRate = spitupKnown == 0
        ? '-'
        : '${(spitupYes / spitupKnown * 100).round()}%';

    widgets.add(_zebraTable(
      ['Total feeds', 'Avg / day', 'Avg amount', 'Avg quality',
          'Spit-up rate', 'Busiest day'],
      [
        [
          '${d.feedings.length}',
          _num1(d.feedings.length / d.activeDays),
          avgMl,
          avgQuality,
          spitupRate,
          busiest,
        ],
      ],
    ));

    // One computed insight, only when the data genuinely supports it.
    if (d.feedings.length >= 8 && hourBuckets.isNotEmpty) {
      final top = hourBuckets.entries
          .reduce((a, b) => a.value >= b.value ? a : b);
      final share = top.value / d.feedings.length;
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

  static String _daypartOf(int hour) {
    if (hour >= 6 && hour < 12) return 'morning';
    if (hour >= 12 && hour < 18) return 'afternoon';
    if (hour >= 18) return 'evening';
    return 'night';
  }

  // -------------------------------------------------------------------
  // 4. Sleep
  // -------------------------------------------------------------------

  static List<pw.Widget> _sleepSection(_ReportData d) {
    final widgets = <pw.Widget>[
      _sectionHeader('Sleep', _accentSleep),
    ];

    final completed = d.sleeps.where((s) => s['end_time'] != null).toList();
    if (completed.isEmpty) {
      widgets.add(_noData('No completed sleep sessions this period.'));
      return widgets;
    }

    final hours = List<double>.filled(d.bucketCount, 0);
    var totalMin = 0;
    var longestMin = 0;
    var nightMin = 0;
    var dayMin = 0;

    for (final s in completed) {
      final start = _ts(s['start_time']);
      if (start == null) continue;
      var mins = (s['duration_minutes'] as num?)?.toInt() ?? 0;
      if (mins <= 0) {
        final end = _ts(s['end_time']);
        if (end != null) mins = end.difference(start).inMinutes;
      }
      if (mins <= 0) continue;
      hours[d.bucketOf(start)] += mins / 60.0;
      totalMin += mins;
      if (mins > longestMin) longestMin = mins;
      // Night vs day attribution by session start (19:00 - 07:00 = night).
      if (start.hour >= 19 || start.hour < 7) {
        nightMin += mins;
      } else {
        dayMin += mins;
      }
    }

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

    final splitTotal = nightMin + dayMin;
    final nightPct =
        splitTotal == 0 ? 0 : (nightMin / splitTotal * 100).round();
    widgets.add(_zebraTable(
      ['Total sleep', 'Avg / day', 'Longest stretch', 'Stretches / day',
          'Night (19:00-07:00)', 'Day (07:00-19:00)'],
      [
        [
          _hm(totalMin),
          '${_num1(totalMin / d.activeDays / 60)} h',
          _hm(longestMin),
          _num1(completed.length / d.activeDays),
          '${_hm(nightMin)} ($nightPct%)',
          '${_hm(dayMin)} (${splitTotal == 0 ? 0 : 100 - nightPct}%)',
        ],
      ],
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

    if (d.diapers.isNotEmpty) {
      // Wet = wet or both; dirty = dirty or both (matches weeklyMetrics).
      final wet = List<double>.filled(d.bucketCount, 0);
      final dirty = List<double>.filled(d.bucketCount, 0);
      for (final dp in d.diapers) {
        final dt = _ts(dp['logged_at']);
        if (dt == null) continue;
        final b = d.bucketOf(dt);
        final type = (dp['type'] ?? '').toString();
        if (type != 'dirty') wet[b] += 1;
        if (type != 'wet') dirty[b] += 1;
      }

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
    final stoolCounts = <int, int>{};
    for (final dp in d.diapers) {
      final t = dp['stool_type'];
      if (t is int) stoolCounts.update(t, (v) => v + 1, ifAbsent: () => 1);
    }
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
      final uncomfortable = <String>{};
      for (final j in d.journals) {
        final cramps = (j['cramps'] as num?)?.toInt() ?? 0;
        final gas = (j['gas'] as num?)?.toInt() ?? 0;
        if (cramps >= 2 || gas >= 2) {
          uncomfortable.add((j['journal_date'] ?? '').toString());
        }
      }
      widgets.add(pw.Text(
        'Days with cramps or gas rated 2+ (on the 0-3 scale): '
        '${uncomfortable.length} of ${d.journals.length} journalled days.',
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

    final counts = List<double>.filled(d.bucketCount, 0);
    final severityCounts = <int, int>{};
    final triggers = <String, int>{};
    var painful = 0;
    for (final r in d.reflux) {
      final dt = _ts(r['logged_at']);
      if (dt != null) counts[d.bucketOf(dt)] += 1;
      final sev = r['severity'];
      if (sev is int) {
        severityCounts.update(sev, (v) => v + 1, ifAbsent: () => 1);
      }
      if (r['painful_crying'] == true) painful++;
      final trigger =
          _ascii((r['trigger_noticed'] ?? '').toString().trim().toLowerCase());
      if (trigger.isNotEmpty) {
        triggers.update(trigger, (v) => v + 1, ifAbsent: () => 1);
      }
    }

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
              '${severityCounts[point.value] ?? 0}',
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
        'Painful episodes (crying with the event): $painful of '
            '${d.reflux.length}.',
      ];
      if (triggers.isNotEmpty) {
        final top = triggers.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        lines.add('Top noticed triggers: '
            '${top.take(3).map((e) => '${e.key} (${e.value})').join(', ')}.');
      }
      for (final line in lines) {
        widgets.add(pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: pw.Text(line, style: pw.TextStyle(fontSize: 9, color: _ink)),
        ));
      }
    }

    // Improving / worse vs the previous period (per-day rates).
    final curRate = d.reflux.length / d.activeDays;
    final prevRate = d.prevReflux.length / d.prevDays;
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
    final doses = d.healthLogs
        .where((h) =>
            (h['medication'] ?? '').toString().trim().isNotEmpty)
        .toList();

    if (temps.isEmpty && doses.isEmpty && d.medications.isEmpty) {
      widgets.add(_noData(
          'No temperature readings or medicine doses this period.'));
      return widgets;
    }

    // Temperature readings.
    if (temps.isNotEmpty) {
      String status(double t) {
        if (t < 36) return 'Low';
        if (t <= 37.5) return 'Normal';
        if (t <= 38.5) return 'Fever';
        return 'High fever';
      }

      widgets.add(_subLabel('Temperature readings'));
      widgets.add(_zebraTable(
        ['Date', 'Time', 'Temp (C)', 'Status', 'Symptoms'],
        [
          for (final h in temps)
            [
              _fmtDate(_ts(h['logged_at'])),
              _fmtTime(_ts(h['logged_at'])),
              '${h['temperature_c']}',
              status((h['temperature_c'] as num).toDouble()),
              _orDash(h['symptoms']),
            ],
        ],
      ));
      widgets.add(pw.SizedBox(height: 10));
    }

    // Doses given in this period, grouped by lowercased medication name.
    final givenByName = <String, int>{};
    for (final h in doses) {
      final name = (h['medication'] as String).trim().toLowerCase();
      givenByName.update(name, (v) => v + 1, ifAbsent: () => 1);
    }

    final scheduled = <List<String>>[];
    final asNeeded = <List<String>>[];
    final matchedNames = <String>{};
    for (final m in d.medications) {
      final name = (m['name'] ?? '').toString();
      if (name.trim().isEmpty) continue;
      final key = name.trim().toLowerCase();
      matchedNames.add(key);
      final given = givenByName[key] ?? 0;
      final freq = (m['frequency_per_day'] as num?)?.toInt();
      final isAsNeeded = m['as_needed'] == true || freq == null || freq <= 0;
      final dose = _orDash(m['default_dosage'] ?? m['instructions']);
      if (isAsNeeded) {
        asNeeded.add([_ascii(name), 'As needed', '$given', dose]);
      } else {
        final expected = freq * d.activeDays;
        final pct =
            expected == 0 ? '-' : '${(given / expected * 100).round()}%';
        scheduled.add([
          _ascii(name),
          '${freq}x / day',
          '$given of $expected',
          pct,
          dose,
        ]);
      }
    }
    // Doses logged for meds not in the catalog still deserve a row.
    givenByName.forEach((key, count) {
      if (!matchedNames.contains(key)) {
        asNeeded.add([_ascii(key), 'Not in catalog', '$count', '-']);
      }
    });

    if (scheduled.isNotEmpty) {
      widgets.add(_subLabel('Scheduled medication adherence'));
      widgets.add(_zebraTable(
        ['Medication', 'Schedule', 'Doses given', 'Adherence',
            'Default dose'],
        scheduled,
      ));
      widgets.add(pw.SizedBox(height: 4));
      widgets.add(pw.Text(
        'Expected doses = schedule x ${d.activeDays} elapsed day(s) in '
        'this period.',
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
            _daysBetween(d.baby.dateOfBirth, at) / 30.44;
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
              _fmtDate(_ts(g['measured_at'])),
              withPercentile(g['weight_kg'], 'weight', _ts(g['measured_at'])),
              withPercentile(g['height_cm'], 'height', _ts(g['measured_at'])),
              withPercentile(g['head_cm'], 'head', _ts(g['measured_at'])),
            ],
        ],
      ));
      widgets.add(pw.SizedBox(height: 10));
    }

    if (d.milestones.isNotEmpty) {
      widgets.add(_subLabel('Milestones achieved'));
      for (final m in d.milestones) {
        final when = _fmtDate(_ts(m['achieved_at']));
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
    final moodCounts = <String, int>{};
    for (final j in d.journals) {
      final mood = (j['mood'] ?? '').toString();
      if (moodLabels.containsKey(mood)) {
        moodCounts.update(mood, (v) => v + 1, ifAbsent: () => 1);
      }
    }
    if (moodCounts.isNotEmpty) {
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
                      '${moodCounts[entry.key] ?? 0}',
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

    // Up to 6 "new things" / notable activities, quoted.
    final highlights = <(String, String)>[];
    for (final j in d.journals) {
      final date = DateTime.tryParse((j['journal_date'] ?? '').toString());
      final when = date == null ? '' : DateFormat('EEE d MMM').format(date);
      for (final field in ['new_things', 'activities']) {
        final text = _ascii((j[field] ?? '').toString().trim());
        if (text.isNotEmpty) highlights.add((text, when));
      }
    }
    if (highlights.isNotEmpty) {
      final seen = <String>{};
      var added = 0;
      widgets.add(_subLabel('New things & notable moments'));
      for (final (text, dateLabel) in highlights) {
        if (added >= 6) break;
        if (!seen.add(text.toLowerCase())) continue;
        widgets.add(_bullet(
          '"${_truncate(text, 160)}"${dateLabel.isEmpty ? '' : ' - $dateLabel'}',
          _accentJournal,
        ));
        added++;
      }
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

  static String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max - 3)}...';

  static String _orDash(dynamic value) {
    final s = _ascii(value?.toString() ?? '');
    return s.isEmpty ? '-' : s;
  }

  static DateTime? _ts(dynamic raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString())?.toLocal();
  }

  static String _fmtDate(DateTime? dt) =>
      dt == null ? '-' : DateFormat('EEE d MMM').format(dt);

  static String _fmtTime(DateTime? dt) =>
      dt == null ? '-' : DateFormat('HH:mm').format(dt);

  static String _dateKey(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

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

  /// Calendar-day difference. Hour-rounded so DST shifts cannot drop a day.
  static int _daysBetween(DateTime a, DateTime b) {
    final from = DateTime(a.year, a.month, a.day);
    final to = DateTime(b.year, b.month, b.day);
    return ((to.difference(from).inHours) + 12) ~/ 24;
  }

  /// '+12%' / '-8%' / 'no change' / 'new' against the previous period.
  static String _delta(double current, double previous) {
    if (previous <= 0 && current <= 0) return 'no change';
    if (previous <= 0) return 'new';
    final pct = ((current - previous) / previous * 100).round();
    if (pct == 0) return 'no change';
    return '${pct > 0 ? '+' : ''}$pct%';
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
  int get totalDays =>
      FamilyReportService._daysBetween(periodStart, periodEnd);

  /// Days of the period that have actually happened - averages divide by
  /// this so a report generated mid-week never under-reports the rates.
  int get activeDays {
    final now = DateTime.now();
    if (!now.isBefore(periodEnd)) return totalDays.clamp(1, 366);
    final elapsed =
        FamilyReportService._daysBetween(periodStart, now) + 1;
    return elapsed.clamp(1, totalDays.clamp(1, 366));
  }

  int get prevDays =>
      FamilyReportService._daysBetween(prevStart, prevEnd).clamp(1, 366);

  /// Weekly: 7 day buckets. Monthly: W1..W5 week buckets.
  int get bucketCount =>
      isMonthly ? ((totalDays - 1) ~/ 7) + 1 : 7;

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

  int bucketOf(DateTime dt) {
    final dayIndex = FamilyReportService._daysBetween(periodStart, dt);
    if (!isMonthly) return dayIndex.clamp(0, 6);
    return (dayIndex ~/ 7).clamp(0, bucketCount - 1);
  }
}

// ---------------------------------------------------------------------
// Aggregates for the "At a glance" grid (computed identically for the
// current and the previous period so the deltas compare like with like).
// ---------------------------------------------------------------------

class _Aggregates {
  final int feeds;
  final double? avgMl;
  final int sleepMinutes;
  final int longestSleepMin;
  final int nappies;
  final int tummyMinutes;
  final int refluxEvents;
  final int medicineDoses;

  _Aggregates({
    required this.feeds,
    required this.avgMl,
    required this.sleepMinutes,
    required this.longestSleepMin,
    required this.nappies,
    required this.tummyMinutes,
    required this.refluxEvents,
    required this.medicineDoses,
  });

  static _Aggregates of(
    List<Map<String, dynamic>> feedings,
    List<Map<String, dynamic>> sleeps,
    List<Map<String, dynamic>> diapers,
    List<Map<String, dynamic>> tummyTimes,
    List<Map<String, dynamic>> reflux,
    List<Map<String, dynamic>> healthLogs,
  ) {
    final mlValues = [
      for (final f in feedings)
        if (f['amount_ml'] is num) (f['amount_ml'] as num).toDouble(),
    ];

    var sleepMin = 0;
    var longest = 0;
    for (final s in sleeps) {
      if (s['end_time'] == null) continue;
      var mins = (s['duration_minutes'] as num?)?.toInt() ?? 0;
      if (mins <= 0) {
        final start = FamilyReportService._ts(s['start_time']);
        final end = FamilyReportService._ts(s['end_time']);
        if (start != null && end != null) {
          mins = end.difference(start).inMinutes;
        }
      }
      if (mins <= 0) continue;
      sleepMin += mins;
      if (mins > longest) longest = mins;
    }

    final tummyMin = tummyTimes.fold<int>(
        0, (sum, t) => sum + ((t['duration_minutes'] as num?)?.toInt() ?? 0));

    final doses = healthLogs
        .where(
            (h) => (h['medication'] ?? '').toString().trim().isNotEmpty)
        .length;

    return _Aggregates(
      feeds: feedings.length,
      avgMl: mlValues.isEmpty
          ? null
          : mlValues.reduce((a, b) => a + b) / mlValues.length,
      sleepMinutes: sleepMin,
      longestSleepMin: longest,
      nappies: diapers.length,
      tummyMinutes: tummyMin,
      refluxEvents: reflux.length,
      medicineDoses: doses,
    );
  }
}
