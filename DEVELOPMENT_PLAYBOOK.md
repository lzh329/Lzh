# 简瘦 FitTrack — 项目体检报告与重整开发方案

> **日期**：2026-10-16
> **基线**：v1.2.0（Git 快照 f595b25）
> **用途**：重新开发阶段的行动依据。与 PROJECT.md（产品宪法）配套使用。
> **一句话结论**：**不要推倒重来。** 项目是"局部乱"，不是"全局烂"。用 4 周做一次外科手术式重构 + 建立工程纪律，就能把一个已经能跑的产品变成可持续演进的代码库。

---

## 一、体检结果（2026-10-16 实测）

### 1.1 项目规模

| 指标 | 数值 |
|------|------|
| Dart 文件 | 57 个（含生成代码 1 个） |
| 手写代码 | 约 12,300 行（另有 database.g.dart 生成代码 8,764 行） |
| 数据库 | Drift，schemaVersion = 11，12 张表 |
| 功能完整度 | v1.2 全部功能已实现：仪表盘 / 体重围度 / 饮食 / 训练 / 计划 / 目标 / 照片 / 周报 / 月对比 / 饮水 / 导出 / 主题 |
| 环境 | Flutter 3.47.7 stable + Dart 3.13.5（D:/dev/flutter），项目构建通过 |

### 1.2 健康度指标

| 维度 | 现状 | 评级 |
|------|------|------|
| 静态分析 | 47 条（45 info + 2 warning + **0 error**） | 🟡 |
| 测试 | 7 个测试全部通过，但只覆盖 entity 构造与主题常量，**业务逻辑 0 覆盖** | 🔴 |
| 文件规模 | **12 个文件超 300 行纪律**，其中 6 个超 500 行（最大 1272 行） | 🔴 |
| 状态管理 | FutureBuilder 残留 10 个文件；setState 残留 12 个文件；手动刷新计数器存活 | 🔴 |
| Git 历史 | 仅 1 个快照 commit，另有 8 个文件未提交 | 🔴 |
| 架构分层 | Clean Architecture + Feature-First 已落地约 70%，方向正确 | 🟢 |
| 文档 | PROJECT.md（产品+架构宪法）质量高，VERSION_1.2_PLAN.md 记录完整 | 🟢 |

### 1.3 超标文件明细（300 行纪律 vs 实际）

| 文件 | 行数 | 超标倍数 |
|------|------|---------|
| dashboard/presentation/dashboard_page.dart | 1272 | 4.2x |
| body_log/presentation/pages/body_metric_page.dart | 1204 | 4.0x |
| settings/presentation/pages/settings_page.dart | 697 | 2.3x |
| diet/presentation/pages/diet_page.dart | 633 | 2.1x |
| workout/presentation/pages/workout_active_page.dart | 620 | 2.1x |
| workout/presentation/notifiers/workout_session_notifier.dart | 553 | 2.8x（Notifier 上限 200） |
| plan/presentation/pages/plan_create_page.dart | 431 | 1.4x |
| workout/presentation/pages/workout_detail_page.dart | 426 | 1.4x |
| analysis/presentation/pages/weekly_report_page.dart | 409 | 1.4x |
| workout/presentation/pages/workout_stats_page.dart | 383 | 1.3x |
| workout/presentation/pages/workout_list_page.dart | 337 | 1.1x |
| exercise/presentation/pages/exercise_manage_page.dart | 333 | 1.1x |

### 1.4 问题清单（按严重度排序）

| # | 问题 | 证据 | 影响 |
|---|------|------|------|
| 1 | 无 Git 历史 | 单 commit + 8 个未提交文件 | 改错了无法回滚，无追溯，重构没有退路 |
| 2 | 业务逻辑零测试 | 82 行测试，仅测 entity 构造和主题常量 | 改一处怕坏三处 → 只能往上堆 → 越堆越乱（恶性循环的根源） |
| 3 | 12 个超大文件 | 见 1.3 | 逻辑与 UI 纠缠，难读难改，出错高发区 |
| 4 | 手动刷新计数器存活 | `dashboardRefreshCount` 手动 `state++` 散布在 5 个文件 13 处 —— 正是 PROJECT.md 明令禁止的 `dataVersionProvider++` 模式（改了名字但本质相同） | 刷新时机不可预测，状态不一致的经典根源 |
| 5 | 双体系并存 | Riverpod 已引入，但 FutureBuilder（10 文件）+ setState（12 文件）照旧使用 | 两套心智模型互相纠缠，新人（包括未来的你）难以判断该用哪套 |
| 6 | 47 条分析告警 | 其中含 7 处 `use_build_context_synchronously`（异步后用 context 的真实风险点）、2 处 Radio API 弃用 | 真实风险被淹没在噪音里，等于没有告警 |
| 7 | 依赖滞后 | 24 个包有新版但被约束卡住 | 升级成本随欠债时间指数增长 |

