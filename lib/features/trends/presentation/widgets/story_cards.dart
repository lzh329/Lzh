import 'package:flutter/material.dart';
import 'package:fittrack/features/trends/presentation/trends_providers.dart';

const _green = Color(0xFF66BB6A);
const _amber = Color(0xFFFFA726);

/// 你的变化故事卡 —— 情感化激励
class StoryCard extends StatelessWidget {
  final TrendsData data;

  const StoryCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!data.hasWeight) return const SizedBox.shrink();

    final loss = data.totalLossJin;

    return Card(
      color: const Color(0xFF12251A),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, size: 16, color: _green),
                const SizedBox(width: 6),
                Text('你的变化故事',
                    style: theme.textTheme.titleSmall?.copyWith(color: _green)),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '你已经坚持 ${data.daysRecorded} 天',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (loss != null) ...[
              const SizedBox(height: 4),
              Text(
                '累计减重 ${loss.abs().toStringAsFixed(1)} 斤',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: _green),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              (loss ?? 0) > 0.05
                  ? '这是你减脂旅程的重要成果，继续保持！'
                  : '每一次记录，都是向目标迈进的一步。',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Colors.white60),
            ),
          ],
        ),
      ),
    );
  }
}

/// 减脂效果分析卡 —— 趋势判断 + 达标预测
class EffectAnalysisCard extends StatelessWidget {
  final TrendsData data;

  const EffectAnalysisCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!data.hasWeight || data.metrics.length < 2) {
      return const SizedBox.shrink();
    }

    final days = data.latestDate!.difference(data.startDate!).inDays;
    final loss = data.totalLossJin ?? 0;

    final String verdict;
    final Color verdictColor;
    if (loss > 0.3) {
      verdict =
          '体重呈现下降趋势，$days 天内从 ${data.startJin!.toStringAsFixed(1)} 降到 ${data.currentJin!.toStringAsFixed(1)}，你的减脂策略有效！';
      verdictColor = _green;
    } else if (loss < -0.3) {
      verdict = '体重有所回升，注意保持饮食和训练节奏。';
      verdictColor = const Color(0xFFEF5350);
    } else {
      verdict = '体重保持平稳，继续坚持记录吧。';
      verdictColor = Colors.white70;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 4, height: 16, color: _green, margin: const EdgeInsets.only(right: 8)),
                Text('减脂效果分析', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '过去 $days 天，累计${loss >= 0 ? '减重' : '增重'} ${loss.abs().toStringAsFixed(1)} 斤，共锻炼 ${data.workoutDays} 天。',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              verdict,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: verdictColor, height: 1.5),
            ),
            if (data.daysToTarget != null && data.targetDate != null) ...[
              const SizedBox(height: 8),
              Text(
                '按当前趋势，预计 ${data.targetDate!.month}月${data.targetDate!.day}日 达到目标体重（约 ${data.daysToTarget} 天后），还差 ${data.remainingJin!.abs().toStringAsFixed(1)} 斤。',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: _amber,
                  height: 1.5,
                ),
              ),
            ] else if (data.metrics.length < 3) ...[
              const SizedBox(height: 8),
              Text(
                '（需 3 条以上体重记录才能预测达标日期）',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 本周概览卡 —— 体重变化 / 训练天数 / 今日摄入
class WeekOverviewCard extends StatelessWidget {
  final TrendsData data;

  const WeekOverviewCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final change = data.weekChangeJin;

    final String changeText;
    final Color changeColor;
    if (change == null) {
      changeText = '—';
      changeColor = Colors.white54;
    } else if (change < -0.05) {
      changeText = '${change.abs().toStringAsFixed(1)}斤';
      changeColor = _green;
    } else if (change > 0.05) {
      changeText = '+${change.toStringAsFixed(1)}斤';
      changeColor = const Color(0xFFEF5350);
    } else {
      changeText = '0.0斤';
      changeColor = Colors.white70;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('本周概览', style: theme.textTheme.titleSmall),
            const SizedBox(height: 14),
            Row(
              children: [
                _Cell(value: changeText, label: '体重变化', color: changeColor),
                _Cell(
                  value: '${data.weekWorkoutDays}/7天',
                  label: '训练',
                  color: _green,
                ),
                _Cell(
                  value: data.todayCalories != null
                      ? '${data.todayCalories!.round()}'
                      : '—',
                  label: '今日摄入(kcal)',
                  color: Colors.white70,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _Cell({required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w600, color: color),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
