# 简瘦 (FitTrack) — 项目定义文档

> **最后更新**：2025-07  
> **版本**：v2 架构规划  
> **本文档定位**：产品和技术的单一事实来源。所有后续开发决策对齐本文档。

---

## 一、产品身份

### 1.1 一句话定义

**帮助普通用户持续减脂、看到成果的训练记录工具。**

### 1.2 产品座右铭

> 训练是手段。减脂成果才是目的。

### 1.3 用户画像

| 维度 | 描述 |
|------|------|
| 年龄 | 18~45 岁 |
| 目标 | 持续减脂，非增肌、非力量举 |
| 训练方式 | 徒手、有氧、简单器械 |
| 技术水平 | 非专业健身者 |
| 核心焦虑 | 「我瘦了吗？」「什么时候能到目标体重？」「我的训练有没有用？」 |

### 1.4 用户每天打开 APP 应该得到什么

| 问题 | APP 必须回答 |
|------|-------------|
| 我瘦了吗？ | 本周体重变化（斤/周），明确方向 |
| 瘦了多少？ | 累计减重，从起始/上周到现在的变化 |
| 离目标还有多远？ | 剩余斤数 + 预计天数 |
| 我的训练有效吗？ | 训练频率与体重趋势的关联 |
| 什么时候能达到目标？ | 基于当前速度的倒计时 |
| 今天吃多了吗？ | 热量摄入 vs 消耗 |

### 1.5 产品定位红线

| 做 | 不做 |
|----|------|
| 减脂仪表盘 | 力量训练日志 |
| 体重趋势分析 | 1RM / PR 记录 |
| 热量缺口展示 | 训练容量分析 |
| 周报 / 里程碑 | 多天训练计划编排 |
| 身体围度变化 | 专业健美备赛功能 |
| 简单的训练记录 | 复杂的训练周期化 |

---

## 二、架构总纲

### 2.1 架构模式

**Clean Architecture + Feature-First 模块划分**

```
lib/
├── main.dart                     # 入口：初始化 DB + 通知
├── app.dart                      # MaterialApp.router 根组件
│
├── core/                         # 基础设施 —— 不包含业务逻辑
│   ├── database/
│   │   ├── database.dart         # Drift 表定义 + 迁移
│   │   ├── database.g.dart       # 生成代码
│   │   └── seed.dart             # 种子数据（独立文件）
│   ├── router/
│   │   └── app_router.dart       # GoRouter 路由表
│   ├── theme/
│   │   └── app_theme.dart        # Material3 主题
│   ├── services/                 # 无状态工具服务
│   │   ├── notification_service.dart
│   │   ├── countdown_controller.dart
│   │   └── workout_coach.dart
│   └── widgets/                  # 公共 UI 组件
│       ├── shimmer.dart
│       └── timer_card.dart
│
├── features/                     # 功能模块 —— 每个 feature 自包含
│   ├── dashboard/                # 减脂仪表盘（首页）
│   ├── weight_tracker/           # 体重 & 围度 & 趋势
│   ├── workout/                  # 训练记录 & 执行
│   ├── nutrition/                # 饮食日记 & 热量缺口
│   ├── goals/                    # 目标系统
│   ├── profile/                  # 用户身体信息 & 设置
│   └── analysis/                 # 周报 & 洞察
│
└── shared/                       # 跨 feature 共享
    ├── models/                   # 共享实体
    └── utils/                    # 格式化、计算工具
```

### 2.2 Feature 内部标准结构

```
feature_name/
├── data/
│   ├── feature_repository_impl.dart   # 数据源实现
│   └── mappers/                       # DB ↔ Entity 映射（仅需时）
├── domain/
│   ├── feature_entity.dart            # 领域实体（纯 Dart）
│   └── feature_repository.dart        # 仓储接口（抽象类）
└── presentation/
    ├── pages/                         # 完整页面
    │   ├── feature_page.dart
    │   └── feature_detail_page.dart
    ├── widgets/                       # 页面内组件
    │   └── feature_card.dart
    └── notifiers/                     # Riverpod Notifier（状态+逻辑）
        └── feature_notifier.dart
```

