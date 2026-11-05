import 'package:flutter/material.dart' show Color;

import 'package:fittrack/core/services/character_registry.dart';

/// 角色白名单（C1）：只有这三个值。
///
/// 为什么用枚举而不是字符串常量：写入口
/// [`UserSettingsRepository.saveCharacterId`] 的签名收窄成枚举之后，
/// 「把 DB 里的脏值原样写回去」在类型层面就不成立了（C4）。
/// 非法值可以在读路径显示错，但不许改数据。
enum CharacterId {
  guga('guga'),
  nuonuo('nuonuo'),
  phoebe('phoebe');

  const CharacterId(this.wire);

  /// 落库值（`user_settings.character_id`）
  final String wire;

  /// 读路径唯一入口：非法/空/null/大小写不符 一律回落咕嘎（C1）。
  ///
  /// **永不写库** —— 这里只决定"显示成谁"，不修正数据（C4）。
  static CharacterId parse(String? raw) => tryParse(raw) ?? CharacterId.guga;

  /// 严格匹配（不做 lower/trim）：`'GUGA'`、`' guga'` 都算非法值。
  ///
  /// 为什么不一并宽松处理：宽松匹配会让"新版本写入了 `'GUGA'`"这种脏数据
  /// 看起来像正常的咕嘎，掩盖真正的写入 bug。
  static CharacterId? tryParse(String? raw) {
    if (raw == null) return null;
    for (final id in values) {
      if (id.wire == raw) return id;
    }
    return null;
  }
}

/// 一个「样子」的资源与文案声明。
///
/// 这是**资产路径的唯一来源**（B-b 决定 / R2 的落地形式）：UI 里不许拼
/// `xxx.replaceFirst('.png', '_head.png')` 这种字符串 —— 糯糯/菲比根本没有
/// `_head` 文件，拼出来就是白框。
class CharacterFormSpec {
  /// 形态档位，**1 起算**（文件名、Rive `form` 输入、代码三处同号，R2）
  final int form;

  /// 形态名（用户可见）：只描述外观，禁止身材评价词（C9）
  final String displayName;

  /// 进入该档所需的**累计打卡天数**（中间断了不清零）
  ///
  /// 曾经用"历史最大减重"决定形态，但减重受水分/聚餐影响会回弹，
  /// 用户会因为"明明练了却退回上一档"而困惑。改按打卡天数后，档位只升不降。
  final int minCheckinDays;

  /// 单图立绘（糯糯/菲比只有这个）
  final String? imageAsset;

  /// 分层拆图：头
  final String? headAsset;

  /// 分层拆图：身体
  final String? bodyAsset;

  const CharacterFormSpec({
    required this.form,
    required this.displayName,
    required this.minCheckinDays,
    this.imageAsset,
    this.headAsset,
    this.bodyAsset,
  });

  /// 有 `_head`+`_body` 拆分图 ⇒ 降级走"分层呼吸"（R9）。由**声明**决定，
  /// 不按角色名硬编码 —— 将来给糯糯补拆分图，加两行常量即生效。
  bool get hasSplit => headAsset != null && bodyAsset != null;

  bool get hasImage => imageAsset != null;
}

/// 角色定义：身份 + 阶段表 + 台词池 + 文案。
class CharacterDef {
  final CharacterId id;

  /// 角色名（**用户向，不带形态名**）：问候语、气泡、prompt 只用这个（C19）
  final String name;

  /// 形象页卡描述行。**只有单形象角色（菲比）用它**；多形象角色的描述行由
  /// `kFormsProgressLine` 按解锁状态算（写死会和"都解锁了"自相矛盾）。
  final String cardTagline;

  /// 主色，只取 `AppColors` 现有令牌，不新增色值（避免和主题打架）
  final Color accent;

  /// 阶段表，至少 1 项（菲比只有 1 项，C11）
  final List<CharacterFormSpec> forms;

  /// 台词池：tier → 台词（每档 ≥3 句，C11）
  final Map<int, List<String>> linesByTier;

  /// 刚切换到该角色时说的那句（1.5s 内）
  final String introLine;

  /// 升级时说的那句；单形态角色为 null（菲比不触发，C11）
  final String? formUpLine;