### 1.5 上一轮规划（PROJECT.md Phase 3）的完成度

| 任务 | 状态 |
|------|------|
| 训练执行层统一（WorkoutSessionNotifier + 统一 WorkoutActivePage） | ✅ 已完成，旧 PlanExecutePage 已删除 |
| 空目录清理（usecases/ 等） | ✅ 无空目录残留 |
| 饮水功能决策（加 UI 或删除） | ✅ 已选"加 UI"路线（water_page.dart + 首页卡片已存在） |
| FutureBuilder → Riverpod | ❌ 未开始（10 个文件） |
| 迁移基线化 | ⚠️ 未做（schema 已到 v11，迁移链未清理） |

**结论：上轮规划不是废纸，是只执行了三分之一。剩下三分之二正是本方案 Phase 2 的内容。**

---

## 二、战略判断：不推倒重来，做渐进式重构

### 2.1 为什么"重新开发"不该等于"推倒重写"

想推倒重来的心理很常见（"之前写得太乱，推倒重来最干净"），但这里不成立：

**重写的账算不过来：**
- 要重写 12,300 行、12 张表、11 个功能模块 —— 这里面大量的"边界情况处理"（日历跨月、体重跨周对比、计划执行状态机……）是踩坑踩出来的，重写必然重踩一遍
- 项目有真实用户依赖（PROJECT.md 明确立项：Plan 系统"已有用户依赖"），重写期间产品停摆
- **最关键的**：乱的原因是**工程纪律缺失**，不是架构方向错误。纪律不补，重写的新代码三个月后一样乱 —— 这是软件工程里最常见的"第二次重写陷阱"

**本项目真正的状态：**
- 架构方向是对的：Clean Architecture + Feature-First 已落地 70%（core/features 分层、data/domain/presentation 三层、Repository 模式、Riverpod 已引入）
- 乱是**局部的、可定点清除的**：6 个大文件 + 1 个手动刷新模式 + 10 处 FutureBuilder
- 已经有部分治理成果（训练执行层统一）

**正确的做法：像改造房子，不是推倒重建。**
- 保留承重墙：数据层、domain 层、路由、主题
- 拆掉违章隔断：12 个大文件
- 重铺电路：FutureBuilder / 手动刷新 → 纯 Riverpod
- 装好安全系统：测试 + 静态分析门禁

> **什么情况下才值得真·重写**：架构方向错误（比如完全没有分层、状态全局散落）、技术栈不可渐进升级、代码量小于 2 周人力。以上三条本项目都不满足。

### 2.2 混乱的四个根因（先治病根，再清症状）

1. **没有安全网**（零测试）→ 不敢改 → 只能堆 → 熵增
2. **没有退路**（无 Git 历史）→ 怕改错无法恢复 → 更不敢改
3. **没有门禁**（300 行纪律只写在文档里，没人拦）→ 文件想多大就多大
4. **没有统一模式**（新旧两套状态管理并存）→ 每写一个页面都是一次即兴发挥

**对症下药**：这四条全部在本方案 Phase 0/1 解决，剩下的全是机械性工作（Phase 2）。

---

## 三、重整路线图

### 节奏总览：功能与 UI 开发从第 2 周就启动

本方案**不是**「先重构 4 周、再开发功能」。真实节奏：

| 时间 | 主线 | 性质 |
|------|------|------|
| 今天（Phase 0） | 提交基线、打 tag | 半小时 |
| 本周（Phase 1） | 清告警 + 补关键测试 + 门禁生效 | 打地基，2~4 天 |
| 第 2 周（Phase 2） | **功能 + UI 开发正式启动**：首个任务 = 首页减脂仪表盘改版 | 改版即重构 |
| 第 3 周起（Phase 3） | 每周一个功能迭代，顺手拆掉碰到的旧文件 | 常态节奏 |

