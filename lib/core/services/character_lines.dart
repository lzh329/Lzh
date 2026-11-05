/// 角色文案常量 —— 全 App 唯一允许出现角色名 / 形态名 / 台词的地方。
///
/// 为什么集中在一处：C10 要求「禁用词零命中」可被一条测试证伪。只要文案散落在
/// 各个 widget 里，守卫测试就只能扫全库字符串 —— 分不清「注释里提到」和
/// 「用户真的会看到」。这里全部是会被渲染的常量，扫描范围明确。
///
/// ⚠️ 两组词不要混：
/// - **形态名**（`肥咕嘎` / `糯糯（蓝发版）`）：只描述外观，出现在形象页卡、
///   趋势页卡与解锁提示里。**不许出现在问候语里**（「晚上好，糯糯（蓝发版）」读不通）。
/// - **禁用词**（`瘦了` / `胖了` / `苗条`…）：把形态和用户身材挂钩的说法。
///   形态是减重成果的可视化，不是对用户身材的评价。表里**不含"肥"** ——
///   咕嘎的档名「肥咕嘎」是既有品牌资产，说的是角色不是用户。
library;

/// 禁用词表（C10）。
///
/// 全库 UI 文案命中任意一条即失败（`test/no_forbidden_words_test.dart`）。
/// 新增文案一律写在本文件，别写在 widget 里。
const List<String> kForbiddenFormWords = [
  '瘦了',
  '变瘦',
  '苗条',
  '胖了',
  '减肥形态',
  '瘦身版',
];

/// 形象页页头说明（6.3）。
const String kCharacterSlogan =
    '换一个你愿意天天看见的。样子会跟着你减了多少变，但不会因为今天涨了一斤就退回去。';

/// 素材缺失占位（6.3 / 决策 8 第 2 层）。
const String kMissingAssetPlaceholder = '素材缺失（这个形象加载不出来，先用咕嘎）';

/// 形象页里「素材缺失」卡的短标签（卡片空间小，用短版；长版给首页兜底提示）
const String kMissingAssetShort = '素材缺失';

/// 术语：用户向一律叫「样子」，不叫「形态 / 阶段 / 等级」（决策 5 / C8）。
///
/// 代码与文档内部仍用 `form`，但**任何用户可见的字符串都不许出现"形态"二字**
/// —— 出现了就说明有人把内部术语漏到了 UI。
const String kTermForm = '样子';

/// 解锁提示的两种句式（C18 / 6.3）。
///
/// 形态由**累计打卡天数**决定（减重只用于文案与数据展示，不参与档位）：
/// 打卡天数只增不减，所以档位只升不降，不会出现"练了却退回上一档"。
String kRemainToNextForm(int remainDays, String nextFormName) =>
    '再打卡 $remainDays 天解锁「$nextFormName」';

/// 全部解锁（C18 的另一种状态）。**只用于"状态行"**（趋势卡），
/// 形象页卡的描述行用 [kFormsProgressLine]，避免同一张卡上两句话打架。
const String kAllFormsUnlocked = '已解锁全部样子';

/// 形象页卡**描述行**（C18 修订）：按解锁状态二选一，不写死。
///
/// 为什么不能写死："三个样子等你解锁"配"已经全部解锁"会让同一张卡自相矛盾
/// （装机实测问题 2）。所以描述行由状态算出来，状态行只负责"当前/还差多少"。
String kFormsProgressLine({
  required int checkinDays,
  required int? remainDays,
  required String? nextFormName,
}) {
  if (remainDays == null) return '已打卡 $checkinDays 天 · 已解锁全部样子';
  return '已打卡 $checkinDays 天 · 再 $remainDays 天解锁「${nextFormName ?? ''}」';
}

// 单形象角色（菲比）**没有**"解锁"类状态行：她只有一个样子，
// 说"解锁/解锁进度"都是凭空造概念 —— 页面直接不画那一行。

// ───────────────────── 咕嘎（沿用现有档名，不改） ─────────────────────

const String kGugaIntroLine = '我来了，我是咕嘎。';
const String kGugaFormUpLine = '我小了一圈。';

/// 咕嘎台词池：tier 与 form 同号（1/2/3），每档 ≥3 句（C11）。
///
/// 语义沿用 `guga_level.dart` 里各档 `tagline`，但口语化 —— tagline 是卡片标题，
/// 台词是角色第一人称说话，两种语域不能直接复用。
const Map<int, List<String>> kGugaLinesByTier = {
  1: [
    '今天动一动就行，别想太多',
    '先记一笔体重，我看看',
    '慢慢来，我又不催你',
  ],
  2: [
    '已经上路了，保持这个节奏',
    '今天练完记得记一下',
    '你最近挺稳的',
  ],
  3: [
    '我一直就这样了，剩下的靠你',
    '今天想练啥，我陪着',
    '别急着加量，稳住就赢',
  ],
};

// ───────────────────── 糯糯（档名只描述材质与发色） ─────────────────────

const String kNuonuoIntroLine = '我是糯糯，慢慢处。';
const String kNuonuoFormUpLine = '换了个样子，你都没发现吧。';

const Map<int, List<String>> kNuonuoLinesByTier = {
  1: [
    '我有点软，你捏一下试试',
    '今天要不先称个体重',
    '我们慢慢来嘛',
  ],
  2: [
    '换了个样子，你发现了吗',
    '今天想练什么，我等着',
    '你比上周稳了',
  ],
  3: [
    '我这样挺久了，剩下的靠你',
    '今天别硬上，练够就行',
    '记一下今天，回头看有意思',
  ],
};

// ───────────────────── 菲比（单形象，靠台词分档体现进展） ─────────────────────

const String kPhoebeIntroLine = '菲比在。你想干嘛都行。';

/// 菲比没有形态变化，所以**没有**升级台词（C11 / 6.3）。
/// 用 null 而不是空串：空串会让"没这句"和"这句是空"分不清。
const String? kPhoebeFormUpLine = null;

const Map<int, List<String>> kPhoebeLinesByTier = {
  1: [
    '我在这儿，你先动一下',
    '今天记个体重吧，就一件事',
    '不急，先来一次',
  ],
  2: [
    '你最近没断，我看见了',
    '今天练点啥？',
    '记得记一下，不然后面看不出来',
  ],
  3: [
    '你比刚开始那会儿稳多了',
    '今天练个小份的也行',
    '我一直这个样，你变了不少',
  ],
};

// ───────────────────── 切换时说的一句（1.5s 内） ─────────────────────

/// 刚切换角色时 1.5s 内说的那句（决策 2 / C6）。之后回落到日常台词池。
const Map<String, String> kCharacterIntroLines = {
  'guga': kGugaIntroLine,
  'nuonuo': kNuonuoIntroLine,
  'phoebe': kPhoebeIntroLine,
};
