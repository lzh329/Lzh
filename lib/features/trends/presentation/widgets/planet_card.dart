import 'package:flutter/material.dart';
import 'package:fittrack/core/services/planet_level.dart';

/// 我的减脂星球卡 —— 趋势页顶部
///
/// 立绘随累计减重升级（萌芽 → 森林 → 小屋 → 城堡）
class PlanetCard extends StatelessWidget {
  final double? totalLossJin;
  final VoidCallback? onTap;

  const PlanetCard({super.key, this.totalLossJin, this.onTap});

  static const _green = Color(0xFF66BB6A);
  static const _bg = Color(0xFF161A16);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = PlanetLevelService.resolve(totalLossJin);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            // ── 立绘（右侧，随等级切换）──
            Positioned(
              right: -30,
              top: 0,
              bottom: 0,
              width: 210,
              child: Image.asset(
                status.stage.asset,
                fit: BoxFit.cover,
                alignment: Alignment.centerRight,
              ),
            ),
            // ── 左侧渐隐遮罩（保证文字可读）──
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      _bg,
                      _bg.withAlpha(210),
                      _bg.withAlpha(0),
                    ],
                    stops: const [0.0, 0.44, 0.80],
                  ),
                ),
              ),
            ),
            // ── 内容 ──
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.public, size: 15, color: _green),
                      const SizedBox(width: 6),
                      Text('我的减脂星球', style: theme.textTheme.titleSmall),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _green.withAlpha(26),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _green.withAlpha(110),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          'Lv.${status.stage.level} ${status.stage.name}',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: _green,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: 168,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: status.progress,
                            minHeight: 5,
                            backgroundColor: Colors.white.withAlpha(18),
                            color: _green,
                          ),
                        ),
                        const SizedBox(height: 9),
                        Text(
                          status.isMax
                              ? '最高等级已解锁，你在守望着自己的星球'
                              : '再减 ${status.remainToNext!.toStringAsFixed(1)} 斤解锁 ${status.next!.name}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white70,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '累计减重 ${status.totalLossJin.toStringAsFixed(1)} 斤 · 进度 ${(status.progress * 100).round()}%',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
