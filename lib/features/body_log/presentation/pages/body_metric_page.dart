import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      case 'week': from = now.subtract(const Duration(days: 7));
      case 'quarter': from = now.subtract(const Duration(days: 90));
      case 'all': from = DateTime(2020);
      default: from = now.subtract(const Duration(days: 30));
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
            padding: const EdgeInsets.all(16),
            children: [
              // ── 最新体重卡片 ──
              if (data.metrics.isNotEmpty) ...[
                _buildWeightCard(theme, data.metrics.last, ref),
                const SizedBox(height: 20),
              ],

              // ── 趋势图 ──
              Text('${_metricLabels[_metricType] ?? '体重'}趋势',
                style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'week', label: Text('周', style: TextStyle(fontSize: 12))),
                      ButtonSegment(value: 'month', label: Text('月', style: TextStyle(fontSize: 12))),
                      ButtonSegment(value: 'quarter', label: Text('季', style: TextStyle(fontSize: 12))),
                      ButtonSegment(value: 'all', label: Text('全部', style: TextStyle(fontSize: 12))),
                    ],
                    selected: {_timeRange},
                    onSelectionChanged: (v) => setState(() => _timeRange = v.first),
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  ),
              ),
              const SizedBox(height: 12),
              if (data.metrics.isEmpty)
                Card(
                  child: const SizedBox(height: 200,
                    child: Center(child: Text('暂无数据', style: TextStyle(color: Colors.grey)))),
                )
              else
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
                    child: _buildChartWithPrediction(data.metrics, theme),
                  ),
                ),
              if (data.metrics.isNotEmpty) ...[
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ['weight', 'waist', 'hip', 'chest'].map((type) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(_metricLabels[type] ?? type),
                          selected: _metricType == type,
                          onSelected: (_) => setState(() => _metricType = type),
                          visualDensity: VisualDensity.compact,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
              const SizedBox(height: 20),

              // ── 录入表单 ──
              Card(
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
              const SizedBox(height: 20),

              // ── 照片栏 ──
              Row(
                children: [
                  Text('记录照片', style: theme.textTheme.titleMedium),
                  const Spacer(),
                  if (data.photos.length >= 2)
                    TextButton.icon(
                      onPressed: () => _showComparePicker(context, data.photos),
                      icon: const Icon(Icons.compare, size: 16),
                      label: const Text('对比', style: TextStyle(fontSize: 13)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (data.photos.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text('还没有照片\n录入数据时可以拍照记录',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.outline)),
                    ),
                  ),
                )
              else
                _PhotoGrid(photos: data.photos, photoRepo: photoRepo, onChanged: () => setState(() {})),

              const SizedBox(height: 16),

              // ── 历史记录 ──
              if (data.metrics.isNotEmpty) ...[
                Text('历史记录', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                ...data.metrics.reversed.take(10).map((m) => ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Text('${(m.weightKg * 2).toStringAsFixed(1)}'.substring(0, 4),
                      style: TextStyle(fontSize: 10, color: theme.colorScheme.onPrimaryContainer)),
                  ),
                  title: Text('${(m.weightKg * 2).toStringAsFixed(1)} 斤',
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  subtitle: Text(DateFormat('yyyy/MM/dd').format(m.date),
                    style: theme.textTheme.bodySmall),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () async {
                      await bodyRepo.delete(m.id);
                      setState(() {});
                    },
                  ),
                )),
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

  Widget _buildWeightCard(ThemeData theme, BodyMetricEntity latestMetric, WidgetRef ref) {
    final userSettingsAsync = ref.watch(userSettingsProvider);
    final userSettings = userSettingsAsync.valueOrNull;

    // BMI 颜色
    Color? cardColor;
    Color? iconAndBadgeColor;
    if (userSettings?.heightCm != null) {
      final bmi = userSettings!.bmi(latestMetric.weightKg);
      if (bmi != null) {
        final level = UserSettingsEntity.bmiLevel(bmi);
        switch (level) {
          case 'normal':
            cardColor = Colors.green.withAlpha(25);
            iconAndBadgeColor = Colors.green;
          case 'overweight':
            cardColor = Colors.orange.withAlpha(40);
            iconAndBadgeColor = Colors.orange;
          case 'obese':
            cardColor = Colors.red.withAlpha(40);
            iconAndBadgeColor = Colors.red;
          default:
            cardColor = Colors.blue.withAlpha(20);
            iconAndBadgeColor = Colors.blue;
        }
      }
    }

    final targetJin = userSettings?.targetWeightKg != null
      ? (userSettings!.targetWeightKg! * 2).toStringAsFixed(1)
      : null;

    final bmiVal = userSettings?.bmi(latestMetric.weightKg);
    final levelLabel = bmiVal != null
      ? UserSettingsEntity.bmiLevelLabels[UserSettingsEntity.bmiLevel(bmiVal)]
      : null;

    return Card(
      color: cardColor ?? theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.monitor_weight, size: 36,
                  color: iconAndBadgeColor ?? theme.colorScheme.onPrimaryContainer),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('最新体重',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: (cardColor != null ? iconAndBadgeColor : theme.colorScheme.onPrimaryContainer)?.withAlpha(180))),
                    Text('${(latestMetric.weightKg * 2).toStringAsFixed(1)} 斤',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: iconAndBadgeColor ?? theme.colorScheme.onPrimaryContainer)),
                  ],
                ),
              ],
            ),
            if (iconAndBadgeColor != null || targetJin != null) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (iconAndBadgeColor != null && bmiVal != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: iconAndBadgeColor.withAlpha(30),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'BMI ${bmiVal.toStringAsFixed(1)} · $levelLabel',
                        style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600, color: iconAndBadgeColor),
                      ),
                    ),
                  if (iconAndBadgeColor != null && targetJin != null) const SizedBox(width: 10),
                  if (targetJin != null)
                    Text('目标 $targetJin 斤',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static const _metricLabels = {
    'weight': '体重', 'waist': '腰围', 'hip': '臀围', 'chest': '胸围',
  };

  Widget _buildChartWithPrediction(List<BodyMetricEntity> metrics, ThemeData theme) {
    return Column(
      children: [
        SizedBox(height: 220, child: _buildChart(metrics, theme)),
        if (_metricType == 'weight' && metrics.length >= 3)
          _buildPredictionText(metrics, theme),
      ],
    );
  }

  Widget _buildPredictionText(List<BodyMetricEntity> metrics, ThemeData theme) {
    final validMetrics = metrics.where((m) => true).toList();
    final spots = validMetrics.asMap().entries
      .map((e) => FlSpot(e.key.toDouble(), e.value.weightKg)).toList();
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
        '📈 按当前趋势（每周$direction ${weeklyChange}斤），预计 $days 天后达到目标体重',
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
        case 'waist': return m.waistCm != null;
        case 'hip': return m.hipCm != null;
        case 'chest': return m.chestCm != null;
        default: return true;
      }
    }).toList();

    if (validMetrics.length < 2) {
      return Center(child: Text('至少需要 2 条数据',
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)));
    }

    double getValue(BodyMetricEntity m) {
      switch (_metricType) {
        case 'waist': return m.waistCm!;
        case 'hip': return m.hipCm!;
        case 'chest': return m.chestCm!;
        default: return m.weightKg * 2; // 转换为斤
      }
    }

    final suffix = _metricType == 'weight' ? ' 斤' : ' cm';
    final spots = validMetrics.asMap().entries
      .map((e) => FlSpot(e.key.toDouble(), getValue(e.value))).toList();

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
        spots: spots, isCurved: true,
        color: theme.colorScheme.primary, barWidth: 2.5,
        dotData: FlDotData(show: validMetrics.length <= 60,
          getDotPainter: (spot, percent, bar, index) =>
            FlDotCirclePainter(radius: 3, color: theme.colorScheme.primary, strokeWidth: 0)),
        belowBarData: BarAreaData(show: true,
          color: theme.colorScheme.primary.withAlpha(30))),
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
      minY: minY, maxY: maxY,
      gridData: FlGridData(show: true, horizontalInterval: 1,
        getDrawingHorizontalLine: (v) =>
          FlLine(color: theme.colorScheme.outline.withAlpha(40), strokeWidth: 0.5),
        drawVerticalLine: false),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40,
          getTitlesWidget: (value, meta) =>
            Text('${value.toInt()}', style: TextStyle(fontSize: 10, color: theme.colorScheme.outline)))),
        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 34,
          interval: (validMetrics.length / 6).ceilToDouble().clamp(1, double.infinity),
          getTitlesWidget: (value, meta) {
            final i = value.toInt();
            if (i < 0 || i >= validMetrics.length) return const SizedBox.shrink();
            return Transform.rotate(angle: -0.7,
              child: Text(DateFormat('M/dd').format(validMetrics[i].date),
                style: TextStyle(fontSize: 9, color: theme.colorScheme.outline)));
          })),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(show: false),
      lineBarsData: lineBars,
      lineTouchData: LineTouchData(touchTooltipData: LineTouchTooltipData(
        getTooltipItems: (spots) => spots.map((s) =>
          LineTooltipItem('${s.y.toStringAsFixed(1)}$suffix',
            TextStyle(color: theme.colorScheme.onInverseSurface, fontSize: 12))).toList()))),
    );
  }
}

