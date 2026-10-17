import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/features/settings/domain/entities/user_settings_entity.dart';

const _green = Color(0xFF66BB6A);
const _amber = Color(0xFFFFA726);
const _orange = Color(0xFFFF7043);
const _purple = Color(0xFFAB47BC);
const _red = Color(0xFFEF5350);

class MonthlyComparePage extends ConsumerWidget {
  const MonthlyComparePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bodyRepo = ref.watch(bodyMetricRepoProvider);
    final workoutRepo = ref.watch(workoutRepoProvider);
    final dietRepo = ref.watch(dietRepoProvider);
    final userSettingsAsync = ref.watch(userSettingsProvider);
    final theme = Theme.of(context);

    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final lastMonthStart = DateTime(now.year, now.month - 1, 1);
    final lastMonthEnd = DateTime(now.year, now.month, 0); // last day of prev month

    return Scaffold(
      appBar: AppBar(title: const Text('月度对比')),
      body: FutureBuilder<_MonthCompareData>(
        future: _loadData(bodyRepo, workoutRepo, dietRepo, lastMonthStart, lastMonthEnd, monthStart, now),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data ?? const _MonthCompareData();
          final us = userSettingsAsync.valueOrNull;

          if (data.thisMonthAvg == null && data.lastMonthAvg == null && data.thisMonthWorkoutDays == 0) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_graph, size: 64, color: theme.colorScheme.outline),
                  const SizedBox(height: 16),
                  Text('数据不足以生成月度对比', style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.outline)),
                  const SizedBox(height: 4),
                  Text('至少需要两个月的体重数据', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                ],
              ),
            );
          }

          final cardKey = GlobalKey();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              // 对比卡片
              RepaintBoundary(
                key: cardKey,
                child: Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
                    child: Column(
                      children: [
                        // 卡头
                        Row(
                          children: [
                            Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: _purple.withAlpha(32),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.calendar_view_month,
                                  size: 16, color: _purple),
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('月度报告',
                                    style: theme.textTheme.titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(
                                  '${DateFormat('M月').format(lastMonthStart)} vs ${DateFormat('M月').format(monthStart)}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.outline,
                                      fontSize: 10),
                                ),
                              ],
                            ),
                            const Spacer(),
                            const Text('简瘦',
                                style: TextStyle(
                                    fontSize: 10, color: Colors.white38)),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Container(height: 1, color: Colors.white.withAlpha(14)),
                        const SizedBox(height: 8),
                        if (data.lastMonthAvg != null && data.thisMonthAvg != null) ...[
                          _buildWeightCompare(theme, data),
                          Container(height: 1, color: Colors.white.withAlpha(10)),
                        ],
                        _buildTrainingCompare(theme, data),
                        if (data.lastMonthAvgCal != null && data.thisMonthAvgCal != null) ...[
                          Container(height: 1, color: Colors.white.withAlpha(10)),
                          _buildDietCompare(theme, data, us),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // 分享按钮
              SizedBox(
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: () => _shareCard(context, cardKey),
                  icon: const Icon(Icons.ios_share, size: 16),
                  label: const Text('分享月度报告',
                      style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _purple,
                    side: BorderSide(color: _purple.withAlpha(90)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildWeightCompare(ThemeData theme, _MonthCompareData data) {
    final delta = data.thisMonthAvg! - data.lastMonthAvg!;
    return _CompareRow(
      icon: Icons.monitor_weight,
      color: _amber,
      label: '月均体重',
      lastValue: '${(data.lastMonthAvg! * 2).toStringAsFixed(1)} 斤',
      thisValue: '${(data.thisMonthAvg! * 2).toStringAsFixed(1)} 斤',
      deltaText: delta.abs() < 0.05
          ? '持平'
          : '${delta < 0 ? '↓' : '↑'} ${delta.abs().toStringAsFixed(1)} 斤',
      deltaColor: delta.abs() < 0.05
          ? Colors.white54
          : (delta < 0 ? _green : _red),
    );
  }

  Widget _buildTrainingCompare(ThemeData theme, _MonthCompareData data) {
    final delta = data.thisMonthWorkoutDays - data.lastMonthWorkoutDays;
    return _CompareRow(
      icon: Icons.fitness_center,
      color: _green,
      label: '训练天数',
      lastValue: '${data.lastMonthWorkoutDays} 天',
      thisValue: '${data.thisMonthWorkoutDays} 天',
      deltaText: delta == 0 ? '持平' : '${delta > 0 ? '+' : ''}$delta 天',
      deltaColor:
          delta == 0 ? Colors.white54 : (delta > 0 ? _green : _red),
    );
  }

  Widget _buildDietCompare(
      ThemeData theme, _MonthCompareData data, UserSettingsEntity? us) {
    final lastDeficit =
        us?.tdee() != null ? us!.tdee()! - data.lastMonthAvgCal! : null;
    final thisDeficit =
        us?.tdee() != null ? us!.tdee()! - data.thisMonthAvgCal! : null;
    final delta = (lastDeficit != null && thisDeficit != null)
        ? thisDeficit - lastDeficit
        : null;

    return _CompareRow(
      icon: Icons.restaurant,
      color: _orange,
      label: '日均摄入',
      lastValue: '${data.lastMonthAvgCal!.toInt()} kcal',
      thisValue: '${data.thisMonthAvgCal!.toInt()} kcal',
      deltaText: delta == null
          ? null
          : (delta.abs() < 1
              ? '缺口持平'
              : '缺口 ${delta > 0 ? '+' : ''}${delta.toInt()}'),
      deltaColor:
          delta == null ? null : (delta > 0 ? _green : _red),
    );
  }

  Future<_MonthCompareData> _loadData(repos, workoutRepo, dietRepo, lastStart, lastEnd, thisStart, thisEnd) async {
    final lastMetrics = await repos.getAll(from: lastStart, to: lastEnd);
    final thisMetrics = await repos.getAll(from: thisStart, to: thisEnd);
    final lastWorkouts = await workoutRepo.getAll(from: lastStart, to: lastEnd);
    final thisWorkouts = await workoutRepo.getAll(from: thisStart, to: thisEnd);

    // 月均体重
    double? lastAvg;
    if (lastMetrics.isNotEmpty) lastAvg = lastMetrics.map((m) => m.weightKg).reduce((a, b) => a + b) / lastMetrics.length;
    double? thisAvg;
    if (thisMetrics.isNotEmpty) thisAvg = thisMetrics.map((m) => m.weightKg).reduce((a, b) => a + b) / thisMetrics.length;

    // 训练天数
    final lastWorkoutDays = lastWorkouts.map((w) => DateTime(w.date.year, w.date.month, w.date.day)).toSet().length;
    final thisWorkoutDays = thisWorkouts.map((w) => DateTime(w.date.year, w.date.month, w.date.day)).toSet().length;

    // 月均热量
    double? lastAvgCal, thisAvgCal;
    final lastDays = lastEnd.difference(lastStart).inDays + 1;
    final thisDays = DateTime.now().difference(thisStart).inDays + 1;
    double lastTotal = 0, thisTotal = 0;
    int lastCount = 0, thisCount = 0;
    for (int i = 0; i < lastDays; i++) {
      final cal = await dietRepo.getDailyCalories(lastStart.add(Duration(days: i)));
      if (cal > 0) { lastTotal += cal; lastCount++; }
    }
    for (int i = 0; i < thisDays; i++) {
      final day = thisStart.add(Duration(days: i));
      if (day.isAfter(DateTime.now())) break;
      final cal = await dietRepo.getDailyCalories(day);
      if (cal > 0) { thisTotal += cal; thisCount++; }
    }
    if (lastCount > 0) lastAvgCal = lastTotal / lastCount;
    if (thisCount > 0) thisAvgCal = thisTotal / thisCount;

    return _MonthCompareData(
      lastMonthAvg: lastAvg,
      thisMonthAvg: thisAvg,
      lastMonthWorkoutDays: lastWorkoutDays,
      thisMonthWorkoutDays: thisWorkoutDays,
      lastMonthAvgCal: lastAvgCal,
      thisMonthAvgCal: thisAvgCal,
    );
  }

  Future<void> _shareCard(BuildContext context, GlobalKey cardKey) async {
    try {
      final boundary = cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/monthly_report_${DateFormat('yyyyMM').format(DateTime.now())}.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());
      await Share.shareXFiles([XFile(file.path)], text: '简瘦 · 月度减脂报告');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('分享失败: $e')));
      }
    }
  }
}

class _MonthCompareData {
  final double? lastMonthAvg;
  final double? thisMonthAvg;
  final int lastMonthWorkoutDays;
  final int thisMonthWorkoutDays;
  final double? lastMonthAvgCal;
  final double? thisMonthAvgCal;

  const _MonthCompareData({
    this.lastMonthAvg,
    this.thisMonthAvg,
    this.lastMonthWorkoutDays = 0,
    this.thisMonthWorkoutDays = 0,
    this.lastMonthAvgCal,
    this.thisMonthAvgCal,
  });
}

class _CompareRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String lastValue;
  final String thisValue;
  final String? deltaText;
  final Color? deltaColor;

  const _CompareRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.lastValue,
    required this.thisValue,
    this.deltaText,
    this.deltaColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withAlpha(30),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline, fontSize: 10)),
                const SizedBox(height: 3),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(lastValue,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white54)),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 5),
                      child: Text('→',
                          style:
                              TextStyle(fontSize: 10, color: Colors.white38)),
                    ),
                    Flexible(
                      child: Text(thisValue,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (deltaText != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (deltaColor ?? Colors.white54).withAlpha(28),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                deltaText!,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: deltaColor ?? Colors.white54),
              ),
            ),
        ],
      ),
    );
  }
}
