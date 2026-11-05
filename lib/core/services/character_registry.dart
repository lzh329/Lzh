import 'package:fittrack/core/services/character_catalog.dart'
    show CharacterDef, CharacterFormSpec, CharacterId;
import 'package:fittrack/core/services/character_lines.dart';
import 'package:fittrack/core/theme/app_colors.dart';

/// 三角色的**常量定义表**（资产路径 / 档名 / 台词池 / 主色）。
///
/// 为什么从 `character_catalog.dart` 拆出来：光这三个定义就 90 多行，
/// 混在计算逻辑里会把 catalog 顶到 300 行以上（300 行纪律）。
/// 拆分后：**这份文件只放数据，catalog 只放计算**。
///
/// 资产路径只允许在这里出现（注册表是唯一事实来源）。
abstract final class CharacterRegistry {
  /// 咕嘎三档：立绘在 `assets/guga3d/`（**不在** assets/characters/），
  /// 且有 `_head` / `_body` 拆分图 ⇒ 降级走分层呼吸。
  static const CharacterDef guga = CharacterDef(
    id: CharacterId.guga,
    name: '咕嘎',
    cardTagline: '一只会陪你减的鸟，一直在',
    accent: AppColors.primary,
    forms: [
      CharacterFormSpec(
        form: 1,
        displayName: '肥咕嘎',
        minCheckinDays: 0,
        imageAsset: 'assets/guga3d/guga_fat.png',
        headAsset: 'assets/guga3d/guga_fat_head.png',
        bodyAsset: 'assets/guga3d/guga_fat_body.png',
      ),
      CharacterFormSpec(
        form: 2,
        displayName: '普通咕嘎',
        minCheckinDays: 7,
        imageAsset: 'assets/guga3d/guga_normal.png',
        headAsset: 'assets/guga3d/guga_normal_head.png',
        bodyAsset: 'assets/guga3d/guga_normal_body.png',
      ),
      CharacterFormSpec(
        form: 3,
        displayName: '小咕嘎',
        minCheckinDays: 21,
        imageAsset: 'assets/guga3d/guga_small.png',
        headAsset: 'assets/guga3d/guga_small_head.png',
        bodyAsset: 'assets/guga3d/guga_small_body.png',
      ),
    ],
    linesByTier: kGugaLinesByTier,
    introLine: kGugaIntroLine,
    formUpLine: kGugaFormUpLine,
  );

  /// 糯糯三档：只有单图（没有拆分图）⇒ 降级走单图呼吸。
  /// 档名只描述材质与发色 —— 三张图不是同一套画风，说成"瘦了"用户会去找哪里瘦了。
  static const CharacterDef nuonuo = CharacterDef(
    id: CharacterId.nuonuo,
    name: '糯糯',
    cardTagline: '换个样子陪着你，三个样子等你解锁',
    accent: AppColors.info,
    forms: [
      CharacterFormSpec(
        form: 1,
        displayName: '糯糯（玩偶版）',
        minCheckinDays: 0,
        imageAsset: 'assets/characters/nuonuo_1.png',
      ),
      CharacterFormSpec(
        form: 2,
        displayName: '糯糯（蓝发版）',
        minCheckinDays: 7,
        imageAsset: 'assets/characters/nuonuo_2.png',
      ),
      CharacterFormSpec(
        form: 3,
        displayName: '糯糯（灰发版）',
        minCheckinDays: 21,
        imageAsset: 'assets/characters/nuonuo_3.png',
      ),
    ],
    linesByTier: kNuonuoLinesByTier,
    introLine: kNuonuoIntroLine,
    formUpLine: kNuonuoFormUpLine,
  );

  /// 菲比：单形象（`forms.length == 1`），阶段感只靠台词分档（C11）。
  /// 没有升级台词 —— 她不会变样子，说了反而像 bug（风险 10）。
  static const CharacterDef phoebe = CharacterDef(
    id: CharacterId.phoebe,
    name: '菲比',
    cardTagline: '一直是这个样子，话不多但都在',
    accent: AppColors.analysis,
    forms: [
      CharacterFormSpec(
        form: 1,
        displayName: '菲比',
        minCheckinDays: 0,
        imageAsset: 'assets/characters/phoebe_1.png',
      ),
    ],
    linesByTier: kPhoebeLinesByTier,
    introLine: kPhoebeIntroLine,
    formUpLine: kPhoebeFormUpLine,
  );

  /// 白名单顺序 = 形象页卡顺序

  static const List<CharacterDef> all = [guga, nuonuo, phoebe];
}