/// 页面数据
class _BodyData {
  final List<BodyMetricEntity> metrics;
  final List<Photo> photos;
  const _BodyData({this.metrics = const [], this.photos = const []});
}

// ───────────────────── 录入表单 ─────────────────────

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
  bool _showAdvanced = false;
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
    final file = await _picker.pickImage(source: ImageSource.camera, maxWidth: 1080);
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
      totalLossJin: totalLossJin != null && totalLossJin > 0 ? totalLossJin : null,
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
                Text('太棒了！', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
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
                    Text('$firstWeightJin 斤', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Icon(Icons.arrow_forward, size: 18),
                    ),
                    Text('$currentWeightJin 斤', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 4),
                Text('用时 $days 天', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
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
        Text('录入数据', style: theme.textTheme.titleSmall),
        const SizedBox(height: 12),

        // ── 日期（中文选择器） ──
        Row(children: [
          Text('日期: ', style: theme.textTheme.bodyMedium),
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
            icon: const Icon(Icons.calendar_today, size: 16),
            label: Text(DateFormat('yyyy年M月d日').format(_date)),
          ),
        ]),
        const SizedBox(height: 12),

        // ── 体重 ──
        TextField(
          controller: _weightCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: '体重', suffixText: '斤', isDense: true),
        ),
        const SizedBox(height: 8),

        // ── 围度展开 ──
        InkWell(
          onTap: () => setState(() => _showAdvanced = !_showAdvanced),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              Icon(_showAdvanced ? Icons.expand_less : Icons.expand_more,
                size: 18, color: theme.colorScheme.primary),
              Text(' 围度测量（可选）',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary)),
            ]),
          ),
        ),
        if (_showAdvanced) ...[
          const SizedBox(height: 4),
          Row(children: [
            Expanded(child: TextField(
              controller: _waistCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: '腰围', suffixText: 'cm', isDense: true))),
            const SizedBox(width: 8),
            Expanded(child: TextField(
              controller: _hipCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: '臀围', suffixText: 'cm', isDense: true))),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: _chestCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: '胸围', suffixText: 'cm', isDense: true)),
        ],

        // ── 拍照 ──
        const SizedBox(height: 12),
        Text('记录照片', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
        const SizedBox(height: 6),
        if (_photoFile != null)
          Stack(
            alignment: Alignment.topRight,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  _photoFile!,
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                style: IconButton.styleFrom(backgroundColor: Colors.black45),
                onPressed: _removePhoto,
              ),
            ],
          )
        else
          OutlinedButton.icon(
            onPressed: _takePhoto,
            icon: const Icon(Icons.camera_alt, size: 18),
            label: const Text('拍照记录'),
          ),

        const SizedBox(height: 8),
        TextField(
          controller: _noteCtrl,
          decoration: const InputDecoration(labelText: '备注（可选）', isDense: true)),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save, size: 18),
            label: const Text('保存'),
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final weight = double.tryParse(_weightCtrl.text);
    if (weight == null || weight <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请输入有效的体重')));
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

      _weightCtrl.clear();
      _waistCtrl.clear();
      _hipCtrl.clear();
      _chestCtrl.clear();
      _noteCtrl.clear();
      setState(() => _photoFile = null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已更新当日体重记录')));
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

    _weightCtrl.clear();
    _waistCtrl.clear();
    _hipCtrl.clear();
    _chestCtrl.clear();
    _noteCtrl.clear();
    setState(() => _photoFile = null);
    widget.onSaved();
  }
}

