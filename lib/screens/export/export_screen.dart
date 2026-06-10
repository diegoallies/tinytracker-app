import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../config/design_tokens.dart';
import '../../config/theme.dart';
import '../../providers/baby_provider.dart';
import '../../providers/care_pack_provider.dart';
import '../../services/doctor_report_service.dart';
import '../../services/family_report_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/date_utils.dart';
import '../../utils/extensions.dart';
import '../../widgets/common/animated_card.dart';
import '../../widgets/common/loading_skeleton.dart';

class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key});

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  int _selectedDays = 7;
  bool _isLoadingStats = false;
  bool _isGenerating = false;
  bool _isGeneratingDoctorReport = false;
  bool _isGeneratingFamilyReport = false;

  // Family report period: weekly (Mon-Sun) or calendar month. Any past
  // period can be selected; [_familyAnchor] is a date INSIDE the selected
  // period and the bounds are derived from it.
  bool _familyMonthly = false;
  DateTime _familyAnchor = DateTime.now();

  int _feedingsCount = 0;
  int _diapersCount = 0;
  int _sleepCount = 0;
  int _growthCount = 0;
  int _healthCount = 0;

  List<Map<String, dynamic>> _feedingsData = [];
  List<Map<String, dynamic>> _diapersData = [];
  List<Map<String, dynamic>> _sleepsData = [];
  List<Map<String, dynamic>> _growthData = [];
  List<Map<String, dynamic>> _healthData = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStats());
  }

  DateTime get _periodStart =>
      DateTime.now().subtract(Duration(days: _selectedDays));

  Future<void> _loadStats() async {
    final baby = ref.read(selectedBabyProvider);
    if (baby == null) return;

    setState(() => _isLoadingStats = true);

    try {
      final supabase = SupabaseService.client;
      final startDate = _periodStart.toUtc().toIso8601String();

      final results = await Future.wait([
        supabase
            .from('feedings')
            .select()
            .eq('baby_id', baby.id)
            .isFilter('deleted_at', null)
            .gte('created_at', startDate)
            .order('created_at', ascending: false),
        supabase
            .from('diapers')
            .select()
            .eq('baby_id', baby.id)
            .isFilter('deleted_at', null)
            .gte('created_at', startDate)
            .order('created_at', ascending: false),
        supabase
            .from('sleeps')
            .select()
            .eq('baby_id', baby.id)
            .isFilter('deleted_at', null)
            .gte('created_at', startDate)
            .order('created_at', ascending: false),
        supabase
            .from('growth')
            .select()
            .eq('baby_id', baby.id)
            .isFilter('deleted_at', null)
            .gte('created_at', startDate)
            .order('created_at', ascending: false),
        supabase
            .from('health_logs')
            .select()
            .eq('baby_id', baby.id)
            .isFilter('deleted_at', null)
            .gte('created_at', startDate)
            .order('created_at', ascending: false),
      ]);

      if (mounted) {
        setState(() {
          _feedingsData = List<Map<String, dynamic>>.from(results[0]);
          _diapersData = List<Map<String, dynamic>>.from(results[1]);
          _sleepsData = List<Map<String, dynamic>>.from(results[2]);
          _growthData = List<Map<String, dynamic>>.from(results[3]);
          _healthData = List<Map<String, dynamic>>.from(results[4]);
          _feedingsCount = _feedingsData.length;
          _diapersCount = _diapersData.length;
          _sleepCount = _sleepsData.length;
          _growthCount = _growthData.length;
          _healthCount = _healthData.length;
          _isLoadingStats = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingStats = false);
        context.showErrorSnackBar(
          'Couldn’t load your stats. Check your connection and try again.',
          onRetry: _loadStats,
        );
      }
    }
  }

  Future<void> _generateAndSharePdf() async {
    final baby = ref.read(selectedBabyProvider);
    if (baby == null) return;

    setState(() => _isGenerating = true);

    try {
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

      // Title page / header
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          header: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('TinyTracker Report', style: headerStyle),
              pw.SizedBox(height: 4),
              pw.Text(
                '${baby.name} - Last $_selectedDays days',
                style: pw.TextStyle(
                  fontSize: 12,
                  color: PdfColor.fromHex('#8b85a0'),
                ),
              ),
              pw.Text(
                'Generated on ${AppDateUtils.formatDate(DateTime.now())}',
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
            // Overview section
            pw.Text('Overview', style: sectionStyle),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(
                color: PdfColors.grey300,
                width: 0.5,
              ),
              children: [
                _pdfTableHeaderRow(['Category', 'Count']),
                _pdfTableRow(['Feedings', '$_feedingsCount']),
                _pdfTableRow(['Diapers', '$_diapersCount']),
                _pdfTableRow(['Sleep Sessions', '$_sleepCount']),
                _pdfTableRow(['Growth Records', '$_growthCount']),
                _pdfTableRow(['Health Logs', '$_healthCount']),
              ],
            ),
            pw.SizedBox(height: 20),

            // Feedings table
            if (_feedingsData.isNotEmpty) ...[
              pw.Text('Feedings', style: sectionStyle),
              pw.SizedBox(height: 8),
              pw.Table(
                border: pw.TableBorder.all(
                  color: PdfColors.grey300,
                  width: 0.5,
                ),
                children: [
                  _pdfTableHeaderRow(['Date', 'Type', 'Amount', 'Notes']),
                  ..._feedingsData.map((f) => _pdfTableRow([
                        _formatPdfDate(f['created_at']),
                        (f['type'] ?? '-').toString(),
                        _formatFeedingAmount(f),
                        (f['notes'] ?? '-').toString(),
                      ])),
                ],
              ),
              pw.SizedBox(height: 20),
            ],

            // Diapers table
            if (_diapersData.isNotEmpty) ...[
              pw.Text('Diapers', style: sectionStyle),
              pw.SizedBox(height: 8),
              pw.Table(
                border: pw.TableBorder.all(
                  color: PdfColors.grey300,
                  width: 0.5,
                ),
                children: [
                  _pdfTableHeaderRow(['Date', 'Type', 'Color', 'Notes']),
                  ..._diapersData.map((d) => _pdfTableRow([
                        _formatPdfDate(d['created_at']),
                        (d['type'] ?? '-').toString(),
                        (d['color'] ?? '-').toString(),
                        (d['notes'] ?? '-').toString(),
                      ])),
                ],
              ),
              pw.SizedBox(height: 20),
            ],

            // Sleep table
            if (_sleepsData.isNotEmpty) ...[
              pw.Text('Sleep', style: sectionStyle),
              pw.SizedBox(height: 8),
              pw.Table(
                border: pw.TableBorder.all(
                  color: PdfColors.grey300,
                  width: 0.5,
                ),
                children: [
                  _pdfTableHeaderRow(
                      ['Date', 'Start', 'End', 'Duration (min)']),
                  ..._sleepsData.map((s) => _pdfTableRow([
                        _formatPdfDate(s['created_at']),
                        _formatPdfTime(s['start_time']),
                        _formatPdfTime(s['end_time']),
                        (s['duration_minutes'] ?? '-').toString(),
                      ])),
                ],
              ),
              pw.SizedBox(height: 20),
            ],

            // Growth table
            if (_growthData.isNotEmpty) ...[
              pw.Text('Growth', style: sectionStyle),
              pw.SizedBox(height: 8),
              pw.Table(
                border: pw.TableBorder.all(
                  color: PdfColors.grey300,
                  width: 0.5,
                ),
                children: [
                  _pdfTableHeaderRow(
                      ['Date', 'Weight (kg)', 'Height (cm)', 'Head (cm)']),
                  ..._growthData.map((g) => _pdfTableRow([
                        _formatPdfDate(g['created_at']),
                        (g['weight_kg'] ?? '-').toString(),
                        (g['height_cm'] ?? '-').toString(),
                        (g['head_cm'] ?? '-').toString(),
                      ])),
                ],
              ),
              pw.SizedBox(height: 20),
            ],

            // Health table
            if (_healthData.isNotEmpty) ...[
              pw.Text('Health Logs', style: sectionStyle),
              pw.SizedBox(height: 8),
              pw.Table(
                border: pw.TableBorder.all(
                  color: PdfColors.grey300,
                  width: 0.5,
                ),
                children: [
                  _pdfTableHeaderRow(
                      ['Date', 'Type', 'Temperature', 'Notes']),
                  ..._healthData.map((h) => _pdfTableRow([
                        _formatPdfDate(h['created_at']),
                        (h['type'] ?? '-').toString(),
                        h['temperature'] != null
                            ? '${h['temperature']}°'
                            : '-',
                        (h['notes'] ?? '-').toString(),
                      ])),
                ],
              ),
            ],
          ],
        ),
      );

      final pdfBytes = await pdf.save();

      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: 'tinytracker_${baby.name.toLowerCase().replaceAll(' ', '_')}_${_selectedDays}days.pdf',
      );

      if (mounted) {
        context.showSuccessSnackBar('PDF generated successfully!');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar(
          'Couldn’t generate the PDF. Please try again.',
          onRetry: _generateAndSharePdf,
        );
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _generateDoctorReport() async {
    final baby = ref.read(selectedBabyProvider);
    if (baby == null) return;

    setState(() => _isGeneratingDoctorReport = true);

    try {
      final pdfBytes = await DoctorReportService.build(baby: baby);

      await Printing.sharePdf(
        bytes: pdfBytes,
        filename:
            'tinytrack_doctor_report_${baby.name.toLowerCase().replaceAll(' ', '_')}.pdf',
      );

      if (mounted) {
        context.showSuccessSnackBar('Doctor visit report generated!');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar(
          'Couldn’t generate the doctor visit report. Please try again.',
          onRetry: _generateDoctorReport,
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingDoctorReport = false);
    }
  }

  /// [periodStart, periodEnd) for the family report, derived from
  /// [_familyAnchor]. Weeks run Mon-Sun via [weekStartOf]; months are
  /// calendar months. Day-component arithmetic, not Duration math -
  /// DST-safe.
  (DateTime, DateTime) _familyReportPeriod() {
    if (_familyMonthly) {
      final start = DateTime(_familyAnchor.year, _familyAnchor.month, 1);
      return (start, DateTime(start.year, start.month + 1, 1));
    }
    final start = weekStartOf(_familyAnchor);
    return (start, DateTime(start.year, start.month, start.day + 7));
  }

  /// Steps the selected period by [delta] weeks/months (negative = back).
  void _stepFamilyPeriod(int delta) {
    setState(() {
      if (_familyMonthly) {
        _familyAnchor =
            DateTime(_familyAnchor.year, _familyAnchor.month + delta, 1);
      } else {
        final start = weekStartOf(_familyAnchor);
        _familyAnchor =
            DateTime(start.year, start.month, start.day + 7 * delta);
      }
    });
  }

  /// Jump straight to any date; the week/month containing it gets selected.
  /// The picker is clamped to the baby's date of birth .. today.
  Future<void> _pickFamilyPeriodDate() async {
    final baby = ref.read(selectedBabyProvider);
    if (baby == null) return;
    final today = DateTime.now();
    final dob = DateTime(baby.dateOfBirth.year, baby.dateOfBirth.month,
        baby.dateOfBirth.day);
    final firstDate = dob.isAfter(today) ? today : dob;
    var initial = _familyAnchor;
    if (initial.isBefore(firstDate)) initial = firstDate;
    if (initial.isAfter(today)) initial = today;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: today,
      helpText: _familyMonthly
          ? 'Pick any day in the month'
          : 'Pick any day in the week',
    );
    if (picked != null && mounted) {
      setState(() => _familyAnchor = picked);
    }
  }

  /// Human label for the selected period: "Mon 2 - Sun 8 Jun 2026" for
  /// weeks, "June 2026" for months.
  String _familyPeriodLabel(DateTime start, DateTime end) {
    if (_familyMonthly) return DateFormat('MMMM yyyy').format(start);
    final endInclusive = DateTime(end.year, end.month, end.day - 1);
    final sameMonth = start.month == endInclusive.month &&
        start.year == endInclusive.year;
    final startFmt = sameMonth
        ? DateFormat('EEE d').format(start)
        : DateFormat('EEE d MMM').format(start);
    return '$startFmt - ${DateFormat('EEE d MMM yyyy').format(endInclusive)}';
  }

  Future<void> _generateFamilyReport() async {
    final baby = ref.read(selectedBabyProvider);
    if (baby == null) return;

    setState(() => _isGeneratingFamilyReport = true);

    try {
      final (start, end) = _familyReportPeriod();
      final pdfBytes = await FamilyReportService.build(
        baby: baby,
        periodStart: start,
        periodEnd: end,
        isMonthly: _familyMonthly,
      );

      final dateTag =
          '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename:
            'tinytrack_family_report_${_familyMonthly ? 'monthly' : 'weekly'}_$dateTag.pdf',
      );

      if (mounted) {
        context.showSuccessSnackBar('Family report generated!');
      }
    } catch (e) {
      if (mounted) {
        context.showErrorSnackBar(
          'Couldn’t generate the family report. Please try again.',
          onRetry: _generateFamilyReport,
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingFamilyReport = false);
    }
  }

  pw.TableRow _pdfTableHeaderRow(List<String> cells) {
    return pw.TableRow(
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#e8d5f5'),
      ),
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

  pw.TableRow _pdfTableRow(List<String> cells) {
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

  String _formatPdfDate(dynamic dateStr) {
    if (dateStr == null) return '-';
    try {
      final dt = DateTime.parse(dateStr.toString());
      return AppDateUtils.formatDate(dt);
    } catch (_) {
      return dateStr.toString();
    }
  }

  String _formatPdfTime(dynamic dateStr) {
    if (dateStr == null) return '-';
    try {
      final dt = DateTime.parse(dateStr.toString());
      return AppDateUtils.formatTime(dt);
    } catch (_) {
      return dateStr.toString();
    }
  }

  String _formatFeedingAmount(Map<String, dynamic> feeding) {
    final amount = feeding['amount_ml'] ?? feeding['amount_oz'];
    if (amount != null) return '${amount}ml';
    final duration = feeding['duration_minutes'];
    if (duration != null) return '$duration min';
    return '-';
  }

  @override
  Widget build(BuildContext context) {
    final baby = ref.watch(selectedBabyProvider);
    final totalRecords =
        _feedingsCount + _diapersCount + _sleepCount + _growthCount + _healthCount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Export'),
        elevation: 0,
      ),
      body: SafeArea(
        child: baby == null
            ? const Center(child: Text('No baby selected'))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Period Selector
                    AnimatedCard(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Time Period',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: context.palette.text,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [7, 14, 30].map((days) {
                                final isSelected = _selectedDays == days;
                                return Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                      right: days == 30 ? 0 : 8,
                                    ),
                                    child: GestureDetector(
                                      onTap: () {
                                        setState(() => _selectedDays = days);
                                        _loadStats();
                                      },
                                      child: AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 200),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? AppColors.primary
                                              : AppColors.pastelPurple
                                                  .withValues(alpha:0.3),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          '$days days',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: isSelected
                                                ? Colors.white
                                                : context.palette.text,
                                          ),
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
                    ),
                    const SizedBox(height: 16),

                    // Preview Stats
                    AnimatedCard(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Preview',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: context.palette.text,
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (_isLoadingStats)
                              const LoadingSkeleton()
                            else
                              Wrap(
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  _buildStatChip(Icons.restaurant_rounded,
                                      'Feeds', _feedingsCount),
                                  _buildStatChip(
                                      Icons.baby_changing_station_rounded,
                                      'Diapers',
                                      _diapersCount),
                                  _buildStatChip(Icons.bedtime_rounded,
                                      'Sleep', _sleepCount),
                                  _buildStatChip(
                                      Icons.straighten_rounded,
                                      'Growth',
                                      _growthCount),
                                  _buildStatChip(
                                      Icons.medical_services_rounded,
                                      'Health',
                                      _healthCount),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // What's Included
                    AnimatedCard(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "What's Included",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: context.palette.text,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildIncludedItem('Feeding records'),
                            _buildIncludedItem('Diaper changes'),
                            _buildIncludedItem('Sleep sessions'),
                            _buildIncludedItem('Growth measurements'),
                            _buildIncludedItem('Health logs'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Generate Button
                    SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        onPressed: (_isGenerating || _isLoadingStats || totalRecords == 0)
                            ? null
                            : _generateAndSharePdf,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              AppColors.primary.withValues(alpha:0.4),
                          disabledForegroundColor: Colors.white70,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        child: _isGenerating
                            ? const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Text(
                                    'Generating...',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.picture_as_pdf_rounded,
                                      size: 22),
                                  const SizedBox(width: 10),
                                  Text(
                                    totalRecords == 0
                                        ? 'No data to export'
                                        : 'Generate PDF ($totalRecords records)',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Doctor Visit Report
                    AnimatedCard(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.local_hospital_rounded,
                                  size: 20,
                                  color: AppColors.primary,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Doctor visit report',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: context.palette.text,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Last 14 days of reflux, digestion, feeding and meds - a clinical summary to bring to appointments.',
                              style: TextStyle(
                                fontSize: 14,
                                color: context.palette.muted,
                              ),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              height: 52,
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _isGeneratingDoctorReport
                                    ? null
                                    : _generateDoctorReport,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor:
                                      AppColors.primary.withValues(alpha: 0.4),
                                  disabledForegroundColor: Colors.white70,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  elevation: 0,
                                ),
                                child: _isGeneratingDoctorReport
                                    ? const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                Colors.white,
                                              ),
                                            ),
                                          ),
                                          SizedBox(width: 12),
                                          Text(
                                            'Generating...',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      )
                                    : const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.picture_as_pdf_rounded,
                                              size: 22),
                                          SizedBox(width: 10),
                                          Text(
                                            'Generate doctor report',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Family Report (owners only)
                    if (ref.watch(babyProvider).isOwner) ...[
                      const SizedBox(height: 16),
                      _buildFamilyReportCard(),
                    ],
                    const SizedBox(height: 20),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildFamilyReportCard() {
    final baby = ref.watch(selectedBabyProvider);
    final (start, end) = _familyReportPeriod();
    final periodLabel = _familyPeriodLabel(start, end);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Forward stepping stops at the period containing today.
    final canStepForward = !end.isAfter(today);

    // A period that starts before the baby's birth month has nothing to
    // report on.
    final dob = baby?.dateOfBirth;
    final beforeBirth =
        dob != null && start.isBefore(DateTime(dob.year, dob.month, 1));

    final thisStart =
        _familyMonthly ? DateTime(now.year, now.month, 1) : weekStartOf(now);
    final lastStart = _familyMonthly
        ? DateTime(now.year, now.month - 1, 1)
        : DateTime(thisStart.year, thisStart.month, thisStart.day - 7);
    final isThisPeriod = start.isAtSameMomentAs(thisStart);
    final isLastPeriod = start.isAtSameMomentAs(lastStart);

    Widget quickChip(String label, bool selected, DateTime anchor) {
      return ChoiceChip(
        label: Text(label),
        selected: selected,
        selectedColor: AppColors.primary,
        checkmarkColor: Colors.white,
        labelStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: selected ? Colors.white : context.palette.text,
        ),
        onSelected: (_) => setState(() => _familyAnchor = anchor),
      );
    }

    return AnimatedCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_stories_rounded,
                  size: 20,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Family Report',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: context.palette.text,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Any week or month, beautifully summarised - feeding, sleep, digestion, reflux, growth, medicine and milestones in one professional document.',
              style: TextStyle(
                fontSize: 14,
                color: context.palette.muted,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _buildFamilyModeToggle(),
            const SizedBox(height: AppSpacing.sm),
            _buildFamilyPeriodStepper(periodLabel, canStepForward),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                quickChip(_familyMonthly ? 'This month' : 'This week',
                    isThisPeriod, thisStart),
                quickChip(_familyMonthly ? 'Last month' : 'Last week',
                    isLastPeriod, lastStart),
              ],
            ),
            if (beforeBirth) ...[
              const SizedBox(height: AppSpacing.sm),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: AppRadius.mdAll,
                  border: Border.all(
                    color: AppColors.warning.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 18, color: AppColors.warning),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'This ${_familyMonthly ? 'month' : 'week'} is before '
                        '${baby?.name ?? 'your baby'} was born '
                        '(${DateFormat('MMMM yyyy').format(dob)}). '
                        'Pick a later period to generate a report.',
                        style: TextStyle(
                          fontSize: 13,
                          color: context.palette.text,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              height: 52,
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_isGeneratingFamilyReport || beforeBirth)
                    ? null
                    : _generateFamilyReport,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      AppColors.primary.withValues(alpha: 0.4),
                  disabledForegroundColor: Colors.white70,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: _isGeneratingFamilyReport
                    ? const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Generating...',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      )
                    : const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.picture_as_pdf_rounded, size: 22),
                          SizedBox(width: 10),
                          Text(
                            'Generate family report',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Weekly | Monthly segmented control. Switching keeps the anchor date,
  /// so the containing week/month of the same date stays selected.
  Widget _buildFamilyModeToggle() {
    Widget segment(String label, bool selected, VoidCallback onTap) {
      return Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: AppMotion.fast,
            curve: AppMotion.ease,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? AppColors.primary : Colors.transparent,
              borderRadius: AppRadius.mdAll,
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : context.palette.text,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: context.palette.border),
      ),
      child: Row(
        children: [
          segment('Weekly', !_familyMonthly,
              () => setState(() => _familyMonthly = false)),
          segment('Monthly', _familyMonthly,
              () => setState(() => _familyMonthly = true)),
        ],
      ),
    );
  }

  /// [<]  Mon 2 - Sun 8 Jun 2026  [calendar] [>]. Back steps indefinitely,
  /// forward stops at the current period; long-press the label (or tap the
  /// calendar icon) to jump straight to any date.
  Widget _buildFamilyPeriodStepper(String periodLabel, bool canStepForward) {
    return Container(
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: context.palette.border),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => _stepFamilyPeriod(-1),
            tooltip: _familyMonthly ? 'Previous month' : 'Previous week',
            icon: Icon(
              Icons.chevron_left_rounded,
              color: context.palette.text,
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: _pickFamilyPeriodDate,
              onLongPress: _pickFamilyPeriodDate,
              borderRadius: AppRadius.mdAll,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    Text(
                      _familyMonthly ? 'MONTH' : 'WEEK',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                        color: context.palette.muted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        periodLabel,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: context.palette.text,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: _pickFamilyPeriodDate,
            tooltip: 'Jump to a date',
            icon: Icon(
              Icons.calendar_month_rounded,
              size: 18,
              color: AppColors.primary,
            ),
          ),
          IconButton(
            onPressed: canStepForward ? () => _stepFamilyPeriod(1) : null,
            tooltip: _familyMonthly ? 'Next month' : 'Next week',
            icon: Icon(
              Icons.chevron_right_rounded,
              color: canStepForward
                  ? context.palette.text
                  : context.palette.muted.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(IconData icon, String label, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.pastelPurple.withValues(alpha:0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(
            '$count $label',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: context.palette.text,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIncludedItem(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_rounded,
            size: 20,
            color: AppColors.primary,
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: context.palette.text,
            ),
          ),
        ],
      ),
    );
  }
}