关键原则：**重构不单独占档期，跟着功能走。** 要改版的页面，借改版直接按新规范重写（UI 重做 + 拆文件 + Riverpod 化一次完成）；不会被碰的页面，等它下次被功能碰到时再拆。

### Phase 0 — 止血与基线（✅ 本地部分已完成，剩 push）

- [x] 提交适配修改（Flutter 3.47 工具链）+ 开发手册与门禁脚本（2 个 commit）
- [x] 打基线 tag：`v1.2.0-baseline`
- [x] 环境备忘落地（NO_PROXY 绕过已写入 check.sh）
- [ ] **push 到远程**：`git push origin master --tags`（origin 已配置为 github.com/lzh329/Lzh.git，执行前确认仓库可见性）

**验收**：远程仓库有完整代码与 tag。

### Phase 1 — 安全网（第 1 周）

**目标：让"改代码"这件事从"赌命"变成"可控"。**

1. **清理静态分析**（半天）
   - 47 条告警清零。优先修 7 处 `use_build_context_synchronously`（真实风险）和 2 处 Radio 弃用
   - 之后 `flutter analyze` 必须保持 0 issue

2. **补测试安全网**（核心工作，2-3 天）
   - `test/core/database_test.dart`：空库建表（校验 v11 全表 + 关键字段）+ 迁移测试
   - `test/features/*/repository_test.dart`：用 `NativeDatabase.memory()` 内存库，逐 repo 测 CRUD + 边界（空表、级联删除、重复写入）
   - `test/core/calculations_test.dart`：核心计算逻辑（BMI/BMR/TDEE、热量缺口、周体重变化、趋势预测）——数值断言
     - ⚠️ 这些计算目前散在页面里。测试之前先**提取到 `core/services/` 或 domain**（提取本身就是在拆大文件，一举两得）
   - 原则：**测试只覆盖数据层和计算逻辑，不追 UI 覆盖率**（UI 变化快，性价比低）

3. **建立提交门禁**（半天）
   - 已备好脚本：`bash scripts/check.sh`（analyze + test 一条命令，已处理本机代理问题）
   - 规矩：**check.sh 不绿，不许提交**

**验收**：analyze 0 issue；核心数据层 + 计算逻辑测试全绿；check.sh 可运行。

### Phase 2 — 功能驱动重构（第 2 周起，功能与 UI 开发同步启动）

**从第 2 周开始，主线就是功能开发，重构跟着功能走。** 每周一个功能任务，开工前检查本次要碰的页面，按三类处理：

| 情况 | 处理方式 |
|------|---------|
| 要改版/重做的页面是大文件或旧模式 | **借这次改动按新规范直接重写**（UI + 拆文件 + Riverpod 一次完成），不必先"行为不变拆一遍"再改 |
| 要动的小文件 | 顺手按新规范清理：Riverpod 化 + 补测试 |
| 不碰的文件 | 不动它，留到下次被功能碰到时 |

**首个任务（建议第 2 周开工）：首页减脂仪表盘改版**
- UI：按 PROJECT.md Phase 1 重做首页（周体重变化 / 目标倒计时 / 热量缺口 / 本周训练天数）
- 重构合体：`dashboard_page.dart`（1272 行）拆为 widgets/ 子组件；移除 `dashboardRefreshCount` 手动刷新（改 `ref.invalidate`）；删除励志标语
- 一单双收：最大的一块 UI 改版 + 最大的一个文件治理同时落地

**其余大文件的处理时机（不单独立项，等对应功能来碰）：**

| 文件 | 等什么功能来碰它 |
|------|----------------|
| body_metric_page（1204） | 体重卡片升级 / 趋势增强 |
| settings_page（697） | 设置项调整 / 提醒设置开发 |
| diet_page（633） | 热量缺口可视化开发 |
| workout_active_page + session_notifier | 训练流程优化 |
| 其余 6 个 300-450 行文件 | 低峰期批量收尾，或下次功能顺路 |

