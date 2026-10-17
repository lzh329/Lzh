import 'package:flutter/material.dart';

/// 2×2 数据磁贴网格（替代原来的横排入口卡）
class StatTileData {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String unit;
  final VoidCallback? onTap;

  const StatTileData({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.unit,
    this.onTap,
  });
}

class StatTilesGrid extends StatelessWidget {
  final List<StatTileData> tiles;

  const StatTilesGrid({super.key, required this.tiles});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.62,
      children: tiles.map((t) => _StatTile(data: t)).toList(),
    );
  }
}

class _StatTile extends StatelessWidget {
  final StatTileData data;

  const _StatTile({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: data.onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: data.color.withAlpha(32),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(data.icon, size: 14, color: data.color),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      data.label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    data.value,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      data.unit,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                        fontSize: 10,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
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
