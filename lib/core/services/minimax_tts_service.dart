import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// 云端 TTS（MiniMax T2A v2）调用失败。`message` 面向用户，可直接播报/显示。
class MinimaxTtsException implements Exception {
  final String message;

  const MinimaxTtsException(this.message);

  @override
  String toString() => 'MinimaxTtsException: $message';
}

/// MiniMax 语音合成（T2A v2）。
///
/// 接口要点（已核实）：
/// - `POST {baseUrl}/v1/t2a_v2?GroupId={groupId}`，`Authorization: Bearer {key}`；
/// - 响应 `{"data":{"audio":"<hex>"},"base_resp":{"status_code":0,"status_msg":"…"}}`；
/// - **`data.audio` 是十六进制字符串**，每 2 个字符 1 字节，解码后才是 MP3；
/// - 业务错误看 `base_resp.status_code`（非 0 即失败，HTTP 可能还是 200）。
class MinimaxTtsService {
  MinimaxTtsService._();

  /// 国内站；国际站是 `https://api.minimax.io`
  static const defaultBaseUrl = 'https://api.minimax.chat';

  /// 用 hd 模型：训练播报就那几十句固定短语，音质优先级高于成本
  static const model = 'speech-02-hd';

  static const requestTimeout = Duration(seconds: 20);

  /// 合成为 MP3 字节。失败抛 [MinimaxTtsException]（文案给用户看）
  static Future<Uint8List> synthesize({
    required String text,
    required String apiKey,
    String? groupId,
    required String voiceId,
    double speed = 1.0,
    int pitch = 0,
    String baseUrl = defaultBaseUrl,
    http.Client? client,
  }) async {
    final trimmed = text.trim();
    // 空文本直接拒绝：不发请求（省一次配额，也避免服务端返回空 audio 让我们误判成功）
    if (trimmed.isEmpty) {
      throw const MinimaxTtsException('要播报的文字是空的');
    }
    if (apiKey.trim().isEmpty) {
      throw const MinimaxTtsException('还没填 MiniMax API Key');
    }

    final uri = _endpoint(baseUrl, groupId);
    final body = jsonEncode({
      'model': model,
      'text': trimmed,
      'stream': false,
      // 关键：要 hex，返回的是十六进制字符串，不是 base64
      'output_format': 'hex',
      'language_boost': 'auto',
      'voice_setting': {
        'voice_id': voiceId,
        // MiniMax 的范围：speed 0.5~2.0、vol 0~10、pitch -12~12（整数）
        'speed': speed.clamp(0.5, 2.0),
        'vol': 1,
        'pitch': pitch.clamp(-12, 12),
      },
      'audio_setting': {
        'sample_rate': 32000,
        'bitrate': 128000,
        'format': 'mp3',
        'channel': 1,
      },
    });

    final httpClient = client ?? http.Client();
    try {
      final res = await httpClient
          .post(uri,
              headers: {
                'Authorization': 'Bearer ${apiKey.trim()}',
                'Content-Type': 'application/json',
              },
              body: body)
          .timeout(requestTimeout);

      // 中文错误文案必须按 UTF-8 解，否则会变乱码
      final raw = utf8.decode(res.bodyBytes, allowMalformed: true);
      if (res.statusCode != 200) {
        throw MinimaxTtsException(_httpMessage(res.statusCode, raw));
      }

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const MinimaxTtsException('MiniMax 返回的数据看不懂，稍后再试');
      }

      // 业务错误：HTTP 200 + base_resp.status_code != 0
      final baseResp = decoded['base_resp'];
      final code = (baseResp is Map ? baseResp['status_code'] : null);
      if (code is int && code != 0) {
        final msg = (baseResp is Map ? baseResp['status_msg'] as String? : null) ??
            '';
        throw MinimaxTtsException(_businessMessage(code, msg));
      }

      final audioHex = (decoded['data'] is Map)
          ? (decoded['data'] as Map)['audio'] as String?
          : null;
      final bytes = decodeHexAudio(audioHex);
      if (bytes.isEmpty) {
        throw const MinimaxTtsException('MiniMax 这次没返回音频，稍后再试');
      }
      return bytes;
    } on MinimaxTtsException {
      rethrow;
    } on FormatException {
      throw const MinimaxTtsException('MiniMax 返回的音频数据格式不对');
    } catch (e) {
      // 网络 / 超时 / 解析异常统一成可读文案，绝不让训练播报崩掉
      throw MinimaxTtsException('云端音色暂时用不了（$e）');
    } finally {
      if (client == null) httpClient.close();
    }
  }

  /// `{baseUrl}/v1/t2a_v2?GroupId=…`（baseUrl 已带 `/v1` 也容忍）
  static Uri _endpoint(String baseUrl, String? groupId) {
    var base = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    if (base.isEmpty) base = defaultBaseUrl;
    final path = base.endsWith('/v1') ? '/t2a_v2' : '/v1/t2a_v2';
    final g = (groupId ?? '').trim();
    return Uri.parse('$base$path${g.isEmpty ? '' : '?GroupId=$g'}');
  }

  /// hex → 字节。**这是本功能最容易写错的一步**：`data.audio` 是
  /// `"4944330..."` 这样的十六进制字符串，直接 base64 解码会得到垃圾。
  static Uint8List decodeHexAudio(String? hex) {
    if (hex == null || hex.isEmpty) return Uint8List(0);
    final cleaned = hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    // 奇数长度说明数据被截断：丢掉最后一个半字节，而不是抛错
    final usable = cleaned.length.isOdd ? cleaned.substring(0, cleaned.length - 1) : cleaned;
    final out = Uint8List(usable.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(usable.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  static String _businessMessage(int code, String msg) => switch (code) {
        // 1004 = 鉴权失败（Key 不对 / 与 GroupId 不匹配）
        1004 || 1002 => 'MiniMax Key 无效，去「语音教练 → 云端音色」检查一下',
        // 1008 = 余额不足 / 1006 = 请求过快
        1008 => 'MiniMax 余额 / 额度不足，换回系统音色或充值后再试',
        1006 => 'MiniMax 请求太频繁，稍后再试',
        _ => '云端音色合成失败${msg.isEmpty ? '' : '（$msg）'}',
      };

  static String _httpMessage(int code, String body) => switch (code) {
        401 || 403 => 'MiniMax Key 无效或没有权限（HTTP $code）',
        429 => 'MiniMax 请求太频繁，稍后再试',
        _ => '云端音色接口出错（HTTP $code）${body.isEmpty ? '' : '：${_brief(body)}'}',
      };

  static String _brief(String body) =>
      body.length <= 120 ? body : '${body.substring(0, 120)}…';
}
