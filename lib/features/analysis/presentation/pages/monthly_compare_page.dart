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
            padding: const EdgeInsets.all(16),
            children: [
              // 对比卡片
              RepaintBoundary(
                key: cardKey,
                child: Card(
                  color: theme.colorScheme.surface,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Text('简瘦 · 月度报告', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(
                          '${DateFormat('M月').format(monthStart)} vs ${DateFormat('M月').format(lastMonthStart)}',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                        ),
                        const SizedBox(height: 20),
                        // 体重对比行
                        if (data.lastMonthAvg != null && data.thisMonthAvg != null)
                          _buildWeightRow(theme, data),
                        const SizedBox(height: 16),
                        // 训练对比行
                        _buildTrainingRow(theme, data),
                        const SizedBox(height: 16),
                        // 饮食对比行
                        if (data.lastMonthAvgCal != null && data.thisMonthAvgCal != null)
                          _buildDietRow(theme, data, us),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // 分享按钮
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _shareCard(context, cardKey),
                  icon: const Icon(Icons.share, size: 18),
                  label: const Text('分享月度报告'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildWeightRow(ThemeData theme, _MonthCompareData data) {
    final delta = data.thisMonthAvg! - data.lastMonthAvg!;
    final isDown = delta < -0.05;
    final arrow = isDown ? '↓' : '↑';
    final color = isDown ? Colors.green : Colors.red;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _CompareItem(icon: Icons.calendar_today, label: '上月', value: '${(data.lastMonthAvg! * 2).toStringAsFixed(1)} 斤', theme: theme),
        Icon(arrow == '↓' ? Icons.trending_down : Icons.trending_up, color: color, size: 24),
        _CompareItem(icon: Icons.calendar_today, label: '本月', value: '${(data.thisMonthAvg! * 2).toStringAsFixed(1)} 斤', theme: theme),
        const SizedBox(width: 8),
        _CompareItem(
          icon: Icons.swap_vert,
          label: '变化',
          value: '$arrow ${delta.abs().toStringAsFixed(1)} 斤',
          color: color,
          theme: theme,
        ),
      ],
    );
  }

  Widget _buildTrainingRow(ThemeData theme, _MonthCompareData data) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _CompareItem(icon: Icons.fitness_center, label: '上月训练', value: '${data.lastMonthWorkoutDays} 天', theme: theme),
        Container(width: 1, height: 32, color: theme.colorScheme.outline.withAlpha(40)),
        _CompareItem(icon: Icons.fitness_center, label: '本月训练', value: '${data.thisMonthWorkoutDays} 天', theme: theme),
      ],
    );
  }

  Widget _buildDietRow(ThemeData theme, _MonthCompareData data, UserSettingsEntity? us) {
    final lastDeficit = us?.tdee() != null ? us!.tdee()! - data.lastMonthAvgCal! : null;
    final thisDeficit = us?.tdee() != null ? us!.tdee()! - data.thisMonthAvgCal! : null;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _CompareItem(icon: Icons.restaurant, label: '上月日均', value: '${data.lastMonthAvgCal!.toInt()} kcal', theme: theme),
        Container(width: 1, height: 32, color: theme.colorScheme.outline.withAlpha(40)),
        _CompareItem(icon: Icons.restaurant, label: '本月日均', value: '${data.thisMonthAvgCal!.toInt()} kcal', theme: theme),
        if (lastDeficit != null && thisDeficit != null) ...[
          Container(width: 1, height: 32, color: theme.colorScheme.outline.withAlpha(40)),
          _CompareItem(
            icon: Icons.local_fire_department,
            label: '缺口变化',
            value: '${(thisDeficit - lastDeficit).toInt()} kcal',
            color: thisDeficit > lastDeficit ? Colors.green : Colors.red,
            theme: theme,
          ),
        ],
      ],
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

class _CompareItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? color;
  final ThemeData theme;
  const _CompareItem({required this.icon, required this.label, required this.value, this.color, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 16, color: (color ?? theme.colorScheme.primary).withAlpha(180)),
        const SizedBox(height: 4),
        Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold, color: color)),
        Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline, fontSize: 10)),
      ],
    );
  }
}