// ───────────────────── 照片网格 ─────────────────────

  void _showComparePicker(BuildContext context, List<Photo> photos) {
    int? leftIndex;
    int? rightIndex;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('选择对比照片'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('选择两张照片进行前后对比',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(color: Theme.of(ctx).colorScheme.outline)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _ComparePhotoSlot(
                        label: '之前',
                        photos: photos,
                        selectedIndex: leftIndex,
                        onSelected: (i) => setDlgState(() => leftIndex = i),
                        excludeIndex: rightIndex,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(Icons.arrow_forward, size: 24),
                    ),
                    Expanded(
                      child: _ComparePhotoSlot(
                        label: '之后',
                        photos: photos,
                        selectedIndex: rightIndex,
                        onSelected: (i) => setDlgState(() => rightIndex = i),
                        excludeIndex: leftIndex,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: leftIndex != null && rightIndex != null
                ? () {
                    Navigator.pop(ctx);
                    _showCompareView(context, photos[leftIndex!], photos[rightIndex!]);
                  }
                : null,
              child: const Text('对比'),
            ),
          ],
        ),
      ),
    );
  }

  void _showCompareView(BuildContext context, Photo before, Photo after) {
    final dateFmt = DateFormat('M月d日');
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text('${dateFmt.format(before.date)} → ${dateFmt.format(after.date)}'),
        ),
        body: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text('之前 · ${dateFmt.format(before.date)}',
                            style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        ),
                        Expanded(
                          child: InteractiveViewer(
                            child: Image.file(File(before.filePath), fit: BoxFit.contain),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(width: 1, color: Colors.white24),
                  Expanded(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text('之后 · ${dateFmt.format(after.date)}',
                            style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        ),
                        Expanded(
                          child: InteractiveViewer(
                            child: Image.file(File(after.filePath), fit: BoxFit.contain),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '${before.date.difference(after.date).inDays.abs()} 天的变化',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ),
    ));
  }

class _ComparePhotoSlot extends StatelessWidget {
  final String label;
  final List<Photo> photos;
  final int? selectedIndex;
  final ValueChanged<int> onSelected;
  final int? excludeIndex;

  const _ComparePhotoSlot({
    required this.label,
    required this.photos,
    required this.selectedIndex,
    required this.onSelected,
    this.excludeIndex,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFmt = DateFormat('M月d日');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
        const SizedBox(height: 6),
        if (selectedIndex != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              children: [
                Image.file(File(photos[selectedIndex!].filePath), height: 100, width: double.infinity, fit: BoxFit.cover),
                Positioned(
                  top: 4, right: 4,
                  child: IconButton(
                    icon: const Icon(Icons.close, size: 16, color: Colors.white),
                    style: IconButton.styleFrom(backgroundColor: Colors.black45, padding: EdgeInsets.zero, minimumSize: const Size(24, 24)),
                    onPressed: () => onSelected(-1),
                  ),
                ),
                Positioned(
                  bottom: 0, left: 0, right: 0,
                  child: Container(
                    color: Colors.black54,
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(dateFmt.format(photos[selectedIndex!].date), textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 10)),
                  ),
                ),
              ],
            ),
          )
        else
          SizedBox(
            height: 100,
            child: OutlinedButton(
              onPressed: () => _showSelectSheet(context),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Icon(Icons.add_photo_alternate, size: 28),
            ),
          ),
      ],
    );
  }

  void _showSelectSheet(BuildContext context) {
    final dateFmt = DateFormat('M月d日');
    showModalBottomSheet(
      context: context,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        children: [
          for (int i = 0; i < photos.length; i++)
            if (i != (excludeIndex ?? -1))
              ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.file(File(photos[i].filePath), width: 48, height: 48, fit: BoxFit.cover),
                ),
                title: Text(dateFmt.format(photos[i].date)),
                trailing: photos[i].note != null ? Text(photos[i].note!, style: Theme.of(ctx).textTheme.bodySmall) : null,
                onTap: () {
                  onSelected(i);
                  Navigator.pop(ctx);
                },
              ),
        ],
      ),
    );
  }
}