  const CharacterDef({
    required this.id,
    required this.name,
    required this.cardTagline,
    required this.accent,
    required this.forms,
    required this.linesByTier,
    required this.introLine,
    this.formUpLine,
  });

  /// 该角色的最高档位（菲比 = 1）
  int get maxForm => forms.isEmpty ? 1 : forms.length;

  /// 取某档的声明；越界一律夹到合法区间（永不抛 —— 渲染路径不该有异常分支）
  CharacterFormSpec formSpec(int form) {
    final i = form.clamp(1, maxForm) - 1;
    return forms[i];
  }

  /// 形态档位：由**累计打卡天数**算 —— 取「满足 minCheckinDays <= 天数」的最大档，
  /// 夹到该角色的最大档（菲比恒 1，C11）。
  ///
  /// 只升不降：打卡天数只增不减，所以档位永不回退。
  int formForCheckinDays(int totalDays) {
    final days = totalDays < 0 ? 0 : totalDays;
    var form = 1;
    for (final f in forms) {
      if (days >= f.minCheckinDays) form = f.form;
    }
    return form.clamp(1, maxForm);
  }

  // 刻意**没有** def 级 remainToNextJin / nextFormName：与 `_build` 同算法，
  // 两处实现必然漂。要这两个值请读 `CharacterRenderSpec`。
}

/// 一个角色 + 一次减重计算结果 → **完整的渲染描述**（C12）。
///
/// 全 App 4 处渲染（首页角色区、问候小头像、趋势卡、聊天头像）只准读这一份规格，
/// 杜绝第二套口径。
class CharacterRenderSpec {
  final CharacterId id;

  /// 角色名（不带形态名）—— 问候语 / 气泡说话人 / prompt 用
  final String name;

  /// 形态档位 1/2/3（菲比恒 1）
  final int form;

  /// 台词档位 1/2/3（菲比也会变，C11）
  final int lineTier;

  /// 形态名（用户可见，只出现在形象页卡 / 趋势卡 / 解锁提示）
  final String formName;

  final String? imageAsset;
  final String? headAsset;
  final String? bodyAsset;

  /// `assets/rive/{id}_{form}.riv`（R2；目录本轮只有 PROVENANCE.md ⇒ 必然降级）
  final String rivPath;

  /// 当前档位的台词池（日常台词，随机轮换不重复上一句）
  final List<String> linePool;

  /// 累计打卡天数（形态口径）
  final int checkinDays;

  /// 距下一档还要打卡多少天；已满档 null
  final int? remainToNextDays;

  /// 下一档的形态名；已满档 null
  final String? nextFormName;

  final Color accent;
  final String introLine;
  final String? formUpLine;
  final bool hasSplit;
  final bool isMaxForm;

  const CharacterRenderSpec({
    required this.id,
    required this.name,
    required this.form,
    required this.lineTier,
    required this.formName,
    required this.imageAsset,
    required this.headAsset,
    required this.bodyAsset,
    required this.rivPath,
    required this.linePool,
    required this.checkinDays,
    required this.remainToNextDays,
    required this.nextFormName,
    required this.accent,
    required this.introLine,
    required this.formUpLine,
    required this.hasSplit,
    required this.isMaxForm,
  });

  /// 立绘可用（单图或分层任一具备）
  bool get hasAsset => imageAsset != null || hasSplit;

  /// 小图 / 头像用的资产：优先 `_head` 拆分图（贴脸好看），否则整图，
  /// 最后兜底咕嘎的头 —— 这是"最后一道保险"，正常情况下走不到。
  ///
  /// 为什么要有它：4 个渲染位（首页小头像、今日任务小图、趋势卡、聊天页头像）
  /// 都要"头像"，但糯糯/菲比没有 `_head` 文件。各页面自己 `replaceFirst`
  /// 就会拼出不存在的路径（白框），所以只在这里决定一次。
  String get avatarAsset =>
      headAsset ??
      imageAsset ??
      CharacterCatalog.guga.forms.first.headAsset ??
      '';
}

