/// 一个 AI 服务商（OpenAI 兼容 /chat/completions 接口）
class AiProvider {
  final String id;
  final String name;

  /// 完整 base（不含 /chat/completions），如 `https://api.moonshot.cn/v1`
  final String baseUrl;

  /// 默认模型名
  final String defaultModel;

  /// Key 提示（如「sk- 开头」）
  final String keyHint;

  /// 申请 Key 的网址（展示用）
  final String keyUrl;

  /// 是否支持 DeepSeek 的 `thinking` 请求字段（其它家是标准 OpenAI 兼容，不认这个字段）
  final bool supportsThinking;

  const AiProvider({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.defaultModel,
    required this.keyHint,
    required this.keyUrl,
    this.supportsThinking = false,
  });
}

/// 中国常用 AI 服务商（OpenAI 兼容接口）
const List<AiProvider> aiProviders = [
  AiProvider(
    id: 'deepseek',
    name: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com',
    defaultModel: 'deepseek-flash',
    keyHint: 'sk- 开头',
    keyUrl: 'platform.deepseek.com',
    supportsThinking: true,
  ),
  AiProvider(
    id: 'moonshot',
    name: 'Kimi（月之暗面）',
    baseUrl: 'https://api.moonshot.cn/v1',
    defaultModel: 'kimi-k2-0711-preview',
    keyHint: 'sk- 开头',
    keyUrl: 'platform.moonshot.cn',
  ),
  AiProvider(
    id: 'qwen',
    name: '通义千问（阿里）',
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    defaultModel: 'qwen-plus',
    keyHint: 'sk- 开头',
    keyUrl: 'bailian.console.aliyun.com',
  ),
  AiProvider(
    id: 'glm',
    name: '智谱 GLM',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    defaultModel: 'glm-4-flash',
    keyHint: 'id.secret 格式',
    keyUrl: 'open.bigmodel.cn',
  ),
  AiProvider(
    id: 'doubao',
    name: '豆包（火山方舟）',
    baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
    defaultModel: 'doubao-1-5-pro-32k-250115',
    keyHint: 'API Key 或 ARK API Key',
    keyUrl: 'console.volcengine.com/ark',
  ),
  AiProvider(
    id: 'ernie',
    name: '文心一言（百度）',
    baseUrl: 'https://qianfan.baidubce.com/v2',
    defaultModel: 'ernie-4.0-8k',
    keyHint: 'API Key（Bearer）',
    keyUrl: 'console.bce.baidu.com/qianfan',
  ),
  AiProvider(
    id: 'spark',
    name: '讯飞星火',
    baseUrl: 'https://spark-api-open.xf-yun.com/v1',
    defaultModel: 'generalv3.5',
    keyHint: 'APIKey:APISecret 格式（冒号拼接）',
    keyUrl: 'console.xfyun.cn',
  ),
  AiProvider(
    id: 'hunyuan',
    name: '腾讯混元',
    baseUrl: 'https://api.hunyuan.cloud.tencent.com/v1',
    defaultModel: 'hunyuan-turbo',
    keyHint: 'sk- 开头',
    keyUrl: 'console.cloud.tencent.com/hunyuan',
  ),
  AiProvider(
    id: 'minimax',
    name: 'MiniMax',
    baseUrl: 'https://api.minimax.chat/v1',
    defaultModel: 'MiniMax-Text-01',
    keyHint: 'API Key（Bearer）',
    keyUrl: 'platform.minimaxi.com',
  ),
];

/// 按 id 找服务商；找不到回落到 DeepSeek（保证不崩）
AiProvider aiProviderById(String? id) => aiProviders.firstWhere(
      (p) => p.id == id,
      orElse: () => aiProviders.first,
    );
