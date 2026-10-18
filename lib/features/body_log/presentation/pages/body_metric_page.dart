import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:image_picker/image_picker.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/features/body_log/domain/entities/body_metric_entity.dart';
import 'package:fittrack/features/body_log/domain/repositories/body_metric_repository.dart';
import 'package:fittrack/features/body_log/domain/repositories/photo_repository.dart';
import 'package:fittrack/features/goal/domain/repositories/goal_repository.dart';
import 'package:fittrack/features/settings/domain/entities/user_settings_entity.dart';
import 'package:fittrack/core/services/notification_service.dart';

const _green = Color(0xFFFF8A00);
const _amber = Color(0xFFFFC53D);
const _blue = Color(0xFF38BDF8);
const _red = Color(0xFFEF5350);

class BodyMetricPage extends ConsumerStatefulWidget {
  const BodyMetricPage({super.key});

  @override
  ConsumerState<BodyMetricPage> createState() => _BodyMetricPageState();
}

class _BodyMetricPageState extends ConsumerState<BodyMetricPage> {
  String _timeRange = 'month';
  String _metricType = 'weight';

  @override
  Widget build(BuildContext context) {
    final bodyRepo = ref.watch(bodyMetricRepoProvider);
    final photoRepo = ref.watch(photoRepoProvider);
    final theme = Theme.of(context);
    final now = DateTime.now();

    DateTime from;
    switch (_timeRange) {
      case 'week':
        from = now.subtract(const Duration(days: 7));
      case 'quarter':
        from = now.subtract(const Duration(days: 90));
      case 'all':
        from = DateTime(2020);
      default:
        from = now.subtract(const Duration(days: 30));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('体重数据')),
      body: FutureBuilder<_BodyData>(
        future: _loadData(bodyRepo, photoRepo, now, from),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data ?? const _BodyData();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              // ── 体重概览（大字 + 三宫格）──
              if (data.metrics.isNotEmpty) ...[
                _buildWeightCard(theme, data.metrics, ref),
                const SizedBox(height: 20),
              ],

              // ── 趋势图（指标 chips + 时间范围 合并进同一张卡）──
              _buildTrendCard(theme, data),
              const SizedBox(height: 18),

              // ── 录入表单（精简模式）──
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _AddMetricForm(
                    bodyRepo: bodyRepo,
                    photoRepo: photoRepo,
                    goalRepo: ref.read(goalRepoProvider),
                    onSaved: () => setState(() {}),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ── 身体相册入口 ──
              _buildAlbumEntryCard(theme, data.photos.length),
              const SizedBox(height: 18),

              // ── 历史记录（紧凑列表，最多 10 条）──
              if (data.metrics.isNotEmpty) ...[
                Text('历史记录', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                ...data.metrics.reversed.take(10).map(
                      (m) => _HistoryRow(
                        metric: m,
                        onDelete: () async {
                          await bodyRepo.delete(m.id);
                          setState(() {});
                        },
                      ),
                    ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<_BodyData> _loadData(
    BodyMetricRepository bodyRepo,
    PhotoRepository photoRepo,
    DateTime now,
    DateTime from,
  ) async {
    final metrics = await bodyRepo.getAll(from: from, to: now);
    final photos = await photoRepo.getAll();
    return _BodyData(metrics: metrics, photos: photos);
  }

  /// 身体相册入口卡（替代原来的照片网格区块）
  Widget _buildAlbumEntryCard(ThemeData theme, int photoCount) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push('/body/album'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: _green.withAlpha(32),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.photo_library,
                    size: 16, color: _green),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('身体相册', style: theme.textTheme.bodyLarge),
                    const SizedBox(height: 2),
                    Text(
                      '$photoCount 张照片',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  size: 18, color: theme.colorScheme.outline),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWeightCard(
    ThemeData theme,
    List<BodyMetricEntity> metrics,
    WidgetRef ref,
  ) {
    final userSettings = ref.watch(userSettingsProvider).valueOrNull;
    final latest = metrics.last;
    final currentJin = latest.weightKg * 2;
    final targetKg = userSettings?.targetWeightKg;
    final targetJin = targetKg != null ? targetKg * 2 : null;

    final firstJin = metrics.first.weightKg * 2;
    final totalLoss = metrics.length >= 2 ? firstJin - currentJin : null;

    final weekCutoff = DateTime.now().subtract(const Duration(days: 7));
    final older = metrics.where((m) => m.date.isBefore(weekCutoff)).toList();
    final weekStartJin = older.isNotEmpty ? older.last.weightKg * 2 : null;
    final weekChange = weekStartJin != null ? currentJin - weekStartJin : null;

    final bmi = userSettings?.bmi(latest.weightKg);
    final bmiLabel = bmi != null
        ? UserSettingsEntity.bmiLevelLabels[UserSettingsEntity.bmiLevel(bmi)]
        : null;
    final bmiColor = bmi == null
        ? Colors.white54
        : switch (UserSettingsEntity.bmiLevel(bmi)) {
            'normal' => _green,
            'overweight' => _amber,
            'obese' => _red,
            _ => _blue,
          };

    String signed(double v) => v < -0.05
        ? '-${v.abs().toStringAsFixed(1)}'
        : (v > 0.05 ? '+${v.toStringAsFixed(1)}' : '0.0');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: currentJin),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => Text(
                v.toStringAsFixed(1),
                style: const TextStyle(
                    fontSize: 40, fontWeight: FontWeight.w700, height: 1.0),
              ),
            ),
            const SizedBox(width: 5),
            Text('斤',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.outline)),
            if (bmi != null) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: bmiColor.withAlpha(30),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'BMI ${bmi.toStringAsFixed(1)} · $bmiLabel',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: bmiColor),
                ),
              ),
            ],
            const Spacer(),
            if (targetJin != null)
              Text(
                '目标 ${targetJin.toStringAsFixed(1)} 斤',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            _MiniStatCard(
              label: '最新',
              value: currentJin.toStringAsFixed(1),
              color: Colors.white,
            ),
            const SizedBox(width: 8),
            _MiniStatCard(
              label: '本周',
              value: weekChange != null ? signed(weekChange) : '—',
              color: weekChange == null
                  ? Colors.white54
                  : (weekChange < -0.05
                      ? _green
                      : (weekChange > 0.05 ? _red : Colors.white70)),
            ),
            const SizedBox(width: 8),
            _MiniStatCard(
              label: '累计',
              value: totalLoss != null ? totalLoss.toStringAsFixed(1) : '—',
              color: (totalLoss ?? 0) > 0.05 ? _green : Colors.white54,
            ),
          ],
        ),
      ],
    );
  }

  static const _metricLabels = {
    'weight': '体重',
    'waist': '腰围',
    'hip': '臀围',
    'chest': '胸围',
  };

  /// 趋势图卡：卡头一行 = 左侧指标 chips（可横滑）+ 右侧范围 SegmentedButton
  Widget _buildTrendCard(ThemeData theme, _BodyData data) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _metricLabels.keys.map((type) {
                        final selected = _metricType == type;
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(
                              _metricLabels[type] ?? type,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: selected
                                    ? Colors.black
                                    : theme.colorScheme.outline,
                              ),
                            ),
                            selected: selected,
                            showCheckmark: false,
                            selectedColor: _green,
                            backgroundColor: Colors.white.withAlpha(12),
                            side: BorderSide(color: Colors.white.withAlpha(20)),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            labelPadding:
                                const EdgeInsets.symmetric(horizontal: 2),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            onSelected: (_) =>
                                setState(() => _metricType = type),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'week', label: Text('周')),
                    ButtonSegment(value: 'month', label: Text('月')),
                    ButtonSegment(value: 'quarter', label: Text('季')),
                    ButtonSegment(value: 'all', label: Text('全部')),
                  ],
                  selected: {_timeRange},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) =>
                      setState(() => _timeRange = v.first),
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 10)),
                    padding: WidgetStatePropertyAll(
                        EdgeInsets.symmetric(horizontal: 6)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (data.metrics.isEmpty)
              SizedBox(
                height: 200,
                child: Center(
                  child: Text('暂无数据',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: Colors.grey)),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 4, 6, 4),
                child: _buildChartWithPrediction(data.metrics, theme),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartWithPrediction(
      List<BodyMetricEntity> metrics, ThemeData theme) {
    return Column(
      children: [
        SizedBox(height: 220, child: _buildChart(metrics, theme)),
        if (_metricType == 'weight' && metrics.length >= 3)
          _buildPredictionText(metrics, theme),
      ],
    );
  }

  Widget _buildPredictionText(
      List<BodyMetricEntity> metrics, ThemeData theme) {
    final validMetrics = metrics.where((m) => true).toList();
    final spots = validMetrics.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.weightKg))
        .toList();
    if (spots.length < 3) return const SizedBox.shrink();

    final n = spots.length;
    double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
    for (final s in spots) {
      sumX += s.x;
      sumY += s.y;
      sumXY += s.x * s.y;
      sumX2 += s.x * s.x;
    }
    final slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
    final intercept = (sumY - slope * sumX) / n;

    final userSettingsAsync = ref.read(userSettingsProvider);
    final us = userSettingsAsync.valueOrNull;
    if (us?.targetWeightKg == null || slope == 0) return const SizedBox.shrink();

    final targetJin = us!.targetWeightKg! * 2;
    final lastX = spots.last.x;
    final days = ((targetJin - intercept) / slope - lastX).round();
    if (days <= 0 || days > 365) return const SizedBox.shrink();

    final direction = slope < 0 ? '下降' : '上升';
    final weeklyChange = (slope.abs() * 7).toStringAsFixed(2);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        '📈 按当前趋势（每周$direction $weeklyChange斤），预计 $days 天后达到目标体重',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w500,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildChart(List<BodyMetricEntity> metrics, ThemeData theme) {
    final validMetrics = metrics.where((m) {
      switch (_metricType) {
        case 'waist':
          return m.waistCm != null;
        case 'hip':
          return m.hipCm != null;
        case 'chest':
          return m.chestCm != null;
        default:
          return true;
      }
    }).toList();

    if (validMetrics.length < 2) {
      return Center(
          child: Text('至少需要 2 条数据',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.outline)));
    }

    double getValue(BodyMetricEntity m) {
      switch (_metricType) {
        case 'waist':
          return m.waistCm!;
        case 'hip':
          return m.hipCm!;
        case 'chest':
          return m.chestCm!;
        default:
          return m.weightKg * 2; // 转换为斤
      }
    }

    final suffix = _metricType == 'weight' ? ' 斤' : ' cm';
    final spots = validMetrics.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), getValue(e.value)))
        .toList();

    // ── 线性回归预测（仅体重） ──
    List<FlSpot> predictSpots = [];
    if (_metricType == 'weight' && spots.length >= 3) {
      final n = spots.length;
      double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
      for (final s in spots) {
        sumX += s.x;
        sumY += s.y;
        sumXY += s.x * s.y;
        sumX2 += s.x * s.x;
      }
      final slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
      final intercept = (sumY - slope * sumX) / n;

      // 预测未来30天
      final lastX = spots.last.x;
      for (int i = 1; i <= 30; i++) {
        final px = lastX + i;
        final py = slope * px + intercept;
        if (py > 0) predictSpots.add(FlSpot(px, py));
      }
    }

    // 计算 Y 轴范围（包含预测值）
    final allY = [...spots.map((s) => s.y), ...predictSpots.map((s) => s.y)];
    final minY = allY.reduce((a, b) => a < b ? a : b) - 1;
    final maxY = allY.reduce((a, b) => a > b ? a : b) + 1;

    final lineBars = <LineChartBarData>[
      LineChartBarData(
        spots: spots,
        isCurved: true,
        color: theme.colorScheme.primary,
        barWidth: 2.5,
        dotData: FlDotData(
            show: validMetrics.length <= 60,
            getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                radius: 3,
                color: theme.colorScheme.primary,
                strokeWidth: 0)),
        belowBarData:
            BarAreaData(show: true, color: theme.colorScheme.primary.withAlpha(30)),
      ),
    ];

    if (predictSpots.isNotEmpty) {
      lineBars.add(LineChartBarData(
        spots: [spots.last, ...predictSpots],
        isCurved: false,
        color: theme.colorScheme.tertiary.withAlpha(180),
        barWidth: 1.5,
        dashArray: [5, 5],
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(show: false),
      ));
    }

    return LineChart(LineChartData(
      minY: minY,
      maxY: maxY,
      gridData: FlGridData(
          show: true,
          horizontalInterval: 1,
          getDrawingHorizontalLine: (v) => FlLine(
              color: theme.colorScheme.outline.withAlpha(40), strokeWidth: 0.5),
          drawVerticalLine: false),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
            sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                getTitlesWidget: (value, meta) => Text('${value.toInt()}',
                    style: TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.outline)))),
        bottomTitles: AxisTitles(
            sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 34,
                interval: (validMetrics.length / 6)
                    .ceilToDouble()
                    .clamp(1, double.infinity),
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= validMetrics.length) {
                    return const SizedBox.shrink();
                  }
                  return Transform.rotate(
                      angle: -0.7,
                      child: Text(
                          DateFormat('M/dd').format(validMetrics[i].date),
                          style: TextStyle(
                              fontSize: 9,
                              color: theme.colorScheme.outline)));
                })),
        topTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(show: false),
      lineBarsData: lineBars,
      lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) => spots
                  .map((s) => LineTooltipItem(
                      '${s.y.toStringAsFixed(1)}$suffix',
                      TextStyle(
                          color: theme.colorScheme.onInverseSurface,
                          fontSize: 12)))
                  .toList())),
    ));
  }
}

