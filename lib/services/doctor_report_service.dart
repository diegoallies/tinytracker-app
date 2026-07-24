import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/baby.dart';
import '../utils/care_pack_data.dart';
import 'report_math.dart';
import 'supabase_service.dart';

/// Builds the "Doctor Visit Report" PDF: a clinical summary of the last
/// 14 days of reflux, digestion, feeding, temperature and medication data,
/// styled with the same design system as the family report (ink cover band,
/// accent-square section headers, zebra tables, running footer).
///
/// Pure data - no AI calls. Tables that ship with the Care Pack migration
/// (reflux_events, daily_journals) or columns that ship with it (stool_type,
/// quality) may not exist yet; every query degrades to an empty section
/// instead of crashing. All arithmetic is delegated to the unit-tested
/// functions in report_math.dart.
class DoctorReportService {
  DoctorReportService._();

  static const int _days = 14;

  // -------------------------------------------------------------------
  // Palette: shared with the family report design system.
  // -------------------------------------------------------------------
  static final PdfColor _primary = PdfColor.fromHex('#9b72cf');
  static final PdfColor _primarySoft = PdfColor.fromHex('#b89ce0');
  static final PdfColor _ink = PdfColor.fromHex('#2d2640');
  static final PdfColor _muted = PdfColor.fromHex('#8b85a0');
  static final PdfColor _rule = PdfColor.fromHex('#ddd6e8');
  static final PdfColor _zebra = PdfColor.fromHex('#f5f3f8');
  static final PdfColor _headerFill = PdfColor.fromHex('#ede4f7');
  static final PdfColor _bandDivider = PdfColor.fromHex('#463d5c');
  static final PdfColor _lavender = PdfColor.fromHex('#c9b8e8');

  // Section accents (exactly one per section header).
  static final PdfColor _accentReflux = PdfColor.fromHex('#cf6a5e');
  static final PdfColor _accentDigestion = PdfColor.fromHex('#5fa46b');
  static final PdfColor _accentFeeding = PdfColor.fromHex('#e09c3f');
  static final PdfColor _accentHealth = PdfColor.fromHex('#46a5a0');

  // -------------------------------------------------------------------
  // Entry point
  // -------------------------------------------------------------------

  static Future<Uint8List> build({required Baby baby}) async {
    final now = DateTime.now();
    // 14 calendar days, inclusive of today.
    final start = DateTime(now.year, now.month, now.day - (_days - 1));
    final startIso = start.toUtc().toIso8601String();
    final client = SupabaseService.client;

    // Each query selects '*' so a missing column never fails the request,
    // and catches everything so a missing table degrades to an empty section.
    Future<List<Map<String, dynamic>>> rows(
      String table,
      String timeCol,
      String sinceValue,
    ) async {
      try {
        final data = await client
            .from(table)
            .select('*')
            .eq('baby_id', baby.id)
            .isFilter('deleted_at', null)
            .gte(timeCol, sinceValue)
            .order(timeCol, ascending: true);
        return List<Map<String, dynamic>>.from(data);
      } catch (_) {
        return const [];
      }
    }

    final results = await Future.wait([
      rows('reflux_events', 'logged_at', startIso),
      rows('daily_journals', 'journal_date', dayKey(start)),
      rows('diapers', 'logged_at', startIso),
      rows('health_logs', 'logged_at', startIso),
      rows('feedings', 'logged_at', startIso),
    ]);

    return _buildPdf(
      baby: baby,
      start: start,
      end: now,
      reflux: results[0],
      journals: results[1],
      diapers: results[2],
      healthLogs: results[3],
      feedings: results[4],
    );
  }

  // ---------------------------------------------------------------------
  // PDF assembly
  // ---------------------------------------------------------------------

