import 'package:fittrack/features/ai/domain/coach_memory.dart';

/// 记忆的**全部策略**都在这里，且全是纯函数（零 IO）。
///
/// 为什么把策略与存取分开：M1/M3/M4/M5/M7/M8/M9/M10 每条都要能被单独证伪，
/// 而"这条该不该落库""哪条该被淘汰""注入取哪几条"如果长在 repository 里，
/// 每次验证都要先造一个库。这里全部用内存 `List<CoachMemory>` 就能断言。
class CoachMemoryPolicy {
  CoachMemoryPolicy._();

  /// 5 类白名单（唯一事实来源在 `coach_memory.dart`）
  static const Set<String> categories = kMemoryCategories;

  /// 记忆总上限
  static const int totalCap = 20;

  /// 每轮注入条数上限（4 行 × ≤60 字 ≈ 300 字，prompt 膨胀有成本）
  static const int promptLimit = 4;

  /// 注入时 `injury` 最多占的名额。
  ///
  /// **不设这个上限的副作用**：用户报 4 条伤病就会把 4 个名额全占满，
  /// `agreement`/`diet` 本轮拿到 0 个位置 —— 于是"我晚上十点后不吃东西"这种
  /// 约定被静默丢掉。安全 > 承诺的排序不变，但不能让安全信息吃掉全部预算。
  static const int injuryPromptCap = 2;

  static const int contentMaxChars = 60;
  static const int topicMaxChars = 20;

  /// 写入侧每类上限（比 PRD 的"每类 5 条"更紧，防某一类挤满全部名额）
  static const Map<String, int> perCategoryCap = <String, int>{
    'injury': 5,
    'diet': 3,
    'schedule': 3,
    'agreement': 3,
    'preference': 3,
  };

  /// 注入优先级：安全 > 承诺 > 饮食 > 作息 > 偏好
  static const List<String> injectionOrder = <String>[
    'injury',
    'agreement',
    'diet',
    'schedule',
    'preference',
  ];

  /// 首尾要剥掉的标点（Dart 的 RegExp 不支持 `\p{P}`，只能列出来）。
  ///
  /// 用"字符类片段 + 拼装"而不是写两条超长正则：`\-` 在 raw string 里保持
  /// 转义形态，拼进字符类正好是"字面减号"，不会变成区间。
  static const String _punctClass =
      r'\s，。、；：,.!?！？·…—\-~～"“”‘’()（）\[\]【】「」『』《》〈〉';
  static final RegExp _edgePunctuation =
      RegExp('^[$_punctClass]+|[$_punctClass]+\$');

  static final RegExp _whitespace = RegExp(r'\s+');

  /// 数字型身体数据（体重 / 围度）：重复存储必然和真数据打架
  static final RegExp _weightNumber =
      RegExp(r'\d+(\.\d+)?\s*(斤|公斤|kg)', caseSensitive: false);

  /// 手机号 / 身份证（隐私标识）
  static final RegExp _phone = RegExp(r'1[3-9]\d{9}');
  static final RegExp _idCard = RegExp(r'\d{15,17}[\dXx]');

  /// 医疗结论（"你有膝关节炎"这类诊断口吻）
  static final RegExp _diagnosis = RegExp(r'(有|得了|患有|属于)[^，。；]{0,10}(炎|症|病)$');

