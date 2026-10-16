import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:fittrack/core/providers.dart';
import 'package:fittrack/features/settings/domain/entities/user_settings_entity.dart';
import 'package:fittrack/features/diet/domain/entities/diet_entity.dart';
import 'package:fittrack/features/diet/domain/repositories/diet_repository.dart';

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

              // 热量汇总卡片
              Card(
                color: theme.colorScheme.primaryContainer.withAlpha(120),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStat('已摄入', '${data.totalCal.toInt()}', 'kcal', theme, Icons.restaurant),
                      _buildStat('蛋白质', data.totalProtein.toStringAsFixed(1), 'g', theme, Icons.egg),
                      _buildStat('碳水', data.totalCarbs.toStringAsFixed(1), 'g', theme, Icons.grain),
                      _buildStat('脂肪', data.totalFat.toStringAsFixed(1), 'g', theme, Icons.water_drop),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ── 本周热量缺口趋势 ──
              _WeeklyDeficitChart(dietRepo: ref.watch(dietRepoProvider), userSettingsAsync: ref.watch(userSettingsProvider)),

              // ── 宏量营养饼图 ──
              if (data.totalCal > 0)
                _MacroPieChart(
                  protein: data.totalProtein,
                  carbs: data.totalCarbs,
                  fat: data.totalFat,
                ),

              const SizedBox(height: 16),

              // 加餐按钮
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _showAddFoodDialog(context, ref),
                  icon: const Icon(Icons.add),
                  label: const Text('添加食物'),
                ),
              ),
              const SizedBox(height: 16),

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

              // 食物列表
              if (data.filteredLogs.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text('还没有记录\n点击上方按钮添加食物',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
                    ),
                  ),
                )
              else
                ..._groupByMeal(data.filteredLogs).entries.map((entry) {
                  final logs = entry.value;
                  final mealCal = logs.fold(0.0, (sum, l) => sum + l.totalCalories);
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(FoodLogEntity.mealTypeLabels[entry.key] ?? entry.key,
                                style: theme.textTheme.titleSmall),
                              const Spacer(),
                              Text('${mealCal.toInt()} kcal',
                                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary)),
                            ],
                          ),
                          const Divider(),
                          ...logs.map((l) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              radius: 16,
                              backgroundColor: theme.colorScheme.secondaryContainer,
                              child: Text('${l.totalCalories.toInt()}',
                                style: TextStyle(fontSize: 10, color: theme.colorScheme.onSecondaryContainer)),
                            ),
                            title: Text(l.foodName ?? '食物#${l.foodId}',
                              style: theme.textTheme.bodyMedium),
                            subtitle: Text('${l.grams.toInt()}g',
                              style: theme.textTheme.bodySmall),
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
                }),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStat(String label, String value, String unit, ThemeData theme, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(height: 4),
        Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        Text(unit, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
        Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
      ],
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

/// 宏量营养饼图
class _MacroPieChart extends StatelessWidget {
  final double protein;
  final double carbs;
  final double fat;

  const _MacroPieChart({
    required this.protein,
    required this.carbs,
    required this.fat,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalG = protein + carbs + fat;
    if (totalG <= 0) return const SizedBox.shrink();

    final proteinPct = (protein / totalG * 100).toStringAsFixed(0);
    final carbsPct = (carbs / totalG * 100).toStringAsFixed(0);
    final fatPct = (fat / totalG * 100).toStringAsFixed(0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('宏量营养', style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 100,
                  height: 100,
                  child: PieChart(PieChartData(
                    sections: [
                      PieChartSectionData(value: protein, color: Colors.red.shade300, title: '', radius: 22),
                      PieChartSectionData(value: carbs, color: Colors.orange.shade300, title: '', radius: 22),
                      PieChartSectionData(value: fat, color: Colors.amber.shade300, title: '', radius: 22),
                    ],
                    sectionsSpace: 2,
                    centerSpaceRadius: 28,
                  )),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    children: [
                      _MacroLegend(color: Colors.red.shade300, label: '蛋白质', grams: '${protein.toStringAsFixed(0)}g', pct: '$proteinPct%'),
                      const SizedBox(height: 6),
                      _MacroLegend(color: Colors.orange.shade300, label: '碳水', grams: '${carbs.toStringAsFixed(0)}g', pct: '$carbsPct%'),
                      const SizedBox(height: 6),
                      _MacroLegend(color: Colors.amber.shade300, label: '脂肪', grams: '${fat.toStringAsFixed(0)}g', pct: '$fatPct%'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MacroLegend extends StatelessWidget {
  final Color color;
  final String label;
  final String grams;
  final String pct;

  const _MacroLegend({
    required this.color,
    required this.label,
    required this.grams,
    required this.pct,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 6),
        Expanded(child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
        Text(grams, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(width: 4),
        Text(pct, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline)),
      ],
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