  static Future<Uint8List> _buildPdf({
    required Baby baby,
    required DateTime start,
    required DateTime end,
    required List<Map<String, dynamic>> reflux,
    required List<Map<String, dynamic>> journals,
    required List<Map<String, dynamic>> diapers,
    required List<Map<String, dynamic>> healthLogs,
    required List<Map<String, dynamic>> feedings,
  }) async {
    final pdf = pw.Document();
    final periodLabel = '${DateFormat('d MMM').format(start)} - '
        '${DateFormat('d MMM yyyy').format(end)}';
    final footerText = _ascii('TinyTrack - ${baby.name} - $periodLabel');

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
                      'TinyTrack Doctor Visit Report',
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: _ink,
                      ),
                    ),
                    pw.Text(
                      _ascii('${baby.name} - $periodLabel'),
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
          _coverBand(baby, periodLabel),
          pw.SizedBox(height: 22),
          ..._refluxSection(reflux),
          pw.SizedBox(height: 20),
          ..._digestionSection(diapers, journals),
          pw.SizedBox(height: 20),
          ..._feedingSection(feedings),
          pw.SizedBox(height: 20),
          ..._healthSection(healthLogs),
        ],
      ),
    );

    return pdf.save();
  }

  // -------------------------------------------------------------------
  // Cover band (ink variant with a clinical subline)
  // -------------------------------------------------------------------

  static pw.Widget _coverBand(Baby baby, String periodLabel) {
    final generated = DateFormat('d MMMM yyyy, HH:mm').format(DateTime.now());
    final dob = DateFormat('d MMMM yyyy').format(baby.dateOfBirth);
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
                'TINYTRACK DOCTOR VISIT REPORT',
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
            _ascii(baby.name),
            style: pw.TextStyle(
              fontSize: 30,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'Clinical summary   |   Last $_days days   |   $periodLabel',
            style: pw.TextStyle(fontSize: 13, color: _primarySoft),
          ),
          pw.SizedBox(height: 14),
          pw.Container(height: 0.75, color: _bandDivider),
          pw.SizedBox(height: 10),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                _ascii('DOB $dob   |   Age ${baby.ageDisplay}'),
                style: smallStyle,
              ),
              pw.Text('Generated $generated', style: smallStyle),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // 1. Reflux
  // ---------------------------------------------------------------------

  static List<pw.Widget> _refluxSection(List<Map<String, dynamic>> reflux) {
    final widgets = <pw.Widget>[
      _sectionHeader('Reflux', _accentReflux),
    ];

    if (reflux.isEmpty) {
      widgets.add(_noData('No reflux events recorded in the last $_days '
          'days.'));
      return widgets;
    }

    final stats = RefluxStats.fromRows(reflux);
    final avg = perDay(stats.total, _days).toStringAsFixed(1);
    var worst = '-';
    if (stats.worstDay != null) {
      final dt = DateTime.tryParse(stats.worstDay!);
      if (dt != null) {
        worst = '${DateFormat('EEE d MMM').format(dt)} '
            '(${stats.worstDayCount} events)';
      }
    }

    widgets.add(pw.Text(
      '${stats.total} events in $_days days - avg $avg/day - '
      'painful (crying): ${stats.painfulCount} - worst day: $worst.',
      style: pw.TextStyle(fontSize: 9, color: _ink),
    ));
    widgets.add(pw.SizedBox(height: 8));

    widgets.add(_zebraTable(
      ['Date', 'Time', 'Severity (1-5)', 'Painful', 'Arching', 'Trigger'],
      [
        for (final r in reflux)
          [
            _fmtDate(parseTimestamp(r['logged_at'])),
            _fmtTime(parseTimestamp(r['logged_at'])),
            (r['severity'] ?? '-').toString(),
            r['painful_crying'] == true ? 'Yes' : '-',
            r['arching_back'] == true ? 'Yes' : '-',
            _orDash(r['trigger_noticed']),
          ],
      ],
    ));

    // Severity scale legend with this fortnight's distribution.
    widgets.add(pw.SizedBox(height: 8));
    widgets.add(_subLabel('Severity scale'));
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

    if (stats.triggerCounts.isNotEmpty) {
      final top = stats.topTriggers;
      widgets.add(pw.SizedBox(height: 6));
      widgets.add(pw.Text(
        'Top noticed triggers: '
        '${top.take(3).map((e) => '${_ascii(e.key)} (${e.value})').join(', ')}.',
        style: pw.TextStyle(fontSize: 9, color: _ink),
      ));
    }
    return widgets;
  }

  // ---------------------------------------------------------------------
  // 2. Digestion
  // ---------------------------------------------------------------------

  static List<pw.Widget> _digestionSection(
    List<Map<String, dynamic>> diapers,
    List<Map<String, dynamic>> journals,
  ) {
    final widgets = <pw.Widget>[
      _sectionHeader('Digestion', _accentDigestion),
    ];

    if (diapers.isEmpty && journals.isEmpty) {
      widgets.add(_noData('No nappies or journal entries in the last '
          '$_days days.'));
      return widgets;
    }

    final stats = NappyStats.fromRows(diapers);
    widgets.add(pw.Text(
      '${stats.dirtyCount} dirty nappies in $_days days - avg '
      '${perDay(stats.dirtyCount, _days).toStringAsFixed(1)}/day - '
      '${stats.wetCount} wet ("both" counts in each).',
      style: pw.TextStyle(fontSize: 9, color: _ink),
    ));

    // Stool type distribution (Bristol-style 1-7, post-migration column).
    if (stats.stoolTypeCounts.isNotEmpty) {
      widgets.add(pw.SizedBox(height: 8));
      widgets.add(_subLabel('Stool type distribution'));
      widgets.add(_zebraTable(
        ['Stool type', 'Description', 'Count'],
        [
          for (final type in stats.stoolTypeCounts.keys.toList()..sort())
            [
              'Type $type',
              _ascii(CarePackData.stoolTypes
                      .where((s) => s.value == type)
                      .map((s) => s.label)
                      .firstOrNull ??
                  '-'),
              '${stats.stoolTypeCounts[type]}',
            ],
        ],
        widths: {
          0: const pw.FixedColumnWidth(55),
          1: const pw.FlexColumnWidth(),
          2: const pw.FixedColumnWidth(40),
        },
      ));
    }

    // Days with notable cramps/gas (rated 2 or higher on the 0-3 scale).
    if (journals.isNotEmpty) {
      widgets.add(pw.SizedBox(height: 8));
      widgets.add(pw.Text(
        'Days with cramps/gas rated 2 or higher (0-3 scale): '
        '${uncomfortableDayCount(journals)} of ${journals.length} '
        'journalled days.',
        style: pw.TextStyle(fontSize: 9, color: _ink),
      ));
      final scale2 = CarePackData.crampsGasScale
          .where((s) => s.value == 2)
          .map((s) => s.label)
          .firstOrNull;
      if (scale2 != null) {
        widgets.add(pw.SizedBox(height: 2));
        widgets.add(pw.Text(
          'Rating 2 = ${_ascii(scale2)}',
          style: pw.TextStyle(fontSize: 7.5, color: _muted),
        ));
      }
    }
    return widgets;
  }

  // ---------------------------------------------------------------------
  // 3. Feeding
  // ---------------------------------------------------------------------

  static List<pw.Widget> _feedingSection(List<Map<String, dynamic>> feedings) {
    final widgets = <pw.Widget>[
      _sectionHeader('Feeding', _accentFeeding),
    ];

    if (feedings.isEmpty) {
      widgets.add(_noData('No feeds recorded in the last $_days days.'));
      return widgets;
    }

    final stats = FeedingStats.fromRows(feedings);
    widgets.add(_zebraTable(
      ['Total feeds', 'Avg / day', 'Avg amount', 'Avg quality',
          'Refused (quality 1)', 'Spit-up rate'],
      [
        [
          '${stats.total}',
          perDay(stats.total, _days).toStringAsFixed(1),
          stats.avgMl == null ? '-' : '${stats.avgMl!.round()} ml',
          stats.avgQuality == null
              ? '-'
              : '${stats.avgQuality!.toStringAsFixed(1)} / 5',
          stats.qualityKnown == 0 ? '-' : '${stats.refusedCount}',
          stats.spitUpRate == null
              ? '-'
              : '${(stats.spitUpRate! * 100).round()}%',
        ],
      ],
    ));
    widgets.add(pw.SizedBox(height: 4));
    widgets.add(pw.Text(
      'Avg amount covers only feeds with a recorded volume; avg quality '
      'and spit-up rate cover only feeds where they were recorded.',
      style: pw.TextStyle(fontSize: 7.5, color: _muted),
    ));
    return widgets;
  }

  // ---------------------------------------------------------------------
  // 4. Temperature & medication
  // ---------------------------------------------------------------------

  static List<pw.Widget> _healthSection(
      List<Map<String, dynamic>> healthLogs) {
    final widgets = <pw.Widget>[
      _sectionHeader('Temperature & medication', _accentHealth),
    ];

    final relevant = healthLogs
        .where((h) => h['temperature_c'] != null || h['medication'] != null)
        .toList();

    if (relevant.isEmpty) {
      widgets.add(_noData('No temperature readings or medicine doses in '
          'the last $_days days.'));
      return widgets;
    }

    widgets.add(_zebraTable(
      ['Date', 'Time', 'Temp (C)', 'Status', 'Medication', 'Dosage',
          'Symptoms'],
      [
        for (final h in relevant)
          [
            _fmtDate(parseTimestamp(h['logged_at'])),
            _fmtTime(parseTimestamp(h['logged_at'])),
            h['temperature_c'] != null ? '${h['temperature_c']}' : '-',
            h['temperature_c'] is num
                ? temperatureStatus((h['temperature_c'] as num).toDouble())
                : '-',
            _orDash(h['medication']),
            _orDash(h['dosage']),
            _orDash(h['symptoms']),
          ],
      ],
    ));

    final doseCount = medicationDoseCount(healthLogs);
    if (doseCount > 0) {
      widgets.add(pw.SizedBox(height: 6));
      widgets.add(pw.Text(
        '$doseCount medicine dose(s) logged in the last $_days days.',
        style: pw.TextStyle(fontSize: 9, color: _ink),
      ));
    }
    widgets.add(pw.SizedBox(height: 6));
    widgets.add(pw.Text(
      temperatureSourceNote,
      style: pw.TextStyle(fontSize: 7.5, color: _muted),
    ));
    return widgets;
  }

  // ---------------------------------------------------------------------
  // Layout building blocks (family report design system)
  // ---------------------------------------------------------------------

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
            decoration: i.isOdd ? pw.BoxDecoration(color: _zebra) : null,
            children: [for (final c in rows[i]) cell(c)],
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Small helpers
  // ---------------------------------------------------------------------

  /// Strips anything outside printable ASCII so the WinAnsi-encoded built-in
  /// fonts never receive emoji or other multi-byte characters.
  static String _ascii(String input) {
    final out = StringBuffer();
    for (final code in input.runes) {
      if (code == 0x0A || (code >= 0x20 && code <= 0x7E)) {
        out.writeCharCode(code);
      }
    }
    return out.toString().replaceAll(RegExp(r'[ \t]{2,}'), ' ').trim();
  }

  static String _orDash(dynamic value) {
    final s = _ascii(value?.toString() ?? '');
    return s.isEmpty ? '-' : s;
  }

  static String _fmtDate(DateTime? dt) =>
      dt == null ? '-' : DateFormat('EEE d MMM').format(dt);

  static String _fmtTime(DateTime? dt) =>
      dt == null ? '-' : DateFormat('HH:mm').format(dt);
}