  /// 一次性信息："今天吃了碗面""我刚才练了 20 分钟"。
  ///
  /// 刻意做**窄规则**：时间前缀 + 行为动词 + 完成体（了/完/过），而不是全量
  /// 关键词匹配 —— 宽匹配会把「我晚上十点才下班」这种真正的长期作息误杀，
  /// 那是 schedule 白名单里最有价值的一条。
  ///
  /// **不能用 `^` 锚定**：中文句子里主语在最前面（「**我**今天吃了碗面」），
  /// 行首锚定只能拦住恰好以时间词开头的句子，用户带个"我"就漏检了。
  ///
  /// **`了` 不能单独当完成体判据**：`了` 有两种语义 —— 贴在动词后是"完成"
  /// （吃**了**碗面 / 练**了** 20 分钟），贴在宾语后是"状态改变"
  /// （吃素**了** / 不吃辣**了** / 戒**了**酒）。后者恰恰是 diet / agreement
  /// 里最有价值的长期事实，把"我现在吃素了"当废话丢掉等于把最有用的表达删了。
  /// 所以完成体必须**紧贴动词**（不设词后间隔），而不是"后面 2 字内出现 `了`"。
  ///
  /// **否定式豁免**：`不/没/别/戒` 紧贴在动词前时是"不做这件事"，不是"做完了"，
  /// 用负向后行断言排掉（Dart 的 RegExp 支持 lookbehind，已用最小用例验证）。
  static final RegExp _oneOff = RegExp(r'(今天|刚才|刚刚|现在)[^，。；]{0,4}(?<![不没别戒])'
      r'(吃|喝|练|称|体重|累|跑)(了|完|过)');

  /// topic 归一化：去空白、转小写、剥首尾标点；超长或为空 → null（M7）
  ///
  /// 归一化是为了让「右膝」「右膝 」是同一个键 —— 否则同一个 topic 会存出
  /// 两条互相矛盾的记忆，而且永远删不干净。
  static String? normalizeTopic(String raw) {
    var t = raw.toLowerCase().replaceAll(_whitespace, '');
    t = t.replaceAll(_edgePunctuation, '');
    if (t.isEmpty) return null;
    if (t.characters > topicMaxChars) return null;
    return t;
  }

  /// 候选条目校验（按 PRD 4.3 的顺序，命中即返回原因；null = 通过）
  ///
  /// [haystack] 是"本轮用户原话"的全文，`quote` 必须是它的**子串** ——
  /// 这是整条记忆链的防腐层：它把"AI 的推断"挡在外面。
  static String? validate(CoachMemoryCandidate c, String haystack) {
    if (!categories.contains(c.category)) return 'category 不在白名单';
    if (c.action != 'remember' && c.action != 'forget') return 'action 非法';
    final quote = c.quote.trim();
    if (quote.isEmpty) return 'quote 为空';
    if (!_containsQuote(haystack, quote)) return 'quote 不是用户原话的子串';
    // forget 不需要 topic 之外的内容校验，但 topic 必须能定位到行
    if (normalizeTopic(c.topic) == null) return 'topic 为空或超长';
    if (c.isForget) return null;
    final content = c.content.trim();
    if (content.isEmpty) return 'content 为空';
    if (content.characters > contentMaxChars) return 'content 超过 60 字';
    if (looksLikeForbidden(content)) return '内容命中"明确不记"';
    return null;
  }

  /// 「明确不记」的本地兜底拦截（M4）。
  ///
  /// prompt 里已经逐条禁止，这里再挡一道：模型偶尔会把"我今天 150 斤"抽成
  /// 长期事实，而记忆里的体重一旦和首页的对不上，用户会认为 App 在骗他。
  static bool looksLikeForbidden(String content) {
    final s = content.trim();
    if (s.isEmpty) return true;
    if (_weightNumber.hasMatch(s)) return true;
    if (_phone.hasMatch(s)) return true;
    if (_idCard.hasMatch(s)) return true;
    if (_diagnosis.hasMatch(s)) return true;
    if (_oneOff.hasMatch(s)) return true;
    return false;
  }

  /// 写入前应删除的行 id（M9 + 类目收紧）。
  ///
  /// 顺序：先按类目上限淘汰该类最久未用的；再看总量，从**非 injury** 里
  /// 淘汰最久未用的直到底线。`injury` 永不入选 —— 伤病是安全信息，
  /// 被"上次吃火锅"挤掉是事故。
  static List<int> evictionsNeeded({
    required List<CoachMemory> all,
    required String incomingCategory,
  }) {
    final out = <int>[];
    final sameCategory =
        all.where((m) => m.category == incomingCategory).toList();
    final cap = perCategoryCap[incomingCategory] ?? 3;
    if (sameCategory.length >= cap) {
      // 安全类不参与淘汰：满额时由 shouldSkipInsert 直接丢弃新条目，
      // 这里 return 空列表，绝不能返回某条旧伤病的 id。
      if (incomingCategory == 'injury') return out;
      out.add((sameCategory..sort(_byLastUsedAsc)).first.id);
    }

    var remaining = all.length - out.length + 1;
    if (remaining <= totalCap) return out;
    final candidates = all
        .where((m) => m.category != 'injury' && !out.contains(m.id))
        .toList()
      ..sort(_byLastUsedAsc);
    for (final m in candidates) {
      if (remaining <= totalCap) break;
      out.add(m.id);
      remaining--;
    }
    return out;
  }

