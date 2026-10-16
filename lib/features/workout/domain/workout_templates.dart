/// 训练模板 —— 推荐模板静态定义（v2）
///
/// 模板动作按名称匹配动作库种子数据；
/// 后续可将模板迁移到数据库以支持"我的模板"。
class WorkoutTemplate {
  final String id;
  final String name;
  final String difficulty; // 入门 / 中阶 / 高阶
  final String focus; // 全身 / 放松 / 碎片
  final int minutes;
  final String description;
  final String accentKey; // green / orange / red / cyan / purple（UI 层映射颜色）
  final List<TemplateExercise> exercises;

  const WorkoutTemplate({
    required this.id,
    required this.name,
    required this.difficulty,
    required this.focus,
    required this.minutes,
    required this.description,
    required this.accentKey,
    required this.exercises,
  });
}

class TemplateExercise {
  final String name; // 动作名（匹配动作库）
  final int sets;
  final int? reps; // 次数
  final int? durationSec; // 时长（秒）

  const TemplateExercise({
    required this.name,
    required this.sets,
    this.reps,
    this.durationSec,
  });
}

/// 推荐模板（按截图设计）
const List<WorkoutTemplate> recommendedTemplates = [
  WorkoutTemplate(
    id: 'starter',
    name: '新手减脂',
    difficulty: '入门',
    focus: '全身',
    minutes: 15,
    description: '低强度全身训练，适合刚开始减脂的用户',
    accentKey: 'green',
    exercises: [
      TemplateExercise(name: '深蹲', sets: 3, reps: 15),
      TemplateExercise(name: '俯卧撑', sets: 3, reps: 10),
      TemplateExercise(name: '平板支撑', sets: 3, durationSec: 30),
      TemplateExercise(name: '卷腹', sets: 3, reps: 12),
    ],
  ),
  WorkoutTemplate(
    id: 'fatburn',
    name: '燃脂训练',
    difficulty: '中阶',
    focus: '全身',
    minutes: 20,
    description: '中等强度全身燃脂，高效消耗热量',
    accentKey: 'orange',
    exercises: [
      TemplateExercise(name: '深蹲', sets: 4, reps: 15),
      TemplateExercise(name: '弓步蹲', sets: 3, reps: 12),
      TemplateExercise(name: '俯卧撑', sets: 3, reps: 12),
      TemplateExercise(name: '仰卧起坐', sets: 4, reps: 15),
    ],
  ),
  WorkoutTemplate(
    id: 'hiit',
    name: '高效HIIT',
    difficulty: '高阶',
    focus: '全身',
    minutes: 15,
    description: '高强度间歇训练，快速燃烧',
    accentKey: 'red',
    exercises: [
      TemplateExercise(name: '深蹲', sets: 4, reps: 20),
      TemplateExercise(name: '俯卧撑', sets: 3, reps: 15),
      TemplateExercise(name: '跳绳', sets: 3, durationSec: 60),
      TemplateExercise(name: '卷腹', sets: 3, reps: 20),
    ],
  ),
  WorkoutTemplate(
    id: 'office',
    name: '办公室运动',
    difficulty: '入门',
    focus: '碎片',
    minutes: 10,
    description: '无需器械，10 分钟碎片化训练',
    accentKey: 'cyan',
    exercises: [
      TemplateExercise(name: '深蹲', sets: 2, reps: 15),
      TemplateExercise(name: '俯卧撑', sets: 2, reps: 10),
      TemplateExercise(name: '平板支撑', sets: 2, durationSec: 30),
      TemplateExercise(name: '肩背拉伸', sets: 2, durationSec: 60),
    ],
  ),
  WorkoutTemplate(
    id: 'presleep',
    name: '睡前拉伸',
    difficulty: '入门',
    focus: '放松',
    minutes: 10,
    description: '放松全身肌肉，改善睡眠质量',
    accentKey: 'purple',
    exercises: [
      TemplateExercise(name: '全身拉伸', sets: 2, durationSec: 60),
      TemplateExercise(name: '腿部拉伸', sets: 3, durationSec: 60),
      TemplateExercise(name: '肩背拉伸', sets: 2, durationSec: 60),
    ],
  ),
];
