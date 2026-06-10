import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/baby.dart';
import '../utils/care_pack_data.dart';
import '../utils/date_utils.dart';
import 'supabase_service.dart';

/// Builds the "Doctor visit report" PDF: a clinical summary of the last
/// 14 days of reflux, digestion, feeding, temperature and medication data.
///
/// Pure data - no AI calls. Tables that ship with the Care Pack migration
/// (reflux_events, daily_journals) or columns that ship with it (stool_type,
/// quality) may not exist yet; every query degrades to an empty section
/// instead of crashing.
class DoctorReportService {
  DoctorReportService._();

  static const int _days = 14;

  static Future<Uint8List> build({required Baby baby}) async {
    final now = DateTime.now();
    // 14 calendar days, inclusive of today.
    final start = DateTime(now.year, now.month, now.day - (_days - 1));
    final startIso = start.toUtc().toIso8601String();
    final startDateStr =
        '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
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
      rows('daily_journals', 'journal_date', startDateStr),
      rows('diapers', 'logged_at', startIso),
      rows('health_logs', 'logged_at', startIso),
      rows('feedings', 'logged_at', startIso),
    ]);

    final reflux = results[0];
    final journals = results[1];
    final diapers = results[2];
    final healthLogs = results[3];
    final feedings = results[4];

    return _buildPdf(
      baby: baby,
      start: start,
      end: now,
      reflux: reflux,
      journals: journals,
      diapers: diapers,
      healthLogs: healthLogs,
      feedings: feedings,
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
    final primaryColor = PdfColor.fromHex('#9b72cf');
    final headerStyle = pw.TextStyle(
      fontSize: 20,
      fontWeight: pw.FontWeight.bold,
      color: primaryColor,
    );
    final sectionStyle = pw.TextStyle(
      fontSize: 14,
      fontWeight: pw.FontWeight.bold,
      color: PdfColor.fromHex('#2d2640'),
    );
    final mutedStyle = pw.TextStyle(
      fontSize: 9,
      color: PdfColor.fromHex('#8b85a0'),
    );
    final bodyStyle = const pw.TextStyle(fontSize: 10);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Doctor Visit Report', style: headerStyle),
            pw.SizedBox(height: 4),
            pw.Text(
              '${baby.name} - DOB ${AppDateUtils.formatFull(baby.dateOfBirth)} - Age ${baby.ageDisplay}',
              style: pw.TextStyle(
                fontSize: 12,
                color: PdfColor.fromHex('#8b85a0'),
              ),
            ),
            pw.Text(
              '${AppDateUtils.formatFull(start)} - ${AppDateUtils.formatFull(end)} (last $_days days) - Prepared with TinyTrack',
              style: mutedStyle,
            ),
            pw.Divider(color: primaryColor, thickness: 1),
            pw.SizedBox(height: 8),
          ],
        ),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: mutedStyle,
          ),
        ),
        build: (context) => [
          ..._refluxSection(reflux, sectionStyle, bodyStyle, mutedStyle),
          pw.SizedBox(height: 20),
          ..._digestionSection(
              diapers, journals, sectionStyle, bodyStyle, mutedStyle),
          pw.SizedBox(height: 20),
          ..._feedingSection(feedings, sectionStyle, bodyStyle),
          pw.SizedBox(height: 20),
          ..._healthSection(healthLogs, sectionStyle, bodyStyle),
        ],
      ),
    );

    return pdf.save();
  }

  // ---------------------------------------------------------------------
  // Sections
  // ---------------------------------------------------------------------

  static List<pw.Widget> _refluxSection(
    List<Map<String, dynamic>> reflux,
    pw.TextStyle sectionStyle,
    pw.TextStyle bodyStyle,
    pw.TextStyle mutedStyle,
  ) {
    final widgets = <pw.Widget>[
      pw.Text('Reflux', style: sectionStyle),
      pw.SizedBox(height: 8),
    ];

    if (reflux.isEmpty) {
      widgets.add(pw.Text('No data recorded.', style: bodyStyle));
      return widgets;
    }

    // Events per day: average across the window + worst day.
    final perDay = <String, int>{};
    for (final r in reflux) {
      final dt = _parseDate(r['logged_at']);
      if (dt == null) continue;
      final key = _dayKey(dt);
      perDay[key] = (perDay[key] ?? 0) + 1;
    }
    String worstDay = '-';
    int worstCount = 0;
    perDay.forEach((day, count) {
      if (count > worstCount) {
        worstCount = count;
        worstDay = day;
      }
    });
    final avg = (reflux.length / _days).toStringAsFixed(1);
    widgets.add(pw.Text(
      '${reflux.length} events in $_days days - avg $avg/day - worst day: '
      '${worstDay == '-' ? '-' : '${_formatDayKey(worstDay)} ($worstCount events)'}',
      style: bodyStyle,
    ));
    widgets.add(pw.SizedBox(height: 8));

    widgets.add(pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      children: [
        _tableHeaderRow(
            ['Date', 'Time', 'Severity (1-5)', 'Painful', 'Arching', 'Trigger']),
        ...reflux.map((r) {
          final dt = _parseDate(r['logged_at']);
          return _tableRow([
            dt != null ? AppDateUtils.formatDate(dt) : '-',
            dt != null ? AppDateUtils.formatTime(dt) : '-',
            (r['severity'] ?? '-').toString(),
            r['painful_crying'] == true ? 'Yes' : '-',
            r['arching_back'] == true ? 'Yes' : '-',
            _orDash(r['trigger_noticed']),
          ]);
        }),
      ],
    ));

    // Severity scale legend.
    widgets.add(pw.SizedBox(height: 6));
    widgets.add(pw.Text('Severity scale:', style: mutedStyle));
    for (final point in CarePackData.refluxSeverity) {
      widgets.add(pw.Text('${point.value} - ${point.label}', style: mutedStyle));
    }
    return widgets;
  }

  static List<pw.Widget> _digestionSection(
    List<Map<String, dynamic>> diapers,
    List<Map<String, dynamic>> journals,
    pw.TextStyle sectionStyle,
    pw.TextStyle bodyStyle,
    pw.TextStyle mutedStyle,
  ) {
    final widgets = <pw.Widget>[
      pw.Text('Digestion', style: sectionStyle),
      pw.SizedBox(height: 8),
    ];

    if (diapers.isEmpty && journals.isEmpty) {
      widgets.add(pw.Text('No data recorded.', style: bodyStyle));
      return widgets;
    }

    // Dirty (poo) nappies: anything that isn't wet-only.
    final poos = diapers.where((d) => d['type'] != 'wet').length;
    widgets.add(pw.Text(
      '$poos dirty nappies in $_days days - avg ${(poos / _days).toStringAsFixed(1)}/day',
      style: bodyStyle,
    ));

    // Stool type distribution (Bristol-style 1-7, post-migration column).
    final stoolCounts = <int, int>{};
    for (final d in diapers) {
      final type = d['stool_type'];
      if (type is int) stoolCounts[type] = (stoolCounts[type] ?? 0) + 1;
    }
    if (stoolCounts.isNotEmpty) {
      widgets.add(pw.SizedBox(height: 8));
      widgets.add(pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
        children: [
          _tableHeaderRow(['Stool type', 'Description', 'Count']),
          ...(stoolCounts.keys.toList()..sort()).map((type) {
            final label = CarePackData.stoolTypes
                .where((s) => s.value == type)
                .map((s) => s.label)
                .firstOrNull;
            return _tableRow([
              'Type $type',
              label ?? '-',
              '${stoolCounts[type]}',
            ]);
          }),
        ],
      ));
    }

    // Days with notable cramps/gas (rated 2 or higher on the 0-3 scale).
    final uncomfortableDays = <String>{};
    for (final j in journals) {
      final cramps = (j['cramps'] as num?)?.toInt() ?? 0;
      final gas = (j['gas'] as num?)?.toInt() ?? 0;
      if (cramps >= 2 || gas >= 2) {
        uncomfortableDays.add((j['journal_date'] ?? '').toString());
      }
    }
    widgets.add(pw.SizedBox(height: 8));
    widgets.add(pw.Text(
      'Days with cramps/gas rated 2 or higher (0-3 scale): ${uncomfortableDays.length} of ${journals.length} journalled days',
      style: bodyStyle,
    ));
    final scale2 = CarePackData.crampsGasScale
        .where((s) => s.value == 2)
        .map((s) => s.label)
        .firstOrNull;
    if (scale2 != null) {
      widgets.add(pw.Text('Rating 2 = $scale2', style: mutedStyle));
    }
    return widgets;
  }

  static List<pw.Widget> _feedingSection(
    List<Map<String, dynamic>> feedings,
    pw.TextStyle sectionStyle,
    pw.TextStyle bodyStyle,
  ) {
    final widgets = <pw.Widget>[
      pw.Text('Feeding', style: sectionStyle),
      pw.SizedBox(height: 8),
    ];

    if (feedings.isEmpty) {
      widgets.add(pw.Text('No data recorded.', style: bodyStyle));
      return widgets;
    }

    final mlValues = [
      for (final f in feedings)
        if (f['amount_ml'] != null) (f['amount_ml'] as num).toDouble(),
    ];
    final avgMl = mlValues.isEmpty
        ? null
        : (mlValues.reduce((a, b) => a + b) / mlValues.length).round();

    final line = StringBuffer(
      '${feedings.length} feeds in $_days days - avg ${(feedings.length / _days).toStringAsFixed(1)}/day',
    );
    if (avgMl != null) line.write(' - avg $avgMl ml per feed');

    // Quality column ships with the Care Pack migration; only report it when
    // the rows actually carry it.
    if (feedings.first.containsKey('quality')) {
      final refused =
          feedings.where((f) => (f['quality'] as num?)?.toInt() == 1).length;
      line.write(' - $refused refused/quality-1 feeds');
    }
    widgets.add(pw.Text(line.toString(), style: bodyStyle));
    return widgets;
  }

  static List<pw.Widget> _healthSection(
    List<Map<String, dynamic>> healthLogs,
    pw.TextStyle sectionStyle,
    pw.TextStyle bodyStyle,
  ) {
    final widgets = <pw.Widget>[
      pw.Text('Temperature & Medication', style: sectionStyle),
      pw.SizedBox(height: 8),
    ];

    final relevant = healthLogs
        .where((h) => h['temperature_c'] != null || h['medication'] != null)
        .toList();

    if (relevant.isEmpty) {
      widgets.add(pw.Text('No data recorded.', style: bodyStyle));
      return widgets;
    }

    widgets.add(pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      children: [
        _tableHeaderRow(
            ['Date', 'Time', 'Temp (C)', 'Medication', 'Dosage', 'Symptoms']),
        ...relevant.map((h) {
          final dt = _parseDate(h['logged_at']);
          return _tableRow([
            dt != null ? AppDateUtils.formatDate(dt) : '-',
            dt != null ? AppDateUtils.formatTime(dt) : '-',
            h['temperature_c'] != null ? '${h['temperature_c']}' : '-',
            _orDash(h['medication']),
            _orDash(h['dosage']),
            _orDash(h['symptoms']),
          ]);
        }),
      ],
    ));
    return widgets;
  }

  // ---------------------------------------------------------------------
  // Table helpers (same compact style as the main export PDF)
  // ---------------------------------------------------------------------

  static pw.TableRow _tableHeaderRow(List<String> cells) {
    return pw.TableRow(
      decoration: pw.BoxDecoration(color: PdfColor.fromHex('#e8d5f5')),
      children: cells
          .map((c) => pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text(
                  c,
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromHex('#2d2640'),
                  ),
                ),
              ))
          .toList(),
    );
  }

  static pw.TableRow _tableRow(List<String> cells) {
    return pw.TableRow(
      children: cells
          .map((c) => pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text(
                  c,
                  style: const pw.TextStyle(fontSize: 9),
                  maxLines: 2,
                ),
              ))
          .toList(),
    );
  }

  static DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString())?.toLocal();
  }

  static String _orDash(dynamic value) {
    final s = value?.toString().trim();
    return (s == null || s.isEmpty) ? '-' : s;
  }

  static String _dayKey(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  static String _formatDayKey(String key) {
    final dt = DateTime.tryParse(key);
    return dt != null ? AppDateUtils.formatDate(dt) : key;
  }
}
