import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../config/theme.dart';
import '../../providers/baby_provider.dart';
import '../../services/doctor_report_service.dart';
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
                              'Last 14 days of reflux, digestion, feeding and meds — a clinical summary to bring to appointments.',
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
                    const SizedBox(height: 20),
                  ],
                ),
              ),
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
