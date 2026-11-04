import 'package:fittrack/features/ai/data/coach_weekly_facts.dart';

/// 周消息正文的长度区间（PRD 决策 1 第 3 级）
const int kWeeklyMinChars = 40;
const int kWeeklyMaxChars = 120;

/// 周消息 AI 调用参数（一次约几分钱，失败不重试）
const Duration kWeeklyAiTimeout = Duration(seconds: 15);
const int kWeeklyAiMaxTokens = 300;

/// 推送时刻：默认周一 09:00；称重提醒也在 9 点 → 顺延 10:00
const int kWeeklyPushHour = 9;
const int kWeeklyPushHourShifted = 10;

/// 周消息的模板兜底 + 字数/禁用词校验（**纯函数，零 IO**）。
///
/// 为什么模板是必要路径而不是"AI 失败时的补丁"：这是本地优先 App，没配 Key
/// 的用户永远收不到 AI 版；断网那一周如果静默，这个功能就再也不会被期待。
///
/// 为什么按"段"拼装而不是三条写死字符串（PRD 6.3 的必要补齐）：
/// PRD 给了 3 条文案，但**没有覆盖"上周只有 1 次称重"**——模板 2 说"体重没动
/// 很正常"，而 1 次称重根本算不出变化，这正是 W9 明令禁止的假精确。
/// 按段拼装后，PRD 那三条正好是拼装结果的三种典型形态，用户看到的字没变。
class CoachWeeklyTemplate {
  CoachWeeklyTemplate._();

  /// 禁用词与 PRD 决策 1 逐字一致（改这里必须同步改验收 W-8）
  static const List<String> kBannedWords = <String>[
    '保证',
    '一定能',
    '肯定瘦',
    '包瘦',
    '暴瘦',
    '一周瘦',
    '几天就',
  ];

  /// 40 ≤ 字数 ≤ 120，且不含禁用词。
  ///
  /// < 40 说明模型敷衍；> 120 系统通知根本看不全。
  static bool isAcceptable(String s) {
    final n = s.runes.length;
    if (n < kWeeklyMinChars || n > kWeeklyMaxChars) return false;
    return !kBannedWords.any(s.contains);
  }

  /// 目标句：由上周训练次数决定，最多两句（W10）
  ///
  /// 三档口径固定 —— 不指责、不追责，也不出现"你没做到"。
  static String goalLine(int workoutCount) {
    if (workoutCount <= 0) return '先练 1 次，10 分钟也算';
    if (workoutCount <= 2) return '练 2 次，每次 15 分钟以上';
    return '保持 3 次';
  }

  /// 模板正文：训练句（必有）+ 体重句（仅算得出变化时）+ 目标句（必有）
  static String render(WeeklyFacts f) {
    final buf = StringBuffer();

    // seg1：训练句
    if (f.workoutCount == 0) {
      // 0 次是真实值，不是"不知道" —— 但措辞仍不许追责
      buf.write('上周没怎么练，也没关系，减脂是长跑不是短跑。');
    } else {
      buf.write('上周练了 ${f.workoutCount} 次，'
          '一共 ${f.workoutMinutes} 分钟。');
      // seg2：体重句（只在算得出变化时出现，绝不填 0）
      if (f.weightChangeKnown) {
        final delta = f.weightChangeJin!;
        if (delta.abs() < 0.2) {
          buf.write('体重没动很正常，围度和状态会比秤先变。');
        } else {
          buf.write('体重从 ${_jin(f.weightStartJin!)} '
              '走到 ${_jin(f.weightEndJin!)}。');
        }
      }
    }

    // seg3：目标句
    buf.write('这周${goalLine(f.workoutCount)}');
    if (f.workoutCount == 0) buf.write('，练完随手记一下就行');
    buf.write('。');
    // 称重天数不足 → 追加一句提醒（PRD 6.3）
    if (f.weighInDays < 3) buf.write('顺手记 3 天体重。');

    return buf.toString();
  }

  static String _jin(double v) => '${v.toStringAsFixed(1)} 斤';
}
