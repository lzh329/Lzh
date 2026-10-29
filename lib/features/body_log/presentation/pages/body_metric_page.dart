import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/body_log/domain/entities/body_metric_entity.dart';
import 'package:fittrack/features/body_log/domain/weight_bucket.dart';
import 'package:fittrack/features/body_log/presentation/widgets/add_metric_form.dart';
import 'package:fittrack/features/body_log/presentation/widgets/body_history_list.dart';
import 'package:fittrack/features/body_log/presentation/widgets/weight_bar_chart.dart';
import 'package:fittrack/features/body_log/presentation/widgets/weight_highlight_card.dart';

/// 体重页数据（时间范围是 family 参数）
///
/// 遵循「异步状态一律 Riverpod」：新写的图表与指标卡都从 provider 取数，
/// 不再在 build 里 `FutureBuilder`。
///
/// ⚠️ 遗留技术债：录入表单内部仍用 setState，保存后靠 `onSaved` invalidate
/// 触发刷新（见 add_metric_form.dart 文件头），本轮只做搬运。
final bodyPageDataProvider =
    FutureProvider.family<BodyPageData, String>((ref, rangeKey) async {
  final now = DateTime.now();
  final range = WeightRange.fromKey(rangeKey);
  final days = range.days;
  final from =
      days == null ? DateTime(2020) : now.subtract(Duration(days: days));

  final metrics =
      await ref.watch(bodyMetricRepoProvider).getAll(from: from, to: now);
  final photos = await ref.watch(photoRepoProvider).getAll();
  return BodyPageData(metrics: metrics, photoCount: photos.length);
});

class BodyMetricPage extends ConsumerStatefulWidget {
  const BodyMetricPage({super.key});

  @override
  ConsumerState<BodyMetricPage> createState() => _BodyMetricPageState();
}

class _BodyMetricPageState extends ConsumerState<BodyMetricPage> {
  String _timeRange = 'month';

  static const _metricLabels = {
    'weight': '体重',
    'waist': '腰围',
    'hip': '臀围',
    'chest': '胸围',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dataAsync = ref.watch(bodyPageDataProvider(_timeRange));
    final metrics =
        dataAsync.valueOrNull?.metrics ?? const <BodyMetricEntity>[];
    final settings = ref.watch(userSettingsProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('体重数据')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(bodyPageDataProvider(_timeRange));
          await ref.read(bodyPageDataProvider(_timeRange).future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (dataAsync.isLoading && metrics.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              // ① 关键指标高亮卡
              if (metrics.isNotEmpty) ...[
                WeightHighlightCard(metrics: metrics, settings: settings),
                const SizedBox(height: 18),
              ],

              // ② 分组柱状统计（期平均 / 期最低 / 目标基准线）
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('体重统计', style: theme.textTheme.titleSmall),
                          const Spacer(),
                          _rangeButton(),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        children: [
                          for (final e in _metricLabels.entries)
                            Chip(
                              label: Text(e.value,
                                  style: const TextStyle(fontSize: 11)),
                              visualDensity: VisualDensity.compact,
                              backgroundColor: e.key == 'weight'
                                  ? AppColors.primary.withAlpha(24)
                                  : null,
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      WeightBarChart(
                        buckets: bucketWeightSeries(
                          metrics,
                          range: WeightRange.fromKey(_timeRange),
                        ),
                        targetKg: settings?.targetWeightKg,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // ③ 录入表单
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: AddMetricForm(
                    bodyRepo: ref.read(bodyMetricRepoProvider),
                    photoRepo: ref.read(photoRepoProvider),
                    goalRepo: ref.read(goalRepoProvider),
                    onSaved: () =>
                        ref.invalidate(bodyPageDataProvider(_timeRange)),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // ④ 历史记录（最多 10 条）
              if (metrics.isNotEmpty) ...[
                Text('历史记录', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                ...metrics.reversed.take(10).map(
                      (m) => BodyHistoryRow(
                        metric: m,
                        onDelete: () async {
                          await ref.read(bodyMetricRepoProvider).delete(m.id);
                          ref.invalidate(bodyPageDataProvider(_timeRange));
                        },
                      ),
                    ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _rangeButton() {
    const labels = {'week': '周', 'month': '月', 'quarter': '季', 'all': '全部'};
    return DropdownButton<String>(
      value: _timeRange,
      underline: const SizedBox.shrink(),
      isDense: true,
      style: const TextStyle(fontSize: 12, color: AppColors.primaryText),
      items: [
        for (final e in labels.entries)
          DropdownMenuItem(value: e.key, child: Text(e.value)),
      ],
      onChanged: (v) {
        if (v != null) setState(() => _timeRange = v);
      },
    );
  }
}
