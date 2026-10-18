import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/features/settings/domain/entities/user_settings_entity.dart';
import 'package:fittrack/features/diet/domain/entities/diet_entity.dart';
import 'package:fittrack/features/diet/domain/repositories/diet_repository.dart';

const _orange = Color(0xFFFF7043);
const _amber = Color(0xFFFFC53D);
const _green = Color(0xFFFF8A00);
const _purple = Color(0xFFC084FC);
const _blue = Color(0xFF38BDF8);

class DietPage extends ConsumerStatefulWidget {
  const DietPage({super.key});

  @override
  ConsumerState<DietPage> createState() => _DietPageState();
}

class _DietPageState extends ConsumerState<DietPage> {
  DateTime _selectedDate = DateTime.now();
  String _mealFilter = 'all';

  @override
  Widget build(BuildContext context) {
    final dietRepo = ref.watch(dietRepoProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('饮食日记'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: () async {
              final date = await showDatePicker(
                context: context,
                initialDate: _selectedDate,
                firstDate: DateTime(2024),
                lastDate: DateTime.now(),
                locale: const Locale('zh'),
              );
              if (date != null) setState(() => _selectedDate = date);
            },
          ),
        ],
      ),
      body: FutureBuilder<_DietDayData>(
        future: _loadDay(dietRepo, _selectedDate),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data ?? const _DietDayData();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 日期切换
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => setState(() => _selectedDate = _selectedDate.subtract(const Duration(days: 1))),
                  ),
                  Text(
                    DateFormat('M月d日 EEEE', 'zh_CN').format(_selectedDate),
                    style: theme.textTheme.titleMedium,
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: _selectedDate.day == DateTime.now().day
                      ? null
                      : () => setState(() => _selectedDate = _selectedDate.add(const Duration(days: 1))),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 热量总卡
              _CalorieSummaryCard(
                totalCal: data.totalCal,
                protein: data.totalProtein,
                carbs: data.totalCarbs,
                fat: data.totalFat,
                targetCal:
                    ref.watch(userSettingsProvider).valueOrNull?.dailyCalorieTarget,
              ),
              const SizedBox(height: 12),

              // ── 本周热量缺口趋势 ──
              _WeeklyDeficitChart(dietRepo: ref.watch(dietRepoProvider), userSettingsAsync: ref.watch(userSettingsProvider)),

              const SizedBox(height: 16),

              // 添加食物（橙色主按钮）
              SizedBox(
                height: 46,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _orange,
                    foregroundColor: Colors.black87,
                  ),
                  onPressed: () => _showAddFoodDialog(context, ref),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('添加食物',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 18),

              // 餐次筛选
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _mealChip('全部', 'all'),
                    ...FoodLogEntity.mealTypeLabels.entries.map((e) => _mealChip(e.value, e.key)),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // 三餐卡片（未记录的餐次显示虚框引导）
              ..._buildMealCards(context, data, dietRepo),
            ],
          );
        },
      ),
    );
  }

  Widget _mealChip(String label, String value) {
    final selected = _mealFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected,
        onSelected: (_) => setState(() => _mealFilter = value),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Map<String, List<FoodLogEntity>> _groupByMeal(List<FoodLogEntity> logs) {
    final map = <String, List<FoodLogEntity>>{};
    for (final l in logs) {
      map.putIfAbsent(l.mealType, () => []).add(l);
    }
    return map;
  }

  /// 三餐卡片：有记录的显示明细，未记录的显示虚框引导
  List<Widget> _buildMealCards(
    BuildContext context,
    _DietDayData data,
    DietRepository dietRepo,
  ) {
    final theme = Theme.of(context);
    final groups = _groupByMeal(data.filteredLogs);
    final meals = _mealFilter == 'all'
        ? FoodLogEntity.mealTypeLabels.keys.toList()
        : [_mealFilter];

    return meals.map((meal) {
      final logs = groups[meal];
      final label = FoodLogEntity.mealTypeLabels[meal] ?? meal;
      final color = _mealColor(meal);
      final icon = _mealIcon(meal);

      // 未记录 → 虚线引导卡
      if (logs == null || logs.isEmpty) {
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            onTap: () => _showAddFoodDialog(context, ref),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: Colors.white.withAlpha(26), width: 0.8),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: color.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 16, color: color.withAlpha(150)),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '$label · 待记录',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                  const Spacer(),
                  Text(
                    '＋ 添加',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: color),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      final mealCal =
          logs.fold(0.0, (sum, l) => sum + l.totalCalories);
      return Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 6),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: color.withAlpha(32),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 16, color: color),
                  ),
                  const SizedBox(width: 10),
                  Text(label,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text(
                    '${mealCal.toInt()} kcal',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: color),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              const SizedBox(height: 6),
              ...logs.map((l) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: color.withAlpha(18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${l.totalCalories.toInt()}',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: color),
                      ),
                    ),
                    title: Text(l.foodName ?? '食物#${l.foodId}',
                        style: theme.textTheme.bodyMedium),
                    subtitle: Text('${l.grams.toInt()} g',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      onPressed: () async {
                        await dietRepo.deleteLog(l.id);
                        setState(() {});
                      },
                    ),
                  )),
            ],
          ),
        ),
      );
    }).toList();
  }

  Color _mealColor(String meal) => switch (meal) {
        'breakfast' => _amber,
        'lunch' => _green,
        'dinner' => _purple,
        _ => _blue,
      };

  IconData _mealIcon(String meal) => switch (meal) {
        'breakfast' => Icons.wb_twilight,
        'lunch' => Icons.lunch_dining,
        'dinner' => Icons.dinner_dining,
        _ => Icons.cookie_outlined,
      };

  Future<_DietDayData> _loadDay(DietRepository repo, DateTime date) async {
    final logs = await repo.getLogsByDate(date);
    double cal = 0, protein = 0, fat = 0, carbs = 0;
    for (final l in logs) {
      cal += l.totalCalories;
    }
    // Get full food data for macro calculation
    for (final l in logs) {
      final food = await repo.getFoodById(l.foodId);
      if (food != null) {
        protein += (food.proteinPer100g ?? 0) * l.grams / 100;
        fat += (food.fatPer100g ?? 0) * l.grams / 100;
        carbs += (food.carbsPer100g ?? 0) * l.grams / 100;
      }
    }
    return _DietDayData(
      totalCal: cal,
      totalProtein: protein,
      totalFat: fat,
      totalCarbs: carbs,
      allLogs: logs,
      filteredLogs: _mealFilter == 'all' ? logs : logs.where((l) => l.mealType == _mealFilter).toList(),
    );
  }

  void _showAddFoodDialog(BuildContext context, WidgetRef ref) {
    final searchCtrl = TextEditingController();
    String mealType = 'lunch';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.85,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (ctx, scrollCtrl) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Center(
                        child: Container(
                          width: 40, height: 4,
                          decoration: BoxDecoration(
                            color: Theme.of(ctx).colorScheme.outline.withAlpha(80),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('添加食物', style: Theme.of(ctx).textTheme.titleMedium),
                      const SizedBox(height: 12),

                      // 搜索
                      TextField(
                        controller: searchCtrl,
                        decoration: const InputDecoration(
                          hintText: '搜索食物...',
                          prefixIcon: Icon(Icons.search),
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setSheetState(() {}),
                      ),
                      const SizedBox(height: 8),

                      // 餐次选择
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: FoodLogEntity.mealTypeLabels.entries.map((e) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(e.value, style: const TextStyle(fontSize: 12)),
                                selected: mealType == e.key,
                                onSelected: (_) => setSheetState(() => mealType = e.key),
                                visualDensity: VisualDensity.compact,
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // 食物列表
                      Expanded(
                        child: FutureBuilder<List<FoodLibraryEntity>>(
                          future: ref.read(dietRepoProvider).searchFoods(
                            query: searchCtrl.text.isEmpty ? null : searchCtrl.text,
                          ),
                          builder: (_, snap) {
                            final foods = snap.data ?? [];
                            final categories = <String, List<FoodLibraryEntity>>{};
                            for (final f in foods) {
                              categories.putIfAbsent(f.category, () => []).add(f);
                            }

                            return ListView(
                              controller: scrollCtrl,
                              children: categories.entries.expand((entry) {
                                return [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                    child: Text(
                                      FoodLibraryEntity.categoryLabels[entry.key] ?? entry.key,
                                      style: Theme.of(ctx).textTheme.labelSmall?.copyWith(
                                        color: Theme.of(ctx).colorScheme.primary),
                                    ),
                                  ),
                                  ...entry.value.map((food) => ListTile(
                                    dense: true,
                                    leading: CircleAvatar(
                                      radius: 16,
                                      backgroundColor: Theme.of(ctx).colorScheme.secondaryContainer,
                                      child: Text('${food.caloriesPer100g.toInt()}',
                                        style: TextStyle(fontSize: 10,
                                          color: Theme.of(ctx).colorScheme.onSecondaryContainer)),
                                    ),
                                    title: Text(food.name, style: Theme.of(ctx).textTheme.bodyMedium),
                                    subtitle: Text('${food.caloriesPer100g.toInt()} kcal/100g${food.proteinPer100g != null ? ' · 蛋白${food.proteinPer100g!.toStringAsFixed(1)}g' : ''}',
                                      style: Theme.of(ctx).textTheme.bodySmall),
                                    onTap: () {
                                      // 选食物 → 输入克数
                                      Navigator.pop(ctx);
                                      _showGramsInput(context, ref, food, mealType);
                                    },
                                  )),
                                ];
                              }).toList(),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _showGramsInput(BuildContext context, WidgetRef ref, FoodLibraryEntity food, String mealType) {
    final gramsCtrl = TextEditingController(text: '100');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(food.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${food.caloriesPer100g.toInt()} kcal / 100g',
              style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 12),
            TextField(
              controller: gramsCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '克数', suffixText: 'g',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text('≈ ${(food.caloriesPer100g * (double.tryParse(gramsCtrl.text) ?? 100) / 100).toInt()} kcal',
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                color: Theme.of(ctx).colorScheme.primary)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              final grams = double.tryParse(gramsCtrl.text);
              if (grams == null || grams <= 0) return;
              await ref.read(dietRepoProvider).addLog(
                date: _selectedDate,
                foodId: food.id,
                grams: grams,
                mealType: mealType,
              );
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (mounted) setState(() {});
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }
}

/// 热量总卡（v2）：大字摄入 + 进度 + 三大营养素
class _CalorieSummaryCard extends StatelessWidget {
  final double totalCal;
  final double protein;
  final double carbs;
  final double fat;
  final int? targetCal;

  const _CalorieSummaryCard({
    required this.totalCal,
    required this.protein,
    required this.carbs,
    required this.fat,
    this.targetCal,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final target = targetCal;
    final hasTarget = target != null && target > 0;
    final progress = hasTarget ? (totalCal / target).clamp(0.0, 1.0) : null;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: _orange.withAlpha(32),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child:
                      const Icon(Icons.restaurant, size: 16, color: _orange),
                ),
                const SizedBox(width: 10),
                Text('今日摄入', style: theme.textTheme.titleSmall),
                const Spacer(),
                if (hasTarget)
                  Text(
                    '${(progress! * 100).round()}%',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _orange),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '${totalCal.toInt()}',
                  style: const TextStyle(
                      fontSize: 30, fontWeight: FontWeight.w700, height: 1.0),
                ),
                const SizedBox(width: 5),
                Text(
                  hasTarget ? '/ $target kcal' : 'kcal',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ],
            ),
            if (hasTarget) ...[
              const SizedBox(height: 11),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 5,
                  backgroundColor: Colors.white.withAlpha(16),
                  color: totalCal > target ? Colors.red : _orange,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                _Nutrient(label: '蛋白', value: protein, color: _green),
                _Nutrient(label: '碳水', value: carbs, color: _amber),
                _Nutrient(label: '脂肪', value: fat, color: _orange),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Nutrient extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const _Nutrient({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline, fontSize: 11),
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value.toStringAsFixed(0),
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: color),
              ),
              Text(
                'g',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 本周热量缺口迷你柱状图
class _WeeklyDeficitChart extends StatelessWidget {
  final dynamic dietRepo;
  final AsyncValue<UserSettingsEntity?> userSettingsAsync;

  const _WeeklyDeficitChart({required this.dietRepo, required this.userSettingsAsync});

  @override
  Widget build(BuildContext context) {
    final us = userSettingsAsync.valueOrNull;
    final tdee = us?.tdee();
    if (tdee == null) return const SizedBox.shrink();

    return FutureBuilder<List<_DayDeficit>>(
      future: _loadWeek(dietRepo, tdee),
      builder: (context, snapshot) {
        final data = snapshot.data ?? [];
        if (data.isEmpty) return const SizedBox.shrink();

        final theme = Theme.of(context);
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('本周热量缺口', style: theme.textTheme.titleSmall),
                const SizedBox(height: 12),
                SizedBox(
                  height: 120,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: data.map((d) {
                      final maxDef = data.map((x) => x.deficit.abs()).reduce((a, b) => a > b ? a : b).clamp(100, double.infinity);
                      final height = (d.deficit.abs() / maxDef * 80).clamp(8.0, 80.0);
                      final isDeficit = d.deficit > 0;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text('${d.deficit.abs().toInt()}', style: TextStyle(fontSize: 9, color: isDeficit ? Colors.green : Colors.red)),
                              const SizedBox(height: 2),
                              Container(
                                height: height,
                                decoration: BoxDecoration(
                                  color: (isDeficit ? Colors.green : Colors.red).withAlpha(isDeficit ? 180 : 150),
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(d.label, style: TextStyle(fontSize: 9, color: theme.colorScheme.outline)),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<List<_DayDeficit>> _loadWeek(dietRepo, double tdee) async {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    const labels = ['一', '二', '三', '四', '五', '六', '日'];
    final result = <_DayDeficit>[];
    for (int i = 0; i < 7; i++) {
      final day = monday.add(Duration(days: i));
      if (day.isAfter(now)) break;
      final cal = await dietRepo.getDailyCalories(day);
      result.add(_DayDeficit(label: labels[i], deficit: tdee - cal));
    }
    return result;
  }
}

class _DayDeficit {
  final String label;
  final double deficit;
  const _DayDeficit({required this.label, required this.deficit});
}

class _DietDayData {
  final double totalCal;
  final double totalProtein;
  final double totalFat;
  final double totalCarbs;
  final List<FoodLogEntity> allLogs;
  final List<FoodLogEntity> filteredLogs;

  const _DietDayData({
    this.totalCal = 0,
    this.totalProtein = 0,
    this.totalFat = 0,
    this.totalCarbs = 0,
    this.allLogs = const [],
    this.filteredLogs = const [],
  });
}
