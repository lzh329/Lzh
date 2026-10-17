import 'package:flutter/material.dart';
import 'package:fittrack/core/services/guga_level.dart';

/// 我的咕嘎卡 —— 趋势页顶部
///
/// 左侧成长信息（形态名 / 进度 / 解锁提示），右侧圆形头像是咕嘎立绘。
class CompanionCard extends StatelessWidget {
  final double? totalLossJin;
  final VoidCallback? onTap;

  const CompanionCard({super.key, this.totalLossJin, this.onTap});

  static const _green = Color(0xFF66BB6A);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = GugaLevelService.resolve(totalLossJin);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 左侧：成长信息 ──
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.sentiment_satisfied_alt,
                            size: 15, color: _green),
                        const SizedBox(width: 6),
                        Text('我的咕嘎', style: theme.textTheme.titleSmall),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            status.stage.name,
                            style: theme.textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: _green.withAlpha(26),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: _green.withAlpha(110), width: 0.8),
                          ),
                          child: Text(
                            'Lv.${status.stage.level}',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: _green,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      status.stage.tagline,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.white54),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: status.progress,
                        minHeight: 5,
                        backgroundColor: Colors.white.withAlpha(18),
                        color: _green,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      status.isMax
                          ? '已解锁全部形态，你就是行走的答案'
                          : '再减 ${status.remainToNext!.toStringAsFixed(1)} 斤解锁「${status.next!.name}」',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.white70,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 4),
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
              const SizedBox(width: 10),
              // ── 右侧：圆形头像框 ──
              Container(
                width: 118,
                height: 118,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(
                    color: _green.withAlpha(90),
                    width: 2,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.asset(
                  status.stage.asset,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