/// 三联概览小卡
class _MiniStatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MiniStatCard({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline, fontSize: 10),
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        height: 1.0,
                        color: color),
                  ),
                  Text(
                    ' 斤',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline, fontSize: 9),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 历史记录紧凑行（高 56）
class _HistoryRow extends StatelessWidget {
  final BodyMetricEntity metric;
  final Future<void> Function() onDelete;

  const _HistoryRow({required this.metric, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.only(left: 14, right: 2),
          child: Row(
            children: [
              SizedBox(
                width: 62,
                child: Text(
                  DateFormat('MM/dd').format(metric.date),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ),
              Text(
                (metric.weightKg * 2).toStringAsFixed(1),
                style: theme.textTheme.bodyLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 3),
              Text(
                '斤',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline, fontSize: 10),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                color: theme.colorScheme.outline,
                onPressed: () => onDelete(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BodyData {
  final List<BodyMetricEntity> metrics;
  final List<Photo> photos;
  const _BodyData({this.metrics = const [], this.photos = const []});
}

// ───────────────────── 录入表单（精简模式） ─────────────────────

class _AddMetricForm extends StatefulWidget {
  final BodyMetricRepository bodyRepo;
  final PhotoRepository photoRepo;
  final GoalRepository goalRepo;
  final VoidCallback onSaved;

  const _AddMetricForm({
    required this.bodyRepo,
    required this.photoRepo,
    required this.goalRepo,
    required this.onSaved,
  });

  @override
  State<_AddMetricForm> createState() => _AddMetricFormState();
}

class _AddMetricFormState extends State<_AddMetricForm> {
  final _weightCtrl = TextEditingController();
  final _waistCtrl = TextEditingController();
  final _hipCtrl = TextEditingController();
  final _chestCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  DateTime _date = DateTime.now();
  File? _photoFile;
  final _picker = ImagePicker();

  @override
  void dispose() {
    _weightCtrl.dispose();
    _waistCtrl.dispose();
    _hipCtrl.dispose();
    _chestCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    final file =
        await _picker.pickImage(source: ImageSource.camera, maxWidth: 1080);
    if (file != null) {
      setState(() => _photoFile = File(file.path));
    }
  }

  void _removePhoto() => setState(() => _photoFile = null);

  void _showWeightFeedback(double currentJin) async {
    // 查询上次体重（倒数第二条记录）
    final allMetrics = await widget.bodyRepo.getAll();
    double? changeJin;
    double? totalLossJin;

    if (allMetrics.length >= 2) {
      final prev = allMetrics[allMetrics.length - 2];
      changeJin = currentJin - prev.weightKg * 2;
    }

    // 累计减重（首条 vs 当前）
    if (allMetrics.isNotEmpty) {
      final first = allMetrics.first;
      totalLossJin = first.weightKg * 2 - currentJin;
    }

    await NotificationService().showWeightFeedback(
      currentWeightJin: currentJin,
      changeJin: changeJin,
      totalLossJin:
          totalLossJin != null && totalLossJin > 0 ? totalLossJin : null,
    );
  }

  /// 计算累计减重的 5 斤档位（0, 1, 2, ... 代表 0斤, 5斤, 10斤...）
  int _milestoneLevel(List<BodyMetricEntity> metrics) {
    if (metrics.length < 2) return 0;
    final lossJin = (metrics.first.weightKg - metrics.last.weightKg) * 2;
    return lossJin > 0 ? (lossJin ~/ 5) : 0;
  }

  /// 检测是否跨过新的 5 斤里程碑
  void _checkMilestone(int oldLevel) async {
    final metricsAfter = await widget.bodyRepo.getAll();
    final newLevel = _milestoneLevel(metricsAfter);
    if (newLevel > oldLevel && newLevel > 0 && mounted) {
      _showMilestoneDialog(newLevel * 5, metricsAfter);
    }
  }

  /// 里程碑庆祝全屏弹窗
  void _showMilestoneDialog(int totalLossJin, List<BodyMetricEntity> metrics) {
    final firstWeightJin = (metrics.first.weightKg * 2).toStringAsFixed(1);
    final currentWeightJin = (metrics.last.weightKg * 2).toStringAsFixed(1);
    final days = metrics.last.date.difference(metrics.first.date).inDays;
    final theme = Theme.of(context);

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutBack,
        builder: (context, value, child) {
          return Transform.scale(
            scale: value,
            child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
          );
        },
        child: Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🎉', style: TextStyle(fontSize: 56)),
                const SizedBox(height: 16),
                Text('太棒了！',
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('你已累计减重', style: theme.textTheme.bodyLarge),
                const SizedBox(height: 4),
                Text(
                  '$totalLossJin 斤',
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 20),
                Divider(color: theme.colorScheme.outline.withAlpha(50)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('$firstWeightJin 斤',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.outline)),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Icon(Icons.arrow_forward, size: 18),
                    ),
                    Text('$currentWeightJin 斤',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 4),
                Text('用时 $days 天',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline)),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('继续努力 💪'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 标题 + 日期（一行） ──
        Row(
          children: [
            Text('录入数据', style: theme.textTheme.titleSmall),
            const Spacer(),
            TextButton.icon(
              onPressed: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                  locale: const Locale('zh'),
                );
                if (date != null) setState(() => _date = date);
              },
              icon: const Icon(Icons.calendar_today, size: 15),
              label: Text(DateFormat('M月d日').format(_date),
                  style: const TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),

        // ── 体重（必填） ──
        TextField(
          controller: _weightCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
              labelText: '体重', suffixText: '斤', isDense: true),
        ),
        const SizedBox(height: 4),

        // ── 更多数据（围度 / 备注 / 拍照） ──
        Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: false,
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 4),
            dense: true,
            iconColor: theme.colorScheme.outline,
            collapsedIconColor: theme.colorScheme.outline,
            title: Text(
              '更多数据（围度 / 备注 / 拍照）',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            children: [
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _waistCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: '腰围', suffixText: 'cm', isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _hipCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: '臀围', suffixText: 'cm', isDense: true),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              TextField(
                controller: _chestCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: '胸围', suffixText: 'cm', isDense: true),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _noteCtrl,
                decoration:
                    const InputDecoration(labelText: '备注（可选）', isDense: true),
              ),
              const SizedBox(height: 10),
              if (_photoFile != null)
                Stack(
                  alignment: Alignment.topRight,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        _photoFile!,
                        height: 140,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      style: IconButton.styleFrom(
                          backgroundColor: Colors.black45),
                      onPressed: _removePhoto,
                    ),
                  ],
                )
              else
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _takePhoto,
                    icon: const Icon(Icons.camera_alt, size: 16),
                    label: const Text('拍照记录', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 34),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // ── 保存 ──
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: Colors.black,
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('保存',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final weight = double.tryParse(_weightCtrl.text);
    if (weight == null || weight <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('请输入有效的体重')));
      }
      return;
    }

    // 里程碑检测：保存前的累计减重等级
    final metricsBefore = await widget.bodyRepo.getAll();
    final oldLevel = _milestoneLevel(metricsBefore);

    // 检查当日是否已有记录
    final existingEntries = await widget.bodyRepo.getAll(
      from: DateTime(_date.year, _date.month, _date.day),
      to: DateTime(_date.year, _date.month, _date.day),
    );

    if (existingEntries.isNotEmpty) {
      // 当日已有记录，更新第一条
      final existing = existingEntries.first;
      await widget.bodyRepo.update(
        id: existing.id,
        date: _date,
        weightKg: weight / 2,
        waistCm: double.tryParse(_waistCtrl.text),
        hipCm: double.tryParse(_hipCtrl.text),
        chestCm: double.tryParse(_chestCtrl.text),
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      );

      // 保存照片
      if (_photoFile != null) {
        await widget.photoRepo.addPhoto(
          date: _date,
          imageFile: _photoFile!,
          note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        );
      }

      // 自动更新体重目标进度
      final goals = await widget.goalRepo.getAll();
      for (final g in goals.where((g) => g.type == 'weight' && !g.isCompleted)) {
        await widget.goalRepo.updateProgress(g.id, weight);
      }

      // 即时反馈通知
      _showWeightFeedback(weight);

      // 里程碑检测
      _checkMilestone(oldLevel);

      _clearInputs();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已更新当日体重记录')));
      }
      widget.onSaved();
      return;
    }

    // 保存身体数据
    await widget.bodyRepo.create(
      date: _date,
      weightKg: weight / 2,
      waistCm: double.tryParse(_waistCtrl.text),
      hipCm: double.tryParse(_hipCtrl.text),
      chestCm: double.tryParse(_chestCtrl.text),
      note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
    );

    // 保存照片
    if (_photoFile != null) {
      await widget.photoRepo.addPhoto(
        date: _date,
        imageFile: _photoFile!,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      );
    }

    // 自动更新体重目标进度
    final goals = await widget.goalRepo.getAll();
    for (final g in goals.where((g) => g.type == 'weight' && !g.isCompleted)) {
      await widget.goalRepo.updateProgress(g.id, weight);
    }

    // 即时反馈通知
    _showWeightFeedback(weight);

    // 里程碑检测
    _checkMilestone(oldLevel);

    _clearInputs();
    widget.onSaved();
  }

  /// 清空表单（保留日期）
  void _clearInputs() {
    _weightCtrl.clear();
    _waistCtrl.clear();
    _hipCtrl.clear();
    _chestCtrl.clear();
    _noteCtrl.clear();
    setState(() => _photoFile = null);
  }
}
