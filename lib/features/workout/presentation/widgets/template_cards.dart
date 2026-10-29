import 'package:flutter/material.dart';

import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/workout/domain/entities/workout_template_entity.dart';

/// 训练模板相关的展示型组件：区段标题 / 封面卡 / 空态 / 提示。
class TemplateSectionHeader extends StatelessWidget {
  final String title;
  final String? trailing;
  final Widget? trailingAction;

  const TemplateSectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.trailingAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Text(
            title,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        const Spacer(),
        // 数量与动作按钮**可以同时出现**：原来二选一，导致"模板 ≤2 个"时
        // 只剩「新建」、展开/收起按钮整个消失（用户报的第 1 条）
        if (trailing != null)
          Padding(
            padding: EdgeInsets.only(right: trailingAction == null ? 2 : 6),
            child: Text(
              trailing!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.textTertiary, fontSize: 11),
            ),
          ),
        if (trailingAction != null) trailingAction!,
      ],
    );
  }
}

class TemplateCard extends StatelessWidget {
  final WorkoutTemplateEntity template;
  final bool starting;
  final double coverHeight;
  final VoidCallback onStart;
  final VoidCallback? onEdit;

  const TemplateCard({
    super.key,
    required this.template,
    required this.starting,
    required this.coverHeight,
    required this.onStart,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: starting ? null : onStart,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TemplateCover(
              template: template,
              height: coverHeight,
              compact: coverHeight < 120,
              onEdit: onEdit,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    template.name,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${template.items.length} 个动作 · ${template.focus}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: SizedBox(
                height: 40,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                    disabledBackgroundColor: AppColors.primary.withAlpha(60),
                    disabledForegroundColor: AppColors.textTertiary,
                    elevation: 0,
                    minimumSize: Size.zero,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onPressed: starting ? null : onStart,
                  child: const Text('开始训练'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TemplateCover extends StatelessWidget {
  final WorkoutTemplateEntity template;
  final double height;
  final bool compact;
  final VoidCallback? onEdit;

  const TemplateCover({
    super.key,
    required this.template,
    required this.height,
    required this.compact,
    this.onEdit,
  });

  /// accentKey → 渐变双色（深色收尾，保证白字可读）
  static const _gradients = <String, List<Color>>{
    'green': [AppColors.primary, Color(0xFF1B5E20)],
    'orange': [Color(0xFFFF7043), Color(0xFFBF360C)],
    'red': [Color(0xFFEF5350), Color(0xFFB71C1C)],
    'cyan': [Color(0xFF26C6DA), Color(0xFF00695C)],
    'purple': [Color(0xFFC084FC), Color(0xFF4A148C)],
  };

  static const _icons = <String, IconData>{
    'green': Icons.fitness_center,
    'orange': Icons.local_fire_department,
    'red': Icons.bolt,
    'cyan': Icons.business_center,
    'purple': Icons.nightlight_round,
  };

  static const List<Color> _fallback = [AppColors.primary, Color(0xFF1B5E20)];

  @override
  Widget build(BuildContext context) {
    final colors = _gradients[template.accentKey] ?? _fallback;
    final icon = _icons[template.accentKey] ?? Icons.fitness_center;
    final iconSize = compact ? 32.0 : 46.0;

    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 渐变底
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors,
              ),
            ),
          ),
          // 装饰圆：制造层次，避免纯色块
          Positioned(
            right: -18,
            top: -26,
            child: DecorCircle(size: compact ? 74 : 104),
          ),
          Positioned(
            left: -14,
            bottom: -30,
            child: DecorCircle(size: compact ? 58 : 84),
          ),
          Positioned(
            right: compact ? 42 : 68,
            bottom: compact ? 10 : 18,
            child: DecorCircle(size: compact ? 24 : 34),
          ),
          // 中央动作图标
          Center(
            child: Icon(
              icon,
              size: iconSize,
              color: Colors.white.withAlpha(200),
            ),
          ),
          // 左上：难度
          Positioned(
            left: 10,
            top: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                template.difficulty,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
          // 右上：编辑按钮（我的模板）或时长（推荐模板）
          if (onEdit != null)
            Positioned(
              right: 8,
              top: 8,
              child: Material(
                color: Colors.black.withAlpha(46),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onEdit,
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.edit_note, size: 18, color: Colors.white),
                  ),
                ),
              ),
            )
          else
            Positioned(
              right: 10,
              top: 11,
              child: Text(
                '${template.minutes} 分钟',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withAlpha(230),
                ),
              ),
            ),
          // 编辑按钮占用了右上角时，时长落到封面右下
          if (onEdit != null)
            Positioned(
              right: 12,
              bottom: 8,
              child: Text(
                '${template.minutes} 分钟',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withAlpha(230),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class DecorCircle extends StatelessWidget {
  final double size;

  const DecorCircle({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withAlpha(18),
      ),
    );
  }
}

class EmptyMineCard extends StatelessWidget {
  final VoidCallback onCreate;

  const EmptyMineCard({super.key, required this.onCreate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onCreate,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.bookmark_add_outlined,
                    size: 22, color: AppColors.textTertiary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '创建你的第一个组合',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '把常做的动作存成模板，一键开练',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 32,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
                    elevation: 0,
                    minimumSize: Size.zero,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onPressed: onCreate,
                  child: const Text('新建'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TemplateHintCard extends StatelessWidget {
  final String text;

  const TemplateHintCard({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 22),
        child: Center(
          child: Text(
            text,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppColors.textTertiary, fontSize: 12),
          ),
        ),
      ),
    );
  }
}
