# assets/rive/ —— 角色骨骼动画目录

> ⚠️ **删掉这个文件会让 `flutter build` 直接报 `unable to find directory entry`。**
> `pubspec.yaml` 声明的是**目录**（`- assets/rive/`），Flutter 要求被声明的目录非空。
> 本目录本轮故意只放这一个说明文件、不放任何 `.riv`，理由见下。

## 命名规则（写死，不要改）

```
assets/rive/{character}_{form}.riv
```

| 字段 | 取值 |
|---|---|
| `character` | `guga` / `nuonuo` / `phoebe` |
| `form` | `1` / `2` / `3`（**1 起算，不用 0**；菲比恒为 1） |

与 `assets/characters/{character}_{form}.png` 的 `form` 同号，与 Rive 编辑器里的
`form` 数值输入同号 —— 三处同号，改一处就三处一起改。

完整清单见 `lib/core/services/character_catalog.dart` 里的 `CharacterFormSpec`，
那是**唯一事实来源**；本文档只做说明，代码不读它。

## 为什么本轮一个 `.riv` 都没有

本期交付的是**链路**，不是素材：

1. 上线后 10 个 `.riv` 全部缺失 ⇒ 100% 走程序化动画（分层呼吸 / 单图呼吸 + 点击摆头）。
   降级路径**必须先做且必须和 Rive 路径行为等价**，所以让"缺文件"成为默认状态，
   等于每天都在验收降级路径。
2. 官方示例 `.riv` **不进生产资产**：首页出现别人的素材，比不接 Rive 更糟。
   链路验证用的夹具放在 `test/fixtures/`，只在测试里被引用。

## 怎么换成真的 Rive（不改代码）

1. 按上表命名，把 `.riv` 放进本目录。
2. 跑一次 `flutter pub get`（新增文件后资产清单要重建；改内容不需要）。
3. 重启 App。首页角色区下一次进入时会重新预检一次（不做全局缓存），
   预检通过就播 Rive。

`.riv` 必须满足的契约（作者在 Rive 编辑器里实现）：

- state machine 名固定 `main`
- 输入：`tap`(Trigger) / `speaking`(Boolean) / `form`(Number 1|2|3) / `celebrate`(Trigger)
- 输出：`react_end`(Event)；缺失时 Flutter 侧用 1.5s 超时兜底
- 内部状态：`idle`(默认，**必须能无限循环**) / `tap_react`(≤1.5s) / `celebrate`(≤2.0s)
- 单文件 ≤300 KB

任何一条不满足都会**静默**降级到程序化动画（不弹窗、不写库），
debug 构建下形象页底部会显示降级原因。
