/// 抖音短链的**纯函数**判定（不发请求，便于单测）。
///
/// 为什么抖音要单独处理：
/// - `v.douyin.com/xxx` 会 302，桌面 UA 落到 `www.douyin.com/...`，拿到的是
///   **SPA 空壳**（实测 `/home` 只有 2.6KB、`<title>【抖音】记录美好生活</title>`、
///   没有 `og:description`）；
/// - 移动 UA 会落到 `www.iesdouyin.com/share/video/{id}/`，那是给微信卡片用的
///   分享页，**可能有** og 标题/简介 —— 所以先用移动 UA 换到分享页，再从 og 取。
///
/// 这里只做"是不是抖音 / 能不能拿到视频 id / 这个标题是不是纯站点名"三件事，
/// 真正的 http 编排在 `LocalPageFetcher` 里（保持这里零 IO，方便穷举用例）。
class DouyinResolver {
  DouyinResolver._();

  /// 抖音系域名（短链 / 主站 / 分享页）
  static const hosts = {
    'v.douyin.com',
    'www.douyin.com',
    'douyin.com',
    'www.iesdouyin.com',
    'iesdouyin.com',
  };

  /// 分享页模板（给微信卡片用的那一版，带 og:title / og:description）
  static String shareUrl(String videoId) =>
      'https://www.iesdouyin.com/share/video/$videoId/';

  static bool isDouyinHost(Uri uri) =>
      hosts.contains(uri.host.toLowerCase());

  /// 从 URL 里提视频 id：`/video/7300…`、`/share/video/7300…`、`?modal_id=7300…`
  ///
  /// 抖音 id 是 19 位数字（也兼容更短的纯数字，避免测试/老链接被误判）。
  static String? videoIdOf(Uri uri) {
    final path = uri.path;
    final byPath = RegExp(r'/(?:share/)?video/(\d{6,})').firstMatch(path);
    if (byPath != null) return byPath.group(1);
    final byQuery = uri.queryParameters['modal_id'];
    if (byQuery != null && RegExp(r'^\d{6,}$').hasMatch(byQuery)) {
      return byQuery;
    }
    return null;
  }

  /// 纯站点名（拿不到任何视频信息时的标题特征）
  ///
  /// 抖音桌面 UA 的落地页标题就是「【抖音】记录美好生活」这种 —— 它证明
  /// "请求成功"，但**不包含任何视频内容**，必须当成"读不到正文"。
  static const _genericTokens = [
    '抖音',
    '记录美好生活',
    '哔哩哔哩',
    'bilibili',
    '小红书',
    '快手',
    '微博',
    'weibo',
    'youtube',
    '知乎',
    '视频',
    '首页',
  ];

  /// 标题是否只是站点名（拿不到任何视频信息）
  ///
  /// 两条规则任一成立即判定为"泛标题"：
  /// ① 去掉站点名之后什么都不剩（「抖音」「【抖音】记录美好生活」「哔哩哔哩」）；
  /// ② 去掉站点名后只剩不到 6 个字（「抖音-记录美好生活」这类壳标题）。
  ///
  /// ⚠️ 不能用"标题总长度"来判断：真实内容标题经常很短
  /// （「10 分钟全身燃脂跟练 - 抖音」只有 12 字），只要**去掉站点名后还有内容**
  /// 就说明它带了视频信息。这条规则只认"除了站点名几乎什么都没剩"。
  static bool isGenericTitle(String title) {
    final stripped = _stripPunctuation(title).toLowerCase();
    if (stripped.isEmpty) return true;
    var rest = stripped;
    var hasToken = false;
    for (final token in _genericTokens) {
      final t = token.toLowerCase();
      if (stripped.contains(t)) hasToken = true;
      rest = rest.replaceAll(t, '');
    }
    if (rest.length < 2) return true;
    return hasToken && rest.length < 6;
  }

  static String _stripPunctuation(String s) => s
      .replaceAll(RegExp(r'[【】\[\]（）()<>《》\s\-_|·:：,，。.!！?？/]'), '')
      .trim();
}