**目录纪律**：
- `usecases/` —— 删除。当前项目无独立用例层，逻辑入 Notifier。
- `mappers/` —— 仅在涉及复杂 DB-JOIN 映射时保留，简单映射入 RepositoryImpl。
- 空目录不允许提交。

### 2.3 设计原则（排序即优先级）

1. **减脂优先** — 任何功能上线前，问：「它帮助用户看到自己瘦了吗？」
2. **UI 薄，Notifier 厚** — Page 只负责布局，业务逻辑和状态在 Notifier 中
3. **不重复** — 训练执行逻辑（组管理、倒计时、语音）只在 **一处** 定义
4. **文件不超过 300 行** — 超过则拆分 widget / notifier / util
5. **无手动版本号刷新** — 禁用 `dataVersionProvider++` 模式，用 Riverpod 原生响应

---

## 三、数据架构

### 3.1 数据库表（现状 12 张表）

| 表名 | 职责 | 审计决策 |
|------|------|---------|
| `exercises` | 动作库（种子+自定义） | **保留** |
| `workouts` | 训练记录头 | **保留** |
| `workout_sets` | 训练每组详情 | **保留** |
| `body_metrics` | 体重+围度 | **保留，增加 neck_cm 字段** |
| `plans` | 训练计划头 | **降级**。保留但不再迭代，减脂用户不需要复杂计划 |
| `plan_days` | 计划按天拆分 | **降级**。同上 |
| `goals` | 目标定义+进度 | **保留并扩展**。增加 goal_category 字段支持更多目标类型 |
| `photos` | 身体照片 | **保留并增强**。增加对比标签 |
| `user_settings` | 用户身体信息+偏好 | **保留**。字段已足够 |
| `food_library` | 食物营养数据库 | **保留** |
| `food_log` | 饮食记录 | **保留** |
| `water_log` | 饮水记录 | **删除或加 UI**。当前只有 Repo 没有 UI，属于死代码 |

**迁移策略**：schema v9 → v10 做一次基线迁移，清理历史迁移链。

### 3.2 实体关系（核心路径）

```
UserSettings (1) ─────────── 身体信息（身高/年龄/性别）
     │
     ├──→ Goals (N) ──────── 目标（体重/频率/自定义）
     │
     ├──→ BodyMetrics (N) ── 体重+围度时间序列
     │      └──→ Photos (N)  身体照片
     │
     ├──→ FoodLog (N) ────── 饮食记录
     │      └──→ FoodLibrary 食物营养数据
     │
     └──→ Workouts (N) ───── 训练记录
            └──→ WorkoutSets (N)  每组详情
                   └──→ Exercises  动作定义
```

### 3.3 数据写入触发关系（自动联动）

```
体重录入 ──→ 自动更新体重类目标进度
          ──→ 触发首页数据刷新
          ──→ 触发体重变化通知（如已开启）

训练完成 ──→ 自动更新频率类目标进度（+1次）
          ──→ 触发日历数据刷新
          ──→ 保存上一次的输入值为动作默认值

饮食记录 ──→ 更新今日热量统计
          ──→ 与 TDEE 对比产生热量缺口

身体信息更新 ──→ 重新计算 BMI / BMR / TDEE
```

---

## 四、模块地图 & 价值分级

### 4.1 P0 模块 —— 减脂闭环（必须完善）

| 模块 | 当前状态 | 目标状态 |
|------|---------|---------|
| **Dashboard** | 训练导向的混合首页 | 减脂仪表盘：周变化、目标倒计时、热量缺口、周训练天数 |
| **Weight Tracker** | 完整的体重+围度+趋势 | 增加减脂速度指标、体重预测带、变化通知 |
| **Goals** | 简单的体重/频率进度条 | 增加目标倒计时、里程碑庆祝、多类型目标 |
| **Nutrition** | 有饮食记录无缺口 | 连接 TDEE，展示今日热量缺口。加入底部导航 |

### 4.2 P1 模块 —— 体验增强

