import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../providers/baby_provider.dart';
import '../../models/growth.dart';
import '../../providers/growth_provider.dart';
import '../../utils/date_utils.dart';
import '../../utils/who_growth_data.dart';
import '../../widgets/common/animated_card.dart';
import '../../widgets/common/empty_state.dart';

enum GrowthChartType { weight, height, head }

class GrowthScreen extends ConsumerStatefulWidget {
  const GrowthScreen({super.key});

  @override
  ConsumerState<GrowthScreen> createState() => _GrowthScreenState();
}

class _GrowthScreenState extends ConsumerState<GrowthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _weightController = TextEditingController();
  final _heightController = TextEditingController();
  final _headController = TextEditingController();
  final _notesController = TextEditingController();

  GrowthChartType _selectedChart = GrowthChartType.weight;
  bool _isSaving = false;
  bool _showForm = false;

  @override
  void dispose() {
    _weightController.dispose();
    _heightController.dispose();
    _headController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _saveGrowth() async {
    if (!_formKey.currentState!.validate()) return;

    final baby = ref.read(selectedBabyProvider);
    if (baby == null) return;

    final weight = double.tryParse(_weightController.text);
    final height = double.tryParse(_heightController.text);
    final head = double.tryParse(_headController.text);

    if (weight == null && height == null && head == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter at least one measurement'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      await GrowthActions.logGrowth(
        babyId: baby.id,
        weightKg: weight,
        heightCm: height,
        headCm: head,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );

      ref.invalidate(growthEntriesProvider);

      _weightController.clear();
      _heightController.clear();
      _headController.clear();
      _notesController.clear();

      setState(() => _showForm = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Growth measurement saved'),
            backgroundColor: const Color(0xFF4CAF50),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  double _babyAgeInMonths(DateTime dateOfBirth) {
    final now = DateTime.now();
    return (now.difference(dateOfBirth).inDays / 30.44);
  }

  @override
  Widget build(BuildContext context) {
    final baby = ref.watch(selectedBabyProvider);
    final growthEntries = ref.watch(growthEntriesProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFFAF8FC),
      appBar: AppBar(
        title: const Text('Growth'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF2D2640),
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => setState(() => _showForm = !_showForm),
        backgroundColor: const Color(0xFF9B72CF),
        child: AnimatedRotation(
          turns: _showForm ? 0.125 : 0,
          duration: const Duration(milliseconds: 200),
          child: Icon(
            _showForm ? Icons.close : Icons.add,
            color: Colors.white,
          ),
        ),
      ),
      body: SafeArea(
        child: growthEntries.when(
          loading: () => const Center(
            child: CircularProgressIndicator(
              color: Color(0xFF9B72CF),
            ),
          ),
          error: (error, _) => Center(
            child: Text('Error: $error'),
          ),
          data: (entries) {
            if (entries.isEmpty && !_showForm) {
              return const EmptyState(
                icon: Icons.straighten,
                title: 'No growth records yet',
                description: 'Tap + to log your baby\'s first measurement',
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                if (_showForm) _buildInputForm(),
                if (entries.isNotEmpty) ...[
                  if (baby != null) _buildPercentileCard(entries, baby),
                  const SizedBox(height: 16),
                  _buildChartToggle(),
                  const SizedBox(height: 12),
                  if (baby != null)
                    _buildGrowthChart(entries, baby),
                  const SizedBox(height: 24),
                  _buildHistorySection(entries, baby),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildInputForm() {
    return AnimatedCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'New Measurement',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2D2640),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildDecimalField(
                      controller: _weightController,
                      label: 'Weight',
                      suffix: 'kg',
                      icon: Icons.monitor_weight_outlined,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildDecimalField(
                      controller: _heightController,
                      label: 'Height',
                      suffix: 'cm',
                      icon: Icons.height,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildDecimalField(
                      controller: _headController,
                      label: 'Head Circ.',
                      suffix: 'cm',
                      icon: Icons.circle_outlined,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(child: SizedBox()),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesController,
                decoration: InputDecoration(
                  labelText: 'Notes (optional)',
                  prefixIcon: const Icon(Icons.notes, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE8D5F5)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE8D5F5)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: Color(0xFF9B72CF),
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFFAF8FC),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveGrowth,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF9B72CF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
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
                      : const Text(
                          'Save Measurement',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDecimalField({
    required TextEditingController controller,
    required String label,
    required String suffix,
    required IconData icon,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE8D5F5)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE8D5F5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: Color(0xFF9B72CF),
            width: 2,
          ),
        ),
        filled: true,
        fillColor: const Color(0xFFFAF8FC),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
      ),
      validator: (value) {
        if (value != null && value.isNotEmpty) {
          final parsed = double.tryParse(value);
          if (parsed == null || parsed <= 0) {
            return 'Invalid';
          }
        }
        return null;
      },
    );
  }

  Widget _buildPercentileCard(List<Growth> entries, dynamic baby) {
    final latest = entries.first;
    final ageMonths = _babyAgeInMonths(baby.dateOfBirth);
    final percentiles = WhoGrowthData.getPercentiles(
      ageMonths: ageMonths,
      gender: baby.gender,
      weightKg: latest.weightKg,
      heightCm: latest.heightCm,
      headCm: latest.headCm,
    );

    if (percentiles.isEmpty) return const SizedBox.shrink();

    return AnimatedCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8D5F5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.insights,
                    color: Color(0xFF9B72CF),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'WHO Percentiles',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2D2640),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (percentiles.containsKey('weight'))
                  Expanded(
                    child: _buildPercentileTile(
                      'Weight',
                      percentiles['weight']!,
                      Icons.monitor_weight_outlined,
                      const Color(0xFFD5E8F5),
                    ),
                  ),
                if (percentiles.containsKey('height')) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildPercentileTile(
                      'Height',
                      percentiles['height']!,
                      Icons.height,
                      const Color(0xFFD5F5E8),
                    ),
                  ),
                ],
                if (percentiles.containsKey('head')) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildPercentileTile(
                      'Head',
                      percentiles['head']!,
                      Icons.circle_outlined,
                      const Color(0xFFF5F0D5),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPercentileTile(
    String label,
    double percentile,
    IconData icon,
    Color bgColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF2D2640)),
          const SizedBox(height: 6),
          Text(
            '${percentile.toStringAsFixed(0)}%',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF2D2640),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF8B85A0),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartToggle() {
    return Row(
      children: GrowthChartType.values.map((type) {
        final isSelected = _selectedChart == type;
        final label = switch (type) {
          GrowthChartType.weight => 'Weight',
          GrowthChartType.height => 'Height',
          GrowthChartType.head => 'Head',
        };
        final icon = switch (type) {
          GrowthChartType.weight => Icons.monitor_weight_outlined,
          GrowthChartType.height => Icons.height,
          GrowthChartType.head => Icons.circle_outlined,
        };

        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              left: type == GrowthChartType.weight ? 0 : 4,
              right: type == GrowthChartType.head ? 0 : 4,
            ),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              child: Material(
                color: isSelected
                    ? const Color(0xFF9B72CF)
                    : Colors.white,
                borderRadius: BorderRadius.circular(12),
                elevation: isSelected ? 2 : 0,
                child: InkWell(
                  onTap: () => setState(() => _selectedChart = type),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? Colors.transparent
                            : const Color(0xFFE8D5F5),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          icon,
                          size: 16,
                          color: isSelected
                              ? Colors.white
                              : const Color(0xFF8B85A0),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? Colors.white
                                : const Color(0xFF8B85A0),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildGrowthChart(List<Growth> entries, dynamic baby) {
    final filteredEntries = entries.where((e) {
      return switch (_selectedChart) {
        GrowthChartType.weight => e.weightKg != null,
        GrowthChartType.height => e.heightCm != null,
        GrowthChartType.head => e.headCm != null,
      };
    }).toList()
      ..sort((a, b) => a.measuredAt.compareTo(b.measuredAt));

    if (filteredEntries.isEmpty) {
      return AnimatedCard(
        child: Container(
          height: 200,
          alignment: Alignment.center,
          child: Text(
            'No ${_selectedChart.name} data to display',
            style: const TextStyle(
              color: Color(0xFF8B85A0),
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    final spots = filteredEntries.asMap().entries.map((entry) {
      final growth = entry.value;
      final ageInMonths = growth.measuredAt
              .difference(baby.dateOfBirth)
              .inDays /
          30.44;
      final value = switch (_selectedChart) {
        GrowthChartType.weight => growth.weightKg!,
        GrowthChartType.height => growth.heightCm!,
        GrowthChartType.head => growth.headCm!,
      };
      return FlSpot(ageInMonths, value);
    }).toList();

    final unit = switch (_selectedChart) {
      GrowthChartType.weight => 'kg',
      GrowthChartType.height => 'cm',
      GrowthChartType.head => 'cm',
    };

    final chartColor = switch (_selectedChart) {
      GrowthChartType.weight => const Color(0xFF9B72CF),
      GrowthChartType.height => const Color(0xFF4CAF50),
      GrowthChartType.head => const Color(0xFFFF9800),
    };

    final minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final yPadding = (maxY - minY) * 0.15;

    return AnimatedCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 20, 20, 12),
        child: SizedBox(
          height: 220,
          child: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval:
                    ((maxY - minY) / 4).clamp(0.5, double.infinity),
                getDrawingHorizontalLine: (value) => FlLine(
                  color: const Color(0xFFE8D5F5).withValues(alpha: 0.5),
                  strokeWidth: 1,
                ),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: AxisTitles(
                  axisNameWidget: const Text(
                    'Age (months)',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF8B85A0),
                    ),
                  ),
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    interval: _calculateInterval(spots),
                    getTitlesWidget: (value, meta) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '${value.toInt()}m',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFF8B85A0),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    getTitlesWidget: (value, meta) {
                      return Text(
                        value.toStringAsFixed(1),
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF8B85A0),
                        ),
                      );
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              minY: (minY - yPadding).clamp(0, double.infinity),
              maxY: maxY + yPadding,
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => const Color(0xFF2D2640),
                  tooltipRoundedRadius: 10,
                  getTooltipItems: (touchedSpots) {
                    return touchedSpots.map((spot) {
                      return LineTooltipItem(
                        '${spot.y.toStringAsFixed(1)} $unit\n${spot.x.toStringAsFixed(1)} months',
                        const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      );
                    }).toList();
                  },
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  curveSmoothness: 0.3,
                  color: chartColor,
                  barWidth: 3,
                  isStrokeCapRound: true,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, barData, index) {
                      return FlDotCirclePainter(
                        radius: 4,
                        color: Colors.white,
                        strokeWidth: 2.5,
                        strokeColor: chartColor,
                      );
                    },
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    color: chartColor.withValues(alpha: 0.1),
                  ),
                ),
              ],
            ),
            duration: const Duration(milliseconds: 300),
          ),
        ),
      ),
    );
  }

  double _calculateInterval(List<FlSpot> spots) {
    if (spots.length < 2) return 1;
    final range = spots.last.x - spots.first.x;
    if (range <= 3) return 1;
    if (range <= 12) return 2;
    if (range <= 24) return 3;
    return 6;
  }

  Widget _buildHistorySection(List<Growth> entries, dynamic baby) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'History',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF2D2640),
          ),
        ),
        const SizedBox(height: 12),
        ...entries.map((entry) => _buildHistoryItem(entry, baby)),
      ],
    );
  }

  Widget _buildHistoryItem(Growth entry, dynamic baby) {
    final ageMonths = baby != null
        ? entry.measuredAt.difference(baby.dateOfBirth).inDays / 30.44
        : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AnimatedCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    AppDateUtils.formatDate(entry.measuredAt),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2D2640),
                    ),
                  ),
                  if (ageMonths != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8D5F5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${ageMonths.toStringAsFixed(1)} mo',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF9B72CF),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (entry.weightKg != null)
                    _buildMeasurementChip(
                      Icons.monitor_weight_outlined,
                      '${entry.weightKg!.toStringAsFixed(2)} kg',
                      const Color(0xFFD5E8F5),
                    ),
                  if (entry.heightCm != null) ...[
                    const SizedBox(width: 8),
                    _buildMeasurementChip(
                      Icons.height,
                      '${entry.heightCm!.toStringAsFixed(1)} cm',
                      const Color(0xFFD5F5E8),
                    ),
                  ],
                  if (entry.headCm != null) ...[
                    const SizedBox(width: 8),
                    _buildMeasurementChip(
                      Icons.circle_outlined,
                      '${entry.headCm!.toStringAsFixed(1)} cm',
                      const Color(0xFFF5F0D5),
                    ),
                  ],
                ],
              ),
              if (entry.notes != null && entry.notes!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  entry.notes!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF8B85A0),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMeasurementChip(IconData icon, String label, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF2D2640)),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF2D2640),
            ),
          ),
        ],
      ),
    );
  }
}
