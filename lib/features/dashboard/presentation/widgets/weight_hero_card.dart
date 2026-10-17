import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// 最新体重卡（橙色主题）— 主控页核心卡片
///
/// 三栏指标：累计减重 / 预计达成 / 距目标
class WeightHeroCard extends StatelessWidget {
  final double? currentJin; // 当前体重（斤）
  final double? targetJin; // 目标体重（斤）
  final double? totalLossJin; // 累计减重（斤）
  final int? daysToTarget; // 预计达成天数
  final double? bmi;
  final DateTime? recordedAt;
  final VoidCallback? onTap;

  const WeightHeroCard({
    super.key,
    this.currentJin,
    this.targetJin,
    this.totalLossJin,
    this.daysToTarget,
    this.bmi,
    this.recordedAt,
    this.onTap,
  });

  static const _accent = Color(0xFFFFA726);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasData = currentJin != null;

    return Card(
      color: const Color(0xFF1E1A14),
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: hasData ? _buildData(theme) : _buildEmpty(theme),
        ),
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Column(
      children: [
        Icon(Icons.monitor_weight_outlined,
            size: 36, color: theme.colorScheme.outline),
        const SizedBox(height: 8),
        Text('暂无体重数据',
            style: theme.textTheme.bodyLarge
                ?.copyWith(color: theme.colorScheme.outline)),
        const SizedBox(height: 4),
        Text('点击右下角「记录体重」开始',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline)),
      ],
    );
  }

  Widget _buildData(ThemeData theme) {
    final remainingJin = (targetJin != null && currentJin != null)
        ? (currentJin! - targetJin!).clamp(0.0, double.infinity)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题行
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _accent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.monitor_weight,
                  size: 16, color: Colors.black),
            ),
            const SizedBox(width: 10),
            Text('最新体重', style: theme.textTheme.titleMedium),
            const Spacer(),
            if (bmi != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _accent.withAlpha(30),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'BMI ${bmi!.toStringAsFixed(1)}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _accent),
                ),
              ),
          ],
        ),

        // 主数字
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            // 数字滚动动效：首次从 0 滚入，数值更新时从当前值过渡到新值
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: currentJin!),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => Text(
                v.toStringAsFixed(1),
                style: const TextStyle(
                    fontSize: 40, fontWeight: FontWeight.bold, height: 1.0),
              ),
            ),
            const SizedBox(width: 6),
            Text('斤',
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: theme.colorScheme.outline)),
            const Spacer(),
            if (recordedAt != null)
              Text(
                DateFormat('MM月dd日').format(recordedAt!),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
          ],
        ),

        // 三栏指标
        if (totalLossJin != null || daysToTarget != null || targetJin != null)
          ...[
          const SizedBox(height: 14),
          Container(height: 1, color: Colors.white.withAlpha(16)),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (totalLossJin != null)
                _Stat(
                  icon: Icons.trending_down,
                  value: '${totalLossJin!.toStringAsFixed(1)}斤',
                  label: '累计减重',
                  color: totalLossJin! > 0.05
                      ? const Color(0xFF66BB6A)
                      : Colors.white54,
                ),
              if (totalLossJin != null && daysToTarget != null) _vDivider(),
              if (daysToTarget != null)
                _Stat(
                  icon: Icons.schedule,
                  value: '$daysToTarget 天后',
                  label: '预计达成',
                  color: _accent,
                ),
              if (targetJin != null) ...[
                _vDivider(),
                _Stat(
                  icon: Icons.flag,
                  value: remainingJin != null
                      ? '还差 ${remainingJin.toStringAsFixed(1)}斤'
                      : '—',
                  label: '目标 ${targetJin!.toStringAsFixed(1)}斤',
                  color: Colors.white70,
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  Widget _vDivider() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Container(width: 1, height: 30, color: Colors.white.withAlpha(20)),
      );
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _Stat({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  value,
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600, color: color),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
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
