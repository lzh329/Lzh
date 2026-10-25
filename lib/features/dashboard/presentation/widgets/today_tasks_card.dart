import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 首页「今日打卡」卡 —— 大号进度环 + 三宫格打卡块
///
/// 三件事：记录体重 / 完成训练 / 记录饮食。
/// 完成后对应弧段点亮、打卡块变橙并发光。
class TodayTasksCard extends StatelessWidget {
  final double? todayWeightJin;
  final double? latestWeightJin;
  final bool hasTraining;
  final int workoutCount;
  final double? calories;
  final String? gugaAsset;

  final VoidCallback onWeight;
  final VoidCallback onWorkout;
  final VoidCallback onDiet;

  const TodayTasksCard({
    super.key,
    this.todayWeightJin,
    this.latestWeightJin,
    this.hasTraining = false,
    this.workoutCount = 0,
    this.calories,
    this.gugaAsset,
    required this.onWeight,
    required this.onWorkout,
    required this.onDiet,
  });

  static const _orange = Color(0xFFFF8A00);
  static const _green = Color(0xFF3DDC84);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final weightDone = todayWeightJin != null;
    final workoutDone = workoutCount > 0;
    final dietDone = calories != null;
    final doneCount =
        [weightDone, workoutDone, dietDone].where((d) => d).length;

    final encourage = switch (doneCount) {
      0 => '先动起来，比什么都重要',
      1 || 2 => '已经完成 $doneCount 项，继续保持',
      _ => '今日全部完成，咕嘎为你鼓掌！',
    };

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: _orange.withAlpha(70), width: 0.8),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        child: Column(
          children: [
            // ── 头部 ──
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: _orange.withAlpha(32),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.checklist, size: 15, color: _orange),
                ),
                const SizedBox(width: 10),
                Text('今日打卡', style: theme.textTheme.titleSmall),
                const Spacer(),
                Text(
                  doneCount == 3
                      ? '全部完成'
                      : (doneCount == 0 ? '从第一项开始' : '正在推进'),
                  style:
                      const TextStyle(fontSize: 10, color: Colors.white38),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── 大号进度环 ──
            SizedBox(
              width: 148,
              height: 148,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: doneCount / 3),
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, _) => CustomPaint(
                      size: const Size(148, 148),
                      painter: _RingPainter(progress: value, total: 3),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$doneCount/3',
                        style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                          height: 1.0,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '今日已完成',
                        style: TextStyle(fontSize: 10, color: Colors.white38),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── 三宫格打卡块 ──
            Row(
              children: [
                _TaskTile(
                  icon: Icons.monitor_weight_outlined,
                  label: '体重',
                  value: weightDone
                      ? '${todayWeightJin!.toStringAsFixed(1)} 斤'
                      : (latestWeightJin != null
                          ? '上次 ${latestWeightJin!.toStringAsFixed(1)}'
                          : '去记录'),
                  done: weightDone,
                  onTap: onWeight,
                ),
                const SizedBox(width: 8),
                _TaskTile(
                  icon: Icons.fitness_center,
                  label: '训练',
                  value: workoutDone
                      ? '已练 $workoutCount 次'
                      : (hasTraining ? '开始' : '去训练'),
                  done: workoutDone,
                  highlight: !workoutDone && hasTraining,
                  onTap: onWorkout,
                ),
                const SizedBox(width: 8),
                _TaskTile(
                  icon: Icons.restaurant_outlined,
                  label: '饮食',
                  value: dietDone ? '${calories!.round()} kcal' : '去记录',
                  done: dietDone,
                  onTap: onDiet,
                ),
              ],
            ),
            const SizedBox(height: 14),

            // ── 咕嘎鼓励 ──
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: gugaAsset != null
                      ? Image.asset(gugaAsset!, fit: BoxFit.cover)
                      : const Icon(Icons.sentiment_satisfied_alt,
                          size: 14, color: _orange),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    encourage,
                    style: TextStyle(
                      fontSize: 11,
                      color: doneCount == 3 ? _green : Colors.white60,
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
    );
  }
}

/// 三段进度环（每完成一项点亮一段）
class _RingPainter extends CustomPainter {
  final double progress; // 0~1
  final int total;

  _RingPainter({required this.progress, required this.total});

  static const _orange = Color(0xFFFF8A00);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final segAngle = 2 * math.pi / total;
    const gap = 0.16; // 弧度间隙
    final lit = progress * total; // 已点亮的段数（含小数）

    for (var i = 0; i < total; i++) {
      final start = -math.pi / 2 + i * segAngle + gap / 2;
      final sweep = segAngle - gap;

      // 底色段
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withAlpha(16),
      );

      // 点亮段（按进度部分填充）
      final segFill = (lit - i).clamp(0.0, 1.0);
      if (segFill > 0) {
        // 光晕
        canvas.drawArc(
          rect,
          start,
          sweep * segFill,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 10
            ..strokeCap = StrokeCap.round
            ..color = _orange.withAlpha(90)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
        // 实心段
        canvas.drawArc(
          rect,
          start,
          sweep * segFill,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 10
            ..strokeCap = StrokeCap.round
            ..color = _orange,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// 单个打卡块（1/3 宽）
class _TaskTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool done;
  final bool highlight;
  final VoidCallback onTap;

  const _TaskTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.done,
    this.highlight = false,
    required this.onTap,
  });

  static const _orange = Color(0xFFFF8A00);

  @override
  Widget build(BuildContext context) {
    final borderColor = done
        ? _orange.withAlpha(150)
        : (highlight ? _orange.withAlpha(90) : Colors.white.withAlpha(16));

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
          height: 108,
          decoration: BoxDecoration(
            color: done ? _orange.withAlpha(22) : Colors.white.withAlpha(6),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: done ? 1.2 : 0.8),
            boxShadow: done
                ? [
                    BoxShadow(
                      color: _orange.withAlpha(30),
                      blurRadius: 14,
                      spreadRadius: 1,
                    )
                  ]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, size: 24, color: done ? _orange : Colors.white38),
                  if (done)
                    Positioned(
                      right: -9,
                      top: -6,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: const BoxDecoration(
                          color: _orange,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check,
                            size: 11, color: Colors.black),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: done ? Colors.white70 : Colors.white,
                ),
              ),
              const SizedBox(height: 3),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 9.5,
                    color: done
                        ? _orange
                        : (highlight ? _orange : Colors.white38),
                    fontWeight: (done || highlight)
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
