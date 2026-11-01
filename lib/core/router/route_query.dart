import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// 读当前路由的 query 参数（没有路由时返回 null）。
///
/// 为什么不用 `GoRouterState.of`：它会直接抛
/// "There is no GoRouterState above the current context"。而页面在
/// widget test 与独立预览里都是脱离 GoRouter 树直接 pump 的 ——
/// 让页面为了一个可选参数在测试里崩溃，等于把"页面能不能单独渲染"这个能力弄丢。
///
/// 只用于**可选**的 UI 参数（`?focus=weight` / `?add=1`），不用于业务路由参数。
String? routeQueryParam(BuildContext context, String key) {
  try {
    return GoRouterState.of(context).uri.queryParameters[key];
  } catch (_) {
    return null;
  }
}