class _PhotoGrid extends StatelessWidget {
  final List<Photo> photos;
  final PhotoRepository photoRepo;
  final VoidCallback onChanged;

  const _PhotoGrid({
    required this.photos,
    required this.photoRepo,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('M月d日');

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: photos.length,
      itemBuilder: (context, index) {
        final photo = photos[index];
        return GestureDetector(
          onTap: () => _showFullScreen(context, photo),
          onLongPress: () => _confirmDelete(context, photo),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(photo.filePath),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stack) => Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.broken_image, color: Colors.grey),
                  ),
                ),
              ),
              // 日期标签
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
                  ),
                  child: Text(
                    dateFmt.format(photo.date),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showFullScreen(BuildContext context, Photo photo) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        child: Stack(
          fit: StackFit.expand,
          children: [
            InteractiveViewer(child: Image.file(File(photo.filePath), fit: BoxFit.contain)),
            Positioned(
              top: 48, left: 16,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                style: IconButton.styleFrom(backgroundColor: Colors.black38),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
            if (photo.note != null)
              Positioned(
                bottom: 32, left: 16, right: 16,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(photo.note!,
                    style: const TextStyle(color: Colors.white, fontSize: 13)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, Photo photo) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除照片'),
        content: const Text('确定要删除这张照片吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              await photoRepo.delete(photo.id);
              Navigator.pop(ctx);
              onChanged();
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
