import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/router/app_router.dart' show appRouteObserver;
import 'package:fittrack/core/services/character_catalog.dart';
import 'package:fittrack/core/services/character_providers.dart';
import 'package:fittrack/features/dashboard/domain/dashboard_timeline.dart' as timeline;
import 'package:fittrack/features/dashboard/presentation/actions/capture_today_photo.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/character_mood.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/character_view.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/greeting_header.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/photo_compare_card.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/sick_day_banner.dart';
import 'package:fittrack/features/dashboard/presentation/widgets/today_tasks_card.dart';
import 'package:fittrack/features/ai/presentation/widgets/coach_weekly_bubble.dart';

/// 主控页 —— v6「任务 + 对比」极简版
///
/// 结构：问候（角色小头像）→ 今日任务（记录体重 / 完成训练 / 记录饮食）
///      → 身体变化对比（最早 vs 最新照片）
/// 统计类信息（体重曲线、热量、饮水、训练量、周报）统一在「趋势」页。
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  /// 自动播放节流间隔。**只在测试里改**（线上恒 30s）：`DateTime.now()` 不受
  /// `tester.pump(Duration)` 影响，用真实时钟等 30 秒不可接受。
  @visibleForTesting
  static Duration autoPlayInterval = const Duration(seconds: 30);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(dashboardDataProvider);

    return Scaffold(
      body: dataAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('加载失败'),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.invalidate(dashboardDataProvider),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
        data: (data) => _DashboardBody(data: data),
      ),
    );
  }
}

class _DashboardBody extends ConsumerStatefulWidget {
  final DashboardData data;

  const _DashboardBody({required this.data});

  @override
  ConsumerState<_DashboardBody> createState() => _DashboardBodyState();
}

class _DashboardBodyState extends ConsumerState<_DashboardBody> with RouteAware {
  /// 角色区的手柄：进入首页时要"自动播一次动作"（点击已改为进教练）
  final _characterKey = GlobalKey<CharacterViewState>();

  /// 自动播放节流：距上次播放 ≥30s 才播（含从教练页返回）。
  /// 只在 State 里记，不落库 —— 重启后重播一次是对的（用户刚看到首页）。
  DateTime? _lastAutoPlay;

  /// 首次自动播放是否已安排（角色挂上之后只安排一次）
  bool _autoPlayScheduled = false;

  /// 「我是○○」的显示窗口（决策 2：切换后 1.5s 内说这一句，之后回通用台词）
  /// 「我是○○」窗口是否还开着。
  ///
  /// 用 bool + Timer，**不用 `DateTime.now()` 比较**：墙钟不受 `tester.pump()`
  /// 影响，会让"1.5s 后回日常台词"这件事既测不了、也不够确定（QA 的 C-6 就卡在这）。
  bool _showIntro = false;

  /// 上一句台词的索引：随机轮换时**不重复上一句**
  int _lineIndex = 0;

  /// 上一次看到的角色 id：变了 = 刚切换角色/形态，要说「我是○○」
  CharacterId? _lastCharacterId;

  static const _introWindow = Duration(milliseconds: 1500);