**"拆解五步法"仅用于不改行为、不动 UI 的纯清理场景：**
```
① 先写该页面的关键路径特性测试（锁住现有行为）
② 纯搬运式拆分（只移动代码，不改逻辑）
③ 跑测试 —— 全绿 = 行为没变
④ 该文件内顺手统一为 Riverpod（仅限已被测试覆盖的部分）
⑤ 单独提交（一个文件一个 commit），更新 PROJECT.md 完成度
```

**验收（动态）**：每周结束时全库超限文件数只减不增；`dashboardRefreshCount` 在首页改版后消失；FutureBuilder 随页面逐个改版清零。

### Phase 3 — 常态迭代（第 3 周起，持续进行）

功能路线完全回到 PROJECT.md 的 v2 路线图（减脂聚焦 → 减脂闭环 → 增长）。每周节奏固定：

- 每周一个功能迭代 = 实现 + 测试 + 文档更新（PROJECT.md / CHANGELOG）
- 功能涉及的旧文件顺手重构，不积累新债
- 每周五跑全量 `check.sh`，全绿打小版本 tag

---

## 四、开发纪律（从今天起的硬规矩）

### 4.1 七条铁律

1. **小步提交**：一个功能/修复/重构 = 一个 commit。禁止"攒一周再提交"（这是上一个 commit 变成快照的原因）
2. **提交前检查**：`bash scripts/check.sh` 全绿才能提交
3. **main 永远可运行**：新功能开 `feature/xxx` 分支，完成合入；重构开 `refactor/xxx`
4. **文件上限**：Page 300 / Notifier 200 / Repository 150 行 —— 超了就拆，没有例外
5. **模式唯一**：异步状态一律 Riverpod（FutureProvider / Notifier）；数据写入后 `ref.invalidate` 让依赖自动刷新。**禁止 FutureBuilder、禁止 setState 管异步、禁止手动刷新计数器**
6. **bug 先复现**：修任何 bug 先写一个能复现的测试，再修
7. **文档先行**：新功能先写进 PROJECT.md（一句话定义 + 验收标准）再开工

### 4.2 单文件拆解流程

- **纯清理（不改 UI、不改行为）**：走 Phase 2 的"拆解五步法"。核心心法：**先测后拆、纯搬运、最后优化**，绝不允许"边拆边改逻辑"。
- **页面改版（UI 要变）**：直接按新规范重写该页面即可，不需要"先行为不变拆一遍"——改版本身就是最好的重构机会。

### 4.3 版本节奏

| 阶段 | 版本 | 内容 |
|------|------|------|
| 现在 | v1.2.0-baseline（tag） | 冻结现状 |
| Phase 1 完成 | v1.2.1 | 安全网 + 告警清零 |
| 第 2 周（Phase 2） | v2.0.0 | 首页减脂仪表盘改版上线（功能+重构合体首单） |
| 第 3 周起 | v2.1、v2.2… | 每周一个功能迭代递增 |

---

## 五、环境备忘（本机）

| 事项 | 说明 |
|------|------|
| Flutter SDK | `D:/dev/flutter`（3.47.7 stable，不在 PATH，用绝对路径调用） |
| Git 权限修复 | 已执行 `git config --global --add safe.directory D:/dev/flutter`（否则 flutter 命令报 dubious ownership） |
| ⚠️ 测试绕代理 | 本机 Clash 代理（127.0.0.1:51650）未排除本地地址，导致 `flutter test` 报 `Invalid WebSocket upgrade request`。**跑测试必须设 `NO_PROXY=127.0.0.1,localhost` 且清空 HTTP_PROXY**（check.sh 已内置） |
| 依赖状态 | pub 已解析 135 个依赖；24 个包有新版被约束卡住（升级择机进行，先不动） |
| 数据库迁移 | 改表后：递增 schemaVersion → 写迁移 → `dart run build_runner build` → **空库安装 + 旧库升级两条路径都要手测** |

---

## 六、本方案的执行原则

1. **一次只动一个文件**，拆完即验证、即提交 —— 不追求一周变干净，追求每周都在变干净
2. **任何阶段全绿才前进**：check.sh 红 = 停下修，不带着问题往下走
3. **三次失败即暂停**：同一个问题连续修 3 次没解决，停下来记录现象、求助，不硬扛
4. **行为不变是重构的唯一验收标准**：重构 commit 里不应出现任何功能变化