| 模块 | 当前状态 | 目标状态 |
|------|---------|---------|
| **Workout** | 功能完整，代码冗余 | 统一训练执行层，消除重复。保留训练记录，PR页面降级 |
| **Analysis** | 无 | 新建。周报生成、月度对比、训练-体重关联图 |
| **Photos** | 存储+网格展示 | 增加前后对比模式（选取两张并排） |

### 4.3 P2 模块 —— 低频但保留

| 模块 | 当前状态 | 目标状态 |
|------|---------|---------|
| **Plan** | 完整的训练计划系统 | **冻结迭代**。维持现状，不删除（已有用户依赖） |
| **Profile** | 身体信息+设置 | 维持现状，微调入口 |
| **Water** | 只有 Repo 无 UI | **二选一**：加 UI 到首页卡片，或删除代码 |

### 4.4 P3 模块 —— 删除或深度降级

| 模块 | 决策 | 理由 |
|------|------|------|
| **PR 页面** | 降级为训练统计的子Tab | 力量举概念，减脂用户不关心 1RM |
| **训练容量趋势图** | 删除 | 减脂用户不关心容量 |
| **训练记录搜索栏** | 删除 | 低频，训练列表天然按时间倒序 |
| **励志标语** | 删除 | 随机无个性化，部分文案有负面暗示 |
| **语音教练** | 维持现状 | 已有用户可能使用，但不投入新功能 |
| **隐私锁** | 维持现状 | 有小众需求，代码量不大 |

---

## 五、导航架构

### 5.1 推荐底部导航（5 Tab → 调整）

```
当前:  [首页] [训练] [计划] [体重] [设置]

建议:  [首页] [体重] [饮食] [训练] [我的]
         │       │      │      │      │
      减脂仪表  体重   饮食   训练   设置+目标
      盘+周报  趋势+  日记+  列表+  +身体信息
              围度   缺口   执行   +导出
```

**变更理由**：
- 体重 Tab 前移——减脂用户每天第一件事是称重
- 饮食 Tab 加入导航——热量管理是减脂核心，不能藏在二级页面
- 计划 Tab 移除——降级为训练页的子入口
- 「我的」合并设置+目标+身体信息——减少 Tab 数量，增加信息密度

### 5.2 路由表（关键路径）

| 路由 | 页面 | 来源 |
|------|------|------|
| `/` | 减脂仪表盘 | Tab 0 |
| `/weight` | 体重趋势+围度+录入 | Tab 1 |
| `/nutrition` | 饮食日记+热量缺口 | Tab 2 |
| `/workout` | 训练列表 | Tab 3 |
| `/workout/active` | 训练执行（自由/计划统一） | 训练页 |
| `/profile` | 我的（设置+目标+身体信息） | Tab 4 |
| `/profile/goals` | 目标管理 | 我的 |
| `/profile/body-info` | 身体信息 | 我的 |
| `/analysis/weekly` | 周报 | 首页入口 |
| `/analysis/compare` | 月度对比 | 首页入口 |

---

## 六、状态管理架构

### 6.1 Riverpod 分层使用规范

```
层 1：数据层 Provider
  databaseProvider          → AppDatabase 单例
  xxxRepoProvider           → Repository 实现

层 2：异步数据 Provider（替代 FutureBuilder）
  weightHistoryProvider     → FutureProvider<List<BodyMetric>>
  todayNutritionProvider    → FutureProvider<DietDayData>
  userSettingsProvider      → FutureProvider<UserSettings?>

层 3：业务逻辑 Notifier（替代 Page 内 setState）
  workoutSessionProvider    → Notifier<WorkoutSessionState>
  dashboardProvider         → Notifier<DashboardState>

层 4：UI 消费
  Page 中仅使用 ref.watch() 消费，不含业务逻辑
```

### 6.2 禁止模式

```
❌ ref.read(xxxProvider.notifier).state++      // 手动版本号
❌ FutureBuilder + setState                    // 在 Page 中管理异步
❌ 两个 Page 包含相同训练执行逻辑              // 代码重复
```

### 6.3 核心状态节点设计