/// 角色注册表 —— 资产路径 / 档位 / 台词的唯一事实来源。
///
/// `resolve()` 是**纯函数**：同入参同出参、不读 DB、无副作用（C12）。
abstract final class CharacterCatalog {
  // 三个角色定义在 `character_registry.dart`（纯常量表，本文件只剩类型与计算）。
  // 分开是为了守住 300 行纪律：catalog 的计算逻辑不该被 3 段 const 常量淹没。
  static CharacterDef get guga => CharacterRegistry.guga;
  static CharacterDef get nuonuo => CharacterRegistry.nuonuo;
  static CharacterDef get phoebe => CharacterRegistry.phoebe;
  static List<CharacterDef> get all => CharacterRegistry.all;

  /// 还没读到设置 / 体重时的兜底规格（= 咕嘎 1 档）。
  ///
  /// 为什么要有它：首页首帧不能等 `FutureProvider` 完成再画角色 ——
  /// 那会让首屏先空一块再"跳出"角色（首帧 ≤300ms 的观感红线）。
  static final CharacterRenderSpec fallback = resolve(null, 0);

  static CharacterDef defOf(CharacterId id) {
    for (final def in all) {
      if (def.id == id) return def;
    }
    // 理论上不可达（枚举穷尽），但渲染路径不该有抛异常的分支
    return guga;
  }

  /// 角色 + 累计打卡天数 → 渲染描述。**纯函数**：无 DB、无 IO、无缓存。
  ///
  /// [rawId] 是 `user_settings.character_id` 的**原始字符串**，可以做脏：
  /// 空串 / 大写 / 中文 / 未来版本的角色名一律按咕嘎渲染，且**不回写库**（C1/C4）。
  static CharacterRenderSpec resolve(String? rawId, int checkinDays) =>
      specOf(defOf(CharacterId.parse(rawId)), checkinDays);

  /// 从一个**具体的角色定义**算渲染描述。
  ///
  /// `resolve()` 走白名单（脏值回落咕嘎）；这个入口直接吃定义对象，
  /// 让"注入一个立绘缺失的定义"这种测试也能走同一条计算（C15 的可测形式）。
  static CharacterRenderSpec specOf(CharacterDef def, int checkinDays) {
    final days = _saneDays(checkinDays);
    return _build(def, def.formForCheckinDays(days), days);
  }

  /// 指定角色 + **指定档位**的规格：素材缺失时"换角色但不换档"用（C15 层 2）。
  /// 不按减重重算：回落时不该让形象**跳档**（菲比图丢了却冒出第 3 档咕嘎 = 像 bug）。
  static CharacterRenderSpec specOfForm(
          CharacterId id, int form, int checkinDays) =>
      _build(defOf(id), form, _saneDays(checkinDays));

  static int _saneDays(int raw) => raw < 0 ? 0 : raw;

  /// 唯一的构造点：`form` 由外部决定（正常路径来自 loss，回落路径来自当前档）
  static CharacterRenderSpec _build(
      CharacterDef def, int rawForm, int days) {
    final form = rawForm.clamp(1, def.maxForm);
    final formSpec = def.formSpec(form);
    // 台词档位与形态同档：形态只升不降，台词也就只升不降
    final tier = form;
    // 还差多少天：下一档阈值 − 当前天数（已满档 → null）
    final remain = form >= def.maxForm
        ? null
        : (def.forms[form].minCheckinDays - days).clamp(0, 9999);

    return CharacterRenderSpec(
      id: def.id,
      name: def.name,
      form: formSpec.form,
      lineTier: tier,
      formName: formSpec.displayName,
      imageAsset: formSpec.imageAsset,
      headAsset: formSpec.headAsset,
      bodyAsset: formSpec.bodyAsset,
      // .riv 路径按规则拼（该目录本轮为空，规则可硬编码；立绘路径则由注册表声明）
      rivPath: 'assets/rive/${def.id.wire}_${formSpec.form}.riv',
      linePool: def.linesByTier[tier] ?? def.linesByTier[1] ?? const <String>[],
      checkinDays: days,
      remainToNextDays: remain,
      nextFormName: form >= def.maxForm ? null : def.forms[form].displayName,
      accent: def.accent,
      introLine: def.introLine,
      formUpLine: def.formUpLine,
      hasSplit: formSpec.hasSplit,
      isMaxForm: form >= def.maxForm,
    );
  }
}
