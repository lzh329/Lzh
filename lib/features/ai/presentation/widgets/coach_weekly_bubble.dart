import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fittrack/core/database/coach_proactive_repository.dart';
import 'package:fittrack/core/services/coach_proactive_providers.dart';
import 'package:fittrack/core/services/coach_workout_recap.dart';
import 'package:fittrack/core/theme/app_colors.dart';

/// 首页「教练说」气泡（W11）
///
/// 一天之内最多 2 条：今日未读点评 1 条 + 本周未读周消息 1 条。
///
/// **W11 口径（已与主理人确认）**：渲染即写 `seen_at`，但**本次 widget 生命周期
/// 内继续显示已捕获的正文**，离开首页再回来（State 重建）才不再出现。
/// 严格按 PRD 字面"写完就消失"会让气泡在用户读到之前的同一帧消失 —— 主动说话
/// 就只剩通知一条路，而 PRD 明确要求内展，那是把需求做反。
class CoachWeeklyBubble extends ConsumerStatefulWidget {
  const CoachWeeklyBubble({super.key});

  @override
  ConsumerState<CoachWeeklyBubble> createState() => _CoachWeeklyBubbleState();
}

class _CoachWeeklyBubbleState extends ConsumerState<CoachWeeklyBubble> {
  CoachProactiveMessage? _recap;
  CoachProactiveMessage? _weekly;
  bool _markedRecap = false;
  bool _markedWeekly = false;

  @override
  Widget build(BuildContext context) {
    final recap = ref.watch(coachUnreadRecapProvider).valueOrNull;
    final weekly = ref.watch(coachUnreadWeeklyProvider).valueOrNull;

    // 捕获（只赋值、不 setState：本帧就按它渲染，避免多余重建）
    if (recap != null && _recap == null) {
      _recap = recap;
      _scheduleMark(recapId: recap.id);
    }
    if (weekly != null && _weekly == null) {
      _weekly = weekly;
      _scheduleMark(weeklyId: weekly.id);
    }

    final r = _recap;
    final w = _weekly;
    if (r == null && w == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          if (r != null)
            _BubbleCard(
              message: r,
              label: '教练点评',
              icon: Icons.bolt_outlined,
              // 点点评 → 打开教练页并**预填**（不自动发送：请求要花钱，用户可能换问法）
              onTap: () => context.push('/ai/coach', extra: kRecapPrefill),
            ),
          if (r != null && w != null) const SizedBox(height: 8),
          if (w != null)
            _BubbleCard(
              message: w,
              label: '教练说',
              icon: Icons.campaign_outlined,
              onTap: () => context.push('/ai/coach'),
            ),
        ],
      ),
    );
  }

  /// 绝不在 build 里直接写库：build 会被频繁重建
  void _scheduleMark({int? recapId, int? weeklyId}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (recapId != null && !_markedRecap) {
        _markedRecap = true;
        markCoachRecapSeen(ref, recapId);
      }
      if (weeklyId != null && !_markedWeekly) {
        _markedWeekly = true;
        markCoachWeeklySeen(ref, weeklyId);
      }
    });
  }
}

class _BubbleCard extends StatelessWidget {
  final CoachProactiveMessage message;
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _BubbleCard({
    required this.message,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      message.content,
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.5,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 教练页顶部的周消息卡片
///
/// 与首页气泡是两个口径（PRD 6.1）：这里**已读也保留**，直到下一条周消息到来。
class CoachWeeklyCard extends ConsumerWidget {
  const CoachWeeklyCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latest = ref.watch(coachLatestWeeklyProvider).valueOrNull;
    if (latest == null) return const SizedBox.shrink();
    final d = latest.weekStart ?? latest.createdAt;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.campaign_outlined,
                      size: 16, color: AppColors.primary),
                  const SizedBox(width: 6),
                  const Text(
                    '教练说',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${d.month} 月 ${d.day} 日',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textTertiary),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                latest.content,
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.5,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