| Provider | 类型 | 持有数据 |
|----------|------|---------|
| `workoutSessionProvider` | `Notifier` | 当前训练的所有状态：动作列表、当前进度、倒计时、已完成组 |
| `dashboardProvider` | `Notifier` | 首页聚合数据：周体重变化、目标进度、今日热量、本周训练天数 |
| `weightHistoryProvider` | `FutureProvider` | 体重时间序列（自动响应新录入） |
| `nutritionTodayProvider` | `FutureProvider` | 今日饮食记录 + 热量缺口 |
| `goalProgressProvider` | `FutureProvider` | 所有活跃目标 + 进度 |

---

## 七、训练执行层统一方案

### 7.1 当前问题

`ActiveWorkoutPage`（自由训练）和 `PlanExecutePage`（计划训练）约 80% 代码重复：
- 组进度管理
- 训练/休息倒计时
- 语音教练
- 输入框预填
- 保存逻辑

### 7.2 统一方案

提取 **`WorkoutSessionNotifier`** 作为唯一训练状态管理者：

```
WorkoutSessionNotifier
├── 输入：SelectedExercise[]（统一模型）
│   └── 自由训练：从 QuickStartPage 组装
│   └── 计划训练：从 PlanDayEntity 转换
│
├── 状态：WorkoutSessionState
│   ├── exercises: List<ExerciseSlot>
│   ├── currentExerciseIndex: int
│   ├── currentSetIndex: int
│   ├── completedSets: List<NewSetData>
│   ├── restTimer: CountdownState
│   ├── trainingTimer: CountdownState
│   ├── isAutoMode: bool
│   └── isComplete: bool
│
├── 行为：
│   ├── completeSet()
│   ├── nextExercise()
│   ├── startRest()
│   ├── startTraining()
│   ├── stopAutoMode()
│   └── saveWorkout()
│
└── 输出：共用一个 WorkoutActivePage（统一 UI）
```

**两个入口路径**：
- 自由训练 `QuickStartPage` → 选择动作 → `WorkoutActivePage(sessionType: free)`
- 计划训练 `PlanDetailPage` → 选择天 → `WorkoutActivePage(sessionType: plan, planId: x)`

`WorkoutActivePage` 只负责 UI 布局——顶部进度条、动作信息、输入表单、倒计时卡片、底部按钮。所有逻辑委托给 `WorkoutSessionNotifier`。

---

## 八、开发路线图

### Phase 1：减脂聚焦（预计 2-3 周）

| 任务 | 优先级 | 描述 |
|------|--------|------|
| 首页重构 | P0 | 改为减脂仪表盘：周体重变化、目标倒计时、热量缺口卡片、本周训练天数 |
| 体重卡片升级 | P0 | 展示「本周-1.2斤」「减脂速度1.2斤/周」 |
| 目标前置 | P0 | 目标进度+倒计时从设置二级提升到首页核心区 |
| 饮食入口暴露 | P0 | 饮食加入底部导航或首页卡片 |
| 励志标语移除 | P3 | 删除 |
| 训练日历降级 | P1 | 缩小日历，标记称重日+训练日 |

### Phase 2：减脂闭环（预计 2-3 周）

| 任务 | 优先级 | 描述 |
|------|--------|------|
| 热量缺口展示 | P0 | 饮食记录 vs TDEE，可视化缺口 |
| 体重变化通知 | P0 | 本地定时推送今日体重变化 |
| 周报系统 | P1 | 每周一自动生成：减了多少、练了几天、饮食总结 |
| 里程碑系统 | P1 | 减重5/10/15斤触发庆祝动画 |
| 训练-体重关联视图 | P1 | 同一时间轴展示训练频率+体重趋势 |
| 照片对比 | P2 | 选取两张身体照片并排对比 |

### Phase 3：架构治理（预计 2-3 周）