  /// 「我是○○」窗口结束时重新取一次台词（否则气泡会一直停在那一句，
  /// 直到别的原因触发重建 —— 用户看到的是"卡住了"）
  Timer? _introTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      appRouteObserver.subscribe(this, route);
    }
  }

  /// 从教练页 / 形象页返回：距上次播放够久就再播一次（含轮换台词）
  @override
  void didPopNext() => _maybeAutoPlay();

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    _introTimer?.cancel();
    super.dispose();
  }

  /// 播一次动作 + 换一句台词（30s 内重复进入不播，避免"每次返回都抽搐"）
  void _maybeAutoPlay() {
    if (!mounted) return;
    final character = _characterKey.currentState;
    if (character == null) return; // 角色还没画出来（设置未读到 / 空舞台）
    final now = DateTime.now();
    final last = _lastAutoPlay;
    if (last != null && now.difference(last) < DashboardPage.autoPlayInterval) {
      return;
    }
    _lastAutoPlay = now;
    character.playActionOnce();
    setState(() {
      // 每次自动播都换一句台词：气泡内容跟着动作一起变，才像"活的"
      _lineIndex++;
      _showIntro = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final latest = data.latestMetric;
    final today = DateTime.now();

    // ── 角色 / 形态（唯一渲染口径，C12） ──
    final spec = ref.watch(currentCharacterProvider);
    // 角色"已知"之前**不画任何角色**：首帧拿"还没读到"当"就是咕嘎"，
    // 会让选了糯糯的用户先看到企鹅装咕嘎再跳变（装机实测问题 1）。
    final characterKnown = ref.watch(characterResolvedProvider);

    // 角色第一次画出来之后自动播一次动作（点角色已改为进教练）。
    // 放在 build 里而不是 initState：角色要等设置读到才挂上，initState 时
    // `_characterKey.currentState` 还是 null，播了空。
    if (characterKnown && !_autoPlayScheduled) {
      _autoPlayScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoPlay());
    }

    // 刚切换角色：1.5s 内说「我是○○」，并丢弃正在播的动作（C6）
    if (_lastCharacterId != spec.id) {
      final isFirstBuild = _lastCharacterId == null;
      _lastCharacterId = spec.id;
      if (!isFirstBuild) {
        _showIntro = true;
        _lineIndex = 0;
        // 窗口结束后回通用台词：Timer 到点就把标记翻掉并重建
        _introTimer?.cancel();
        _introTimer = Timer(_introWindow, () {
          if (mounted) setState(() => _showIntro = false);
        });
      }
    }

    final currentJin = latest != null ? latest.weightKg * 2 : null;
    final startJin =
        data.firstMetric != null ? data.firstMetric!.weightKg * 2 : null;
    final totalLossJin =
        (startJin != null && currentJin != null) ? startJin - currentJin : 0.0;

    // 连续打卡（体重或训练任一有记录算一天）
    final streak = timeline.calcStreak([
      ...data.allMetrics.map((m) => m.date),
      ...data.allWorkouts.map((w) => w.date),
    ]);

    final todayWorkouts =
        data.allWorkouts.where((w) => timeline.sameDay(w.date, today)).toList();

    final activePlan = data.activePlan;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 120),
        children: [
          // 0) 生病模式横幅（不生效时自己渲染成 0 高度占位，不留空档）
          const SickDayBanner(),
          const SizedBox(height: 10),
          // 1) 问候 + 连续打卡 + 角色小头像
          GreetingHeader(
            // 用户设了昵称就用昵称，没设回落到**角色名**（不带形态名，C19）
            nickname: ref.watch(userSettingsProvider).valueOrNull?.nickname,
            streakDays: streak,
            avatarAsset: characterKnown ? spec.avatarAsset : null,
            characterName: characterKnown ? spec.name : null,
            // 解锁提示用「再减 X 斤」，与趋势页的「累计减重」措辞区分（风险 3）
            upgradeHint: characterKnown && !spec.isMaxForm
                ? '再减 ${spec.remainToNextJin!.toStringAsFixed(1)} 斤换下一个样子'
                : null,
          ),
          const SizedBox(height: 10),

          // 2) 角色区（首屏主角）
          //
          // 三段手势：点角色 = 播动作 + 换台词（**不跳页**）；点气泡 = 进对话；
          // 长按 500ms = 进「我的形象」（R14 / 决策 17）。
          // 旧实现把"播动作"和"跳转"压在同一个 onTap 上，接了 Rive 之后
          // 用户点一下会"闪 0.1 秒动作然后页面跳走"，动效等于白接。
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                // 空舞台：尺寸与角色区一致（195 / 0.82），所以角色出现时不跳版
                child: characterKnown
                    ? CharacterView(
                        spec: spec,
                        height: 195,
                        key: _characterKey,
                        line: _currentLine(spec),
                        // 阶段 A：首页固定 idle；训练态等训练页接进来再传 training
                        mood: CharacterMood.idle,
                        isChatEntry: true,
                        // 点角色直接进教练：这是用户唯一的"聊天入口直觉"
                        // （气泡只在有未读时出现，不能当主入口）
                        onTap: () => context.push('/ai/coach'),
                        onBubbleTap: () => context.push('/ai/coach'),
                        // 长按换形象（保留）
                        onLongPress: () => context.push('/settings/character'),
                      )
                    : const SizedBox(width: 195 * 0.82, height: 195),
              ),
            ),
          ),
          // 教练主动消息气泡（有未读才出现；一天最多 2 条）
          const CoachWeeklyBubble(),
          const SizedBox(height: 14),

          // 3) 今日任务（打卡方块，下移到首屏之下）
          TodayTasksCard(
            todayWeightJin: data.todayMetric != null
                ? data.todayMetric!.weightKg * 2
                : null,
            latestWeightJin: currentJin,
            hasTraining: activePlan != null,
            workoutCount: todayWorkouts.length,
            photoDone: data.todayPhoto != null,
            characterAsset: characterKnown ? spec.avatarAsset : null,
            characterName: characterKnown ? spec.name : null,
            onWeight: () => context.push('/body'),
            onWorkout: () {
              if (activePlan != null) {
                context.push('/plan/${activePlan.id}/execute');
              } else {
                // 老路径已 redirect 到 /workout，这里直接给新路由
                context.push('/workout');
              }
            },
            onPhoto: () => captureTodayPhoto(context, ref),
          ),
          const SizedBox(height: 14),

          // 4) 身体变化对比（最早 vs 最新）
          PhotoCompareCard(
            firstPath: data.firstPhoto?.filePath,
            firstDate: data.firstPhoto?.date,
            latestPath: data.latestPhoto?.filePath,
            latestDate: data.latestPhoto?.date,
            lossJin: totalLossJin > 0 ? totalLossJin : null,
            onTap: () => context.push('/body/compare'),
          ),
        ],
      ),
    );
  }

  /// 当前台词：切换后的 1.5s 内说「我是○○」，之后从台词池轮换
  String _currentLine(CharacterRenderSpec spec) {
    if (_showIntro) return spec.introLine;
    if (spec.linePool.isEmpty) return '';
    return spec.linePool[_lineIndex % spec.linePool.length];
  }

}