---

## 七、数据库迁移铁律（改迁移前必读）

> 背景：本 App **本地优先、无后端**。库坏掉 = 用户数据全丢，没有第二条路可救。
> 迁移写错的代价不是"报个错"，是"用户卸载重装"。

### 7.1 `onUpgrade` 不在事务里（已核源码）
drift 2.35.2 的 `onUpgrade` **不在事务中执行**（全包唯一事务在 `alterTable()` 内部）。
所以迁移块里每一条 DDL 都是**独立提交、各自 fsync**；第 2 条失败时第 1 条已经落盘，
而 `user_version` 不会推进 → 下次启动从同一个 `from` 重跑整个块。

### 7.2 迁移块内只允许四种操作
1. `createTableIfNotExists(m, table)`（`core/database/migration_helpers.dart`）
2. `addColumnIfNotExists(m, table, column)`（同上）
3. `CREATE INDEX IF NOT EXISTS ...`（SQLite 原生幂等，无需封装）
4. 自带幂等条件的 DML：`WHERE ... IS NULL`，或「表非空就早退」守卫

**不允许**裸 `m.createTable(` / `m.addColumn(`。裸 `addColumn` 是裸 `ALTER TABLE ADD COLUMN`，
重跑必抛 `duplicate column name` → App 启动即死。`test/migration_helpers_test.dart`
有源码守卫测试，写了就红。

### 7.3 两条实测澄清（别再被常见说法带偏）
- `m.createTable` 生成的是 `CREATE TABLE IF NOT EXISTS`（`migration.dart:317`），**本身幂等**。
  `createTableIfNotExists` 是语义统一与防御，不是"防崩"。
- **真正非幂等的只有两类**：`addColumn`（硬崩）与迁移块里的种子 `INSERT`（静默重复）。
  种子函数必须自带「表非空就早退」，否则重跑会让用户看到两份「新手减脂」。

### 7.4 事务：什么时候必须加
- **纯建表 / 加列 / 建索引**：不强制（半迁移只留空表，不产生错数据）。
- **任何含数据变换的迁移（backfill / 删列 / 改类型 / 拆表合并）：必须整段包
  `BEGIN` / `COMMIT`，失败 `ROLLBACK` 后原样上抛**，否则会留下错数据。

### 7.5 三条与事务相关的硬约束
1. **`onUpgrade` 里绝对不要调 drift 的 `transaction()`** —— 它会先 `ensureOpen()`，
   而此时 `ensureOpen` 正卡在迁移回调里 → **死锁，启动挂死**。只能用裸
   `customStatement('BEGIN')`。
2. 只能 `try / catch → ROLLBACK → rethrow`；**不能用 `finally` 无条件 ROLLBACK**
   （成功路径要 COMMIT）。
3. `PRAGMA foreign_keys` 不能在事务内改。`alterTable()` 内部会开关它 ——
   所以复杂迁移（改列类型 / 删列）必须在事务**外**做，否则静默失效。

补充：裸 `BEGIN`/`COMMIT` 里写 `PRAGMA user_version` 是可行的，因此加事务**不会**
与 drift 在 `onUpgrade` 之后写的版本号冲突。

### 7.6 迁移失败必须可诊断、可自救
- 失败时写 `MigrationFailureMarker`（**文件**，不是 DB 列 —— 迁移失败时数据库正是
  打不开的那个东西），与 `fittrack.sqlite` 同目录。
- `failingStep` 必须是**步骤级**（`index:idx_food_log_date`），不是表级。
- 启动期读 marker → 读 SQLite 文件头 offset 60 的 `user_version` 判定：
  等于当前版本 = 僵尸 marker（删掉正常启动）／落后 = 真失败（进降级页）／
  超前 = 数据来自更新版本（**绝不当僵尸删掉**）。
- 降级页只做文件 IO，**不许** watch 任何 DB provider。

### 7.7 每次改迁移的验收动作
1. `dart run build_runner build --delete-conflicting-outputs`（`.g.dart` 不入库）
2. `bash scripts/check.sh` 全绿
3. 两条路径都手测：**空库安装**（走 `onCreate`）+ **旧库升级**（走 `onUpgrade`）
