import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/exercise/domain/entities/exercise.dart';

/// 选择动作底部弹窗（带搜索）
///
/// 搜索语义：输入即查 `ExerciseRepository.search(query)`（本地 SQLite，name LIKE），
/// 空输入回落 getAll 全量。
///
/// 为什么**不做防抖、不做 loading 骨架**：这是本地数据库查询，一次 LIKE 在
/// 手机上是亚毫秒级；加防抖只会让"输入后列表迟一拍"，加骨架会让列表闪一下。
/// 输入框和列表各自异步，但用户感知到的应该是"边打边筛"。
class ExercisePickerSheet extends ConsumerStatefulWidget {
  final ValueChanged<ExerciseEntity> onPick;

  const ExercisePickerSheet({super.key, required this.onPick});

  @override
  ConsumerState<ExercisePickerSheet> createState() =>
      _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends ConsumerState<ExercisePickerSheet> {
  final _searchCtrl = TextEditingController();

  /// null = 首次加载中（只在这一种情况下显示转圈）
  List<ExerciseEntity>? _exercises;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load(String query) async {
    final repo = ref.read(exerciseRepoProvider);
    final trimmed = query.trim();
    final result =
        trimmed.isEmpty ? await repo.getAll() : await repo.search(trimmed);
    if (!mounted) return;
    setState(() => _exercises = result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final exercises = _exercises;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Text('选择动作', style: theme.textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: TextField(
              controller: _searchCtrl,
              autofocus: false,
              decoration: InputDecoration(
                isDense: true,
                hintText: '搜索动作名',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          _load('');
                        },
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onChanged: _load,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: exercises == null
                ? const Center(child: CircularProgressIndicator())
                : exercises.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            '没有叫这个的动作，可以回聊天页让嘎教练帮你建',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: AppColors.textTertiary),
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: exercises.length,
                        itemBuilder: (_, i) {
                          final ex = exercises[i];
                          // 分组标题：让用户点之前就知道这个动作要填什么
                          final showGroup = i == 0 ||
                              exercises[i - 1].category != ex.category;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (showGroup)
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 10, 16, 2),
                                  child: Text(
                                    categoryLabel(ex.category),
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textSecondary),
                                  ),
                                ),
                              ListTile(
                                dense: true,
                                title: Text(ex.name,
                                    style: theme.textTheme.bodyMedium),
                                subtitle: Text(ex.muscleGroup ?? '',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                        color: AppColors.textTertiary)),
                                trailing: const Icon(Icons.add_circle_outline,
                                    size: 20),
                                onTap: () => widget.onPick(ex),
                              ),
                            ],
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

/// 动作分类的中文标签（选择器分组标题用）
///
/// 用户点之前就该知道这个动作要填什么：按次数、按秒、还是按分钟。
String categoryLabel(String category) => switch (category) {
      'cardio' => '有氧（按时间）',
      'stretch' => '拉伸（按时间）',
      _ => '力量（按次数）',
    };