| 任务 | 优先级 | 描述 |
|------|--------|------|
| 训练执行层统一 | P0 | 提取 WorkoutSessionNotifier，消除代码重复 |
| FutureBuilder → Riverpod | P0 | 全项目迁移，移除手动版本号 |
| 空目录清理 | P1 | 删除或实现 usecases/mappers/notifiers |
| 导航重构 | P1 | 5 Tab 调整，饮食入导航 |
| 饮水功能决策 | P2 | 加 UI 或删除 Repo+表 |
| 迁移基线化 | P2 | schema v9→v10 合并历史迁移 |

### Phase 4：增长与智能化（预计 3-4 周）

| 任务 | 优先级 | 描述 |
|------|--------|------|
| 月度对比快照 | P1 | 可分享的 before/after 卡片 |
| 饮食结构分析 | P1 | 蛋白质/碳水/脂肪饼图 |
| 智能建议 | P2 | 基于趋势的简单规则建议 |
| 自定义饮食目标 | P2 | 每日热量上限、三大营养素目标 |
| 商店素材 | P1 | 截图和描述对齐减脂定位 |

---

## 九、技术标准

### 9.1 文件大小限制

| 文件类型 | 上限 | 超限处理 |
|----------|------|---------|
| Page | 300 行 | 提取 widgets/ 子组件 |
| Notifier | 200 行 | 拆分逻辑到 domain services |
| RepositoryImpl | 150 行 | 提取 query builder |
| Entity | 80 行 | — |

### 9.2 命名规范

| 类型 | 模式 | 示例 |
|------|------|------|
| 页面文件 | `{feature}_page.dart` | `weight_trend_page.dart` |
| 详情页 | `{feature}_detail_page.dart` | `workout_detail_page.dart` |
| 组件 | `{feature}_{描述}_widget.dart` | `weight_card_widget.dart` |
| Notifier | `{feature}_notifier.dart` | `dashboard_notifier.dart` |
| Repository 接口 | `{feature}_repository.dart` | `weight_repository.dart` |
| Repository 实现 | `{feature}_repository_impl.dart` | `weight_repository_impl.dart` |
| Entity | `{feature}_entity.dart` | `body_metric_entity.dart` |

### 9.3 数据库变更流程

1. 在 `database.dart` 中修改表定义
2. 递增 `schemaVersion`
3. 在 `onUpgrade` 中添加迁移逻辑
4. 运行 `dart run build_runner build` 重新生成 `.g.dart`
5. **手动测试空库安装和从旧版本升级两种路径**

### 9.4 新 Feature 开发 check-list

- [ ] 在 `features/{name}/` 下创建标准三层目录
- [ ] 定义 Entity（纯 Dart，不依赖 Drift）
- [ ] 定义 Repository 接口（抽象类）
- [ ] 实现 RepositoryImpl（依赖 AppDatabase）
- [ ] 在 `core/providers.dart` 注册 Provider
- [ ] 创建 Page + Widgets
- [ ] 在 `app_router.dart` 注册路由
- [ ] 在导航结构中暴露入口
- [ ] 验证：新用户空状态、数据加载中、有数据、边界（删除最后一条）

---

## 十、关键决策记录

| 日期 | 决策 | 理由 |
|------|------|------|
| 2025-07 | 产品定位修正为「减脂管理」而非「训练记录」 | 审计发现定位漂移，首页和功能重心偏向训练 |
| 2025-07 | 训练计划系统冻结迭代 | 减脂用户训练简单重复，不需要多天计划编排 |
| 2025-07 | PR 页面降级 | 1RM 是力量举概念，减脂用户核心不关心 |
| 2025-07 | 饮食模块加入底部导航 | 热量管理是减脂闭环的关键一环，不能藏在二级 |
| 2025-07 | 训练执行层统一 | ActiveWorkoutPage 与 PlanExecutePage 80% 代码重复 |
| 2025-07 | FutureBuilder 全面迁移至 Riverpod | 手动版本号刷新模式脆弱，状态不一致 |
| 2025-07 | 饮水模块二选一 | 仅有 Repo 无 UI 是死代码，要么实现要么删除 |

---

> **本文档是简瘦 V2 的产品与技术宪法。所有 PR、Feature Request、重构决策必须对齐本文档。如有冲突，以本文档为准。**
