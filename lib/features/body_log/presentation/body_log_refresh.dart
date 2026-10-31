import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fittrack/core/providers.dart';
import 'package:fittrack/features/trends/presentation/trends_providers.dart';

/// 体重 / 围度 / 身体照片写入后的统一刷新入口。
///
/// 为什么需要它：首页「今日打卡」([dashboardDataProvider])、趋势页
/// ([trendsDataProvider])、目标进度 ([goalListProvider]) 各自缓存了一份
/// 聚合数据（都是非 autoDispose 的 FutureProvider，创建后一直存活）。
/// 写入方只 invalidate 自己页面的 provider，就会留下
/// 「库里已经存了、首页还是旧数据、打卡块不变橙」的幽灵 bug。
///
/// 约定：任何新增/修改/删除身体数据的入口，保存成功后都调这里，
/// 不要只刷当前页。
void refreshBodyDependents(WidgetRef ref) {
  ref.invalidate(dashboardDataProvider);
  ref.invalidate(trendsDataProvider);
  ref.invalidate(goalListProvider);
}
