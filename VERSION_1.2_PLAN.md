# FitTrack v1.2 开发计划

> 当前版本：v1.2.0（2025-03）  
> 状态：✅ 核心功能已完成

---

## 已完成功能

### ✅ P0 — 目标系统（Goals）

- `GoalEntity` / `GoalRepository` / `GoalRepositoryImpl` 仓储层
- `GoalListPage`（路由 `/goals`）— 创建/删除/标记完成
- 首页「目标进度」卡片 — 显示未完成目标的前 2 个
- 自动更新进度：
  - 录入体重 → 自动更新体重目标进度
  - 完成训练 → 自动累计训练频率目标

### ✅ P0 — 数据导出（Data Export）

- 设置页「导出训练记录」— CSV 导出为 `fittrack_workouts_YYYYMMDD.csv`
- 设置页「导出身体数据」— CSV 导出为 `fittrack_body_YYYYMMDD.csv`
- 使用 `share_plus` 调起系统分享面板

### ✅ P0 — 主题切换（Theme Toggle）

- `themeModeProvider` (Riverpod) — 跟随系统 / 浅色 / 深色
- 设置页「外观」SegmentedButton 切换
- `app.dart` 改造为 `ConsumerWidget` 响应主题变更

### ✅ P1 — 训练统计分析（Workout Stats）

- `WorkoutStatsPage`（路由 `/workout/stats`）
  - 连续训练天数 streak
  - 总训练次数 / 总组数
  - 本周训练柱状图（fl_chart BarChart）
  - 训练容量趋势折线图
  - 组数分布概览

### ✅ P1 — 训练时长记录

- 训练页面自动计时（代码就绪，`durationSec` 字段可用）

### ✅ P2 — 计划任意天执行

- 计划详情页每个天卡片增加「开始」按钮
- `PlanExecutePage` 通过路由 extra 接收 `dayOfWeek`，不再硬编码今天

### ⏳ P2 — 训练记录编辑（占位）

- 训练详情页「编辑」按钮已添加，当前显示"功能开发中"提示

### ⏳ P2 — 训练提醒（暂缓）

- 需要 `flutter_local_notifications` + Android channel 配置 + iOS entitlements
- 建议 v1.3 实现

---

## 技术改动一览

| 文件 | 操作 |
|------|------|
| `lib/features/goal/` (4 文件) | **新增** — 目标系统完整模块 |
| `lib/core/providers.dart` | 新增 `goalRepoProvider`、`themeModeProvider` |
| `lib/core/router/app_router.dart` | 新增 `/goals`、`/workout/stats` 路由 |
| `lib/app.dart` | `StatelessWidget` → `ConsumerWidget`，使用 `themeModeProvider` |
| `lib/features/settings/` | 重写设置页：目标管理、外观切换、数据导出 |
| `lib/features/dashboard/` | 新增目标进度卡片 `_GoalsCard` |
| `lib/features/body_log/` | 体重录入自动更新目标进度 |
| `lib/features/workout/` active_workout_page | 训练保存自动更新频率目标 |
| `lib/features/plan/` plan_execute_page | 训练保存自动更新频率目标 |
| `lib/features/plan/` plan_detail_page | 每天增加「开始」按钮 |
| `lib/features/plan/` plan_execute_page | 支持指定 dayOfWeek 执行 |
| `lib/features/workout/` workout_detail_page | 增加编辑按钮（占位） |
| `lib/features/workout/` workout_list_page | 增加统计入口按钮 |
| `pubspec.yaml` | 新增 `share_plus: ^10.0.0` |