  /// 这条候选**不该写入**（"宁可少记一条"只适用于安全类与挤无可挤）。
  ///
  /// 两种情形：① `injury` 已满 5 条 —— 不许挤掉旧伤病；② 总量已到 20 且
  /// 全是 injury，没有任何可淘汰的对象。
  ///
  /// ⚠️ **非 injury 类满额不许在这里返回 true**：PRD M9 的语义是"超限时淘汰
  /// `last_used_at` 最早的那条"，即新信息顶掉最久没用过的旧信息。若这里提前
  /// 短路，`evictionsNeeded` 里"淘汰同类最久未用"的分支就变成死代码，结果是
  /// **新的忌口被丢掉、旧的反而留着** —— 与需求正好相反。
  static bool shouldSkipInsert({
    required List<CoachMemory> all,
    required String incomingCategory,
  }) {
    final cap = perCategoryCap[incomingCategory] ?? 3;
    final sameCount = all.where((m) => m.category == incomingCategory).length;
    // ① 安全类满额：只丢弃新条目，不淘汰旧伤病
    if (incomingCategory == 'injury' && sameCount >= cap) return true;
    // ② 其余类满额：交给 evictionsNeeded 淘汰同类最久未用的那条
    final evictions = evictionsNeeded(
      all: all,
      incomingCategory: incomingCategory,
    );
    return all.length - evictions.length + 1 > totalCap;
  }

  /// 注入挑选：`injury` 先按"最近用过"选 ≤2 条，剩余名额按
  /// `agreement > diet > schedule > preference` 补足，总数 ≤ [limit]。
  static List<CoachMemory> selectForPrompt(List<CoachMemory> all, int limit) {
    if (limit <= 0 || all.isEmpty) return const <CoachMemory>[];
    final out = <CoachMemory>[];

    final injuries = all.where((m) => m.category == 'injury').toList()
      ..sort(_byLastUsedDesc);
    for (final m in injuries) {
      if (out.length >= injuryPromptCap || out.length >= limit) break;
      out.add(m);
    }
    for (final category in injectionOrder) {
      if (category == 'injury') continue;
      final group = all.where((m) => m.category == category).toList()
        ..sort(_byLastUsedDesc);
      for (final m in group) {
        if (out.length >= limit) return out;
        out.add(m);
      }
    }
    return out;
  }

  /// quote 是否是原话子串 —— 允许起一段"空白/标点差异"的宽容匹配，
  /// 但绝不放宽到"意思相近"（那就是幻觉入口）。
  static bool _containsQuote(String haystack, String quote) {
    if (haystack.contains(quote)) return true;
    String strip(String s) =>
        s.replaceAll(_whitespace, '').replaceAll(_edgePunctuation, '');
    final h = strip(haystack);
    final q = strip(quote);
    return q.isNotEmpty && h.contains(q);
  }

  static int _byLastUsedAsc(CoachMemory a, CoachMemory b) =>
      -_byLastUsedDesc(a, b);

  /// `lastUsedAt` 倒序（null = 从没用过 = 最不重要 → 排最后）
  static int _byLastUsedDesc(CoachMemory a, CoachMemory b) {
    final x = a.lastUsedAt;
    final y = b.lastUsedAt;
    if (x == null && y == null) return b.id.compareTo(a.id);
    if (x == null) return 1;
    if (y == null) return -1;
    return y.compareTo(x);
  }
}

/// 字符数（Dart 的 `String.length` 数的是 UTF-16 code unit，中文靠 `characters`
/// 才对；这里只做长度上限校验，用 runes 已经足够且不额外引依赖）
extension on String {
  int get characters => runes.length;
}
