import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fittrack/core/database/database.dart';
import 'package:fittrack/core/services/cloud_voice_config.dart';
import 'package:fittrack/core/services/cloud_voice_player.dart';
import 'package:fittrack/core/services/edge_tts_service.dart';
import 'package:fittrack/core/services/minimax_tts_service.dart';
import 'package:fittrack/core/services/voice_presets.dart';
import 'package:fittrack/core/services/workout_coach.dart';
import 'package:fittrack/features/settings/data/user_settings_repository_impl.dart';

import 'fake_database.dart';

/// 云端音色（MiniMax）+ 5 个预设 + **回落系统 TTS**
///
/// 底线的底线：**训练播报不能哑**。云端只负责更好听；没 Key、断网、配额用完，
/// 都必须继续用系统 TTS 把"3、2、1"念出来。
void main() {
  // WorkoutCoach 是单例，构造时会用到平台通道对象；单测里需要 binding
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VoicePresets：5 个预设', () {
    test('5 个 id 唯一、名称/voiceId 非空、语速音调在 MiniMax 允许范围内', () {
      expect(VoicePresets.all, hasLength(5));
      final ids = VoicePresets.all.map((p) => p.id).toSet();
      expect(ids, hasLength(5), reason: 'id 必须唯一');
      for (final p in VoicePresets.all) {
        expect(p.name, isNotEmpty);
        expect(p.voiceId, isNotEmpty);
        expect(p.edgeVoiceId, isNotEmpty, reason: '每个预设都要有 Edge 音色 id');
        expect(p.speed, inInclusiveRange(0.5, 2.0));
        expect(p.pitch, inInclusiveRange(-12, 12));
        expect(p.pitch, isA<int>(), reason: 'MiniMax 的 pitch 必须是整数');
        expect(p.emoji, isNotEmpty);
      }
    });

    test('byId：null / 空串 / 脏值一律回落第一个（语音不能因脏数据失效）', () {
      expect(VoicePresets.byId(null).id, VoicePresets.all.first.id);
      expect(VoicePresets.byId('').id, VoicePresets.all.first.id);
      expect(VoicePresets.byId('ghost_preset').id, VoicePresets.all.first.id);
      expect(VoicePresets.byId('strict_coach').name, '严厉教练');
    });
  });

  group('MinimaxTtsService：hex 解码与错误文案', () {
    /// MP3 帧头 3 字节的 hex
    const audioHex = 'FFFB90';

    http.Response json200(Object body) => http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );

    test('正常响应：hex → 字节数 = 字符数/2', () async {
      final client = MockClient((_) async => json200({
            'data': {'audio': audioHex, 'status': 2},
            'base_resp': {'status_code': 0, 'status_msg': 'success'},
          }));

      final bytes = await MinimaxTtsService.synthesize(
        text: '开始',
        apiKey: 'sk-test',
        voiceId: 'female-shaonv',
        client: client,
      );

      expect(bytes, hasLength(3), reason: '6 个 hex 字符 = 3 字节');
      expect(bytes, equals(Uint8List.fromList([0xFF, 0xFB, 0x90])));
    });

    test('请求体符合 T2A v2：output_format=hex、pitch 是 int、模型 hd', () async {
      String? body;
      Uri? uri;
      final client = MockClient((request) async {
        body = request.body;
        uri = request.url;
        return json200({
          'data': {'audio': audioHex},
          'base_resp': {'status_code': 0},
        });
      });

      await MinimaxTtsService.synthesize(
        text: '第1组',
        apiKey: 'sk-test',
        groupId: '12345',
        voiceId: 'male-qn-qingse',
        speed: 1.0,
        pitch: -2,
        client: client,
      );

      final decoded = jsonDecode(body!) as Map<String, dynamic>;
      expect(decoded['model'], 'speech-02-hd');
      expect(decoded['output_format'], 'hex');
      expect(decoded['stream'], false);
      final vs = decoded['voice_setting'] as Map<String, dynamic>;
      expect(vs['voice_id'], 'male-qn-qingse');
      expect(vs['pitch'], isA<int>());
      expect((decoded['audio_setting'] as Map)['format'], 'mp3');
      expect(uri!.queryParameters['GroupId'], '12345');
      expect(uri!.path, endsWith('/v1/t2a_v2'));
    });

    test('base_resp.status_code != 0 → 抛可读异常（Key 无效 / 余额不足）', () async {
      Future<String> messageOf(int code) async {
        final client = MockClient((_) async => json200({
              'data': {'audio': ''},
              'base_resp': {'status_code': code, 'status_msg': 'raw msg'},
            }));
        try {
          await MinimaxTtsService.synthesize(
            text: '开始',
            apiKey: 'sk-test',
            voiceId: 'v',
            client: client,
          );
          fail('应该抛异常');
        } on MinimaxTtsException catch (e) {
          return e.message;
        }
      }

      expect(await messageOf(1004), contains('Key 无效'));
      expect(await messageOf(1008), contains('余额'));
    });

    test('空文本 / 空 Key 直接拒绝，**不发请求**（省配额）', () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return json200({
          'data': {'audio': audioHex},
          'base_resp': {'status_code': 0},
        });
      });

      await expectLater(
        MinimaxTtsService.synthesize(
            text: '   ', apiKey: 'sk-test', voiceId: 'v', client: client),
        throwsA(isA<MinimaxTtsException>()),
      );
      await expectLater(
        MinimaxTtsService.synthesize(
            text: '开始', apiKey: '  ', voiceId: 'v', client: client),
        throwsA(isA<MinimaxTtsException>()),
      );
      expect(calls, 0, reason: '空文本 / 空 Key 不该打接口');
    });

    test('返回空音频 → 抛异常（不能拿空字节去播）', () async {
      final client = MockClient((_) async => json200({
            'data': {'audio': ''},
            'base_resp': {'status_code': 0},
          }));
      await expectLater(
        MinimaxTtsService.synthesize(
            text: '开始', apiKey: 'sk-test', voiceId: 'v', client: client),
        throwsA(isA<MinimaxTtsException>()),
      );
    });
  });

  group('CloudVoicePlayer：缓存（同一句话只合成一次）', () {
    test('同一文本第二次不再请求合成；换音色则重新合成', () async {
      var synthesizeCalls = 0;
      final played = <int>[];
      final player = CloudVoicePlayer(
        provider: 'minimax',
        voiceId: 'female-shaonv',
        speed: 1.0,
        pitch: 1,
        synthesize: (text) async {
          synthesizeCalls++;
          return Uint8List.fromList([1, 2, 3]);
        },
        play: (bytes) async => played.add(bytes.length),
        stop: () async {},
      );

      await player.speak('开始');
      await player.speak('开始');
      await player.speak('开始');
      expect(synthesizeCalls, 1, reason: '固定短语必须命中缓存（省钱 + 少延迟）');
      expect(played, [3, 3, 3], reason: '每次都要播');
      expect(player.cachedCount, 1);

      await player.speak('3');
      expect(synthesizeCalls, 2, reason: '不同文本要重新合成');

      final other = CloudVoicePlayer(
        provider: 'minimax',
        voiceId: 'male-qn-jingying',
        speed: 1.1,
        pitch: -3,
        synthesize: (text) async {
          synthesizeCalls++;
          return Uint8List.fromList([4]);
        },
        play: (_) async {},
        stop: () async {},
      );
      await other.speak('开始');
      expect(synthesizeCalls, 3, reason: '换音色/语速/音调 ⇒ 缓存键不同，必须重新合成');
    });

    test('LRU 上限：超过 capacity 淘汰最久未用', () async {
      var calls = 0;
      final player = CloudVoicePlayer(
        provider: 'minimax',
        voiceId: 'v',
        capacity: 2,
        synthesize: (_) async {
          calls++;
          return Uint8List.fromList([1]);
        },
        play: (_) async {},
        stop: () async {},
      );
      await player.speak('a');
      await player.speak('b');
      await player.speak('a'); // 命中，a 刷新为最新
      await player.speak('c'); // 淘汰 b
      expect(player.cachedCount, 2);
      await player.speak('a'); // 仍命中
      expect(calls, 3, reason: 'a:1 b:2 c:3；a 未被淘汰');
    });

    test('空字节不缓存（下次还该重试）', () async {
      var calls = 0;
      final player = CloudVoicePlayer(
        provider: 'minimax',
        voiceId: 'v',
        synthesize: (_) async {
          calls++;
          return Uint8List(0);
        },
        play: (_) async {},
        stop: () async {},
      );
      await player.speak('x');
      await player.speak('x');
      expect(calls, 2);
      expect(player.cachedCount, 0);
    });

    test('prewarm：先合成缓存不播放，之后 speak 命中缓存零请求', () async {
      var synth = 0;
      var played = 0;
      final player = CloudVoicePlayer(
        provider: 'minimax',
        voiceId: 'v',
        synthesize: (_) async {
          synth++;
          return Uint8List.fromList([9]);
        },
        play: (_) async => played++,
        stop: () async {},
      );

      await player.prewarm(const ['3', '2', '1', '开始']);
      expect(synth, 4, reason: '4 个短语各合成一次');
      expect(played, 0, reason: '预热只缓存、不播放');
      expect(player.cachedCount, 4);

      await player.speak('3');
      expect(synth, 4, reason: '预热后 speak 命中缓存，不再合成');
      expect(played, 1);
    });
  });

  group('WorkoutCoach：云端失败 / 没配 Key 都回落系统 TTS（播报不哑）', () {
    late List<String> spoken;

    setUp(() {
      spoken = [];
      final coach = WorkoutCoach();
      coach.enabled = true;
      coach.systemSpeakOverride = (text) async => spoken.add(text);
      coach.applyMinimaxConfig(); // 默认关闭云端
    });

    tearDown(() {
      final coach = WorkoutCoach();
      coach.systemSpeakOverride = null;
      coach.applyMinimaxConfig();
      coach.enabled = true;
    });

    test('没配 Key：直接走系统 TTS', () async {
      final coach = WorkoutCoach();
      expect(coach.cloudEnabled, isFalse);
      await coach.speak('开始');
      expect(spoken, ['开始']);
    });

    test('云端抛异常（断网/Key 错/配额）：**自动回落系统 TTS**，不抛给调用方', () async {
      final coach = WorkoutCoach();
      coach.applyMinimaxConfig(
        apiKey: 'sk-test',
        voiceId: 'female-shaonv',
        player: CloudVoicePlayer(
          provider: 'minimax',
          voiceId: 'female-shaonv',
          synthesize: (_) async =>
              throw const MinimaxTtsException('断网了'),
          play: (_) async {},
          stop: () async {},
        ),
      );
      expect(coach.cloudEnabled, isTrue);

      await coach.speak('3');
      expect(spoken, ['3'], reason: '云端挂了也必须念出来');
    });

    test('云端成功：不走系统 TTS', () async {
      final coach = WorkoutCoach();
      var played = 0;
      coach.applyMinimaxConfig(
        apiKey: 'sk-test',
        voiceId: 'female-shaonv',
        player: CloudVoicePlayer(
          provider: 'minimax',
          voiceId: 'female-shaonv',
          synthesize: (_) async => Uint8List.fromList([1, 2]),
          play: (_) async => played++,
          stop: () async {},
        ),
      );

      await coach.speak('第1组');
      expect(played, 1);
      expect(spoken, isEmpty, reason: '云端成功就不该再叠一遍系统 TTS');
    });

    test('speakImmediate 同样回落', () async {
      final coach = WorkoutCoach();
      coach.applyMinimaxConfig(
        apiKey: 'sk-test',
        voiceId: 'v',
        player: CloudVoicePlayer(
          provider: 'minimax',
          voiceId: 'v',
          synthesize: (_) async => throw const MinimaxTtsException('挂了'),
          play: (_) async {},
          stop: () async {},
        ),
      );
      await coach.speakImmediate('2');
      expect(spoken, ['2']);
    });

    test('applyCloudConfig(apiKey: 空) 关掉云端 → 回到系统 TTS', () async {
      final coach = WorkoutCoach();
      coach.applyMinimaxConfig(apiKey: 'sk-test', voiceId: 'v');
      expect(coach.cloudEnabled, isTrue);
      coach.applyMinimaxConfig(); // 关闭
      expect(coach.cloudEnabled, isFalse);
      await coach.speak('开始');
      expect(spoken, ['开始']);
    });
  });

  group('ttsConfig 持久化（JSON 一列往返）', () {
    late AppDatabase db;
    late UserSettingsRepositoryImpl repo;

    setUp(() {
      db = fakeDatabase();
      repo = UserSettingsRepositoryImpl(db);
    });
    tearDown(() async => db.close());

    test('save → 读回一致；CloudVoiceConfig 解析/序列化往返不丢字段', () async {
      const config = CloudVoiceConfig(
        source: VoiceSource.minimax,
        apiKey: 'sk-abc',
        groupId: 'g-1',
        baseUrl: 'https://api.minimax.io',
        presetId: 'strict_coach',
      );
      await repo.save(ttsConfig: config.toJsonString());

      final row = await repo.get();
      expect(row?.ttsConfig, isNotNull);

      final parsed = CloudVoiceConfig.fromJsonString(row!.ttsConfig);
      expect(parsed.source, VoiceSource.minimax);
      expect(parsed.apiKey, 'sk-abc');
      expect(parsed.groupId, 'g-1');
      expect(parsed.baseUrl, 'https://api.minimax.io');
      expect(parsed.presetId, 'strict_coach');
      expect(parsed.ready, isTrue);
      expect(parsed.preset.voiceId, VoicePresets.byId('strict_coach').voiceId);
    });

    test('脏数据（半截 JSON / 类型不对）→ 回落默认配置，不抛', () {
      // 半截 JSON：解析失败 → 回落默认（Edge），绝不能抛
      final broken = CloudVoiceConfig.fromJsonString('{"provider":"minimax"');
      expect(broken.source, VoiceSource.edge);
      expect(broken.ready, isTrue, reason: 'Edge 默认通道恒可用');
      expect(CloudVoiceConfig.fromJsonString('null').source, VoiceSource.edge);
      expect(CloudVoiceConfig.fromJsonString('[1,2]').source, VoiceSource.edge);
      expect(
          CloudVoiceConfig.fromJsonString('{"provider":"minimax","presetId":5}')
              .presetId,
          VoicePresets.defaultPresetId);
    });

    test('ready 的判定：选了云端但没 Key 仍算未就绪（会走系统 TTS）', () {
      const noKey = CloudVoiceConfig(source: VoiceSource.minimax, apiKey: '  ');
      expect(noKey.ready, isFalse);
      const keyButSystem =
          CloudVoiceConfig(source: VoiceSource.system, apiKey: 'sk-abc');
      expect(keyButSystem.ready, isFalse);
    });
  });

  group('Edge TTS：三档解析与免费通道', () {
    test('applyTo：edge → 启用云端（无需 Key）', () {
      final coach = WorkoutCoach();
      const CloudVoiceConfig(source: VoiceSource.edge, presetId: 'calm_male')
          .applyTo(coach);
      expect(coach.cloudEnabled, isTrue);
    });

    test('applyTo：minimax 有 Key → MiniMax；没 Key → 关闭云端（回落系统）', () {
      final coach = WorkoutCoach();
      const CloudVoiceConfig(
              source: VoiceSource.minimax, apiKey: 'sk-x', presetId: 'calm_male')
          .applyTo(coach);
      expect(coach.cloudEnabled, isTrue);

      const CloudVoiceConfig(
              source: VoiceSource.minimax, apiKey: '  ', presetId: 'calm_male')
          .applyTo(coach);
      expect(coach.cloudEnabled, isFalse);
    });

    test('applyTo：system → 关闭云端', () {
      final coach = WorkoutCoach();
      const CloudVoiceConfig(source: VoiceSource.system).applyTo(coach);
      expect(coach.cloudEnabled, isFalse);
    });

    test('Edge 合成抛异常 → 自动回落系统 TTS', () async {
      final coach = WorkoutCoach();
      final spoken = <String>[];
      coach.systemSpeakOverride = (t) async => spoken.add(t);
      coach.enabled = true;
      coach.applyEdgeConfig(
        voiceId: 'zh-CN-XiaoxiaoNeural',
        player: CloudVoicePlayer(
          provider: 'edge',
          voiceId: 'zh-CN-XiaoxiaoNeural',
          synthesize: (_) async => throw const EdgeTtsException('挂了'),
          play: (_) async {},
          stop: () async {},
        ),
      );
      await coach.speak('开始');
      expect(spoken, ['开始'], reason: '免费音色挂了也必须念出来');
      coach.systemSpeakOverride = null;
      coach.disableCloud();
    });

    test('缓存 key 带 provider：Edge 与 MiniMax 同文本不串音', () async {
      var edgeCalls = 0;
      var miniCalls = 0;
      final edge = CloudVoicePlayer(
        provider: 'edge',
        voiceId: 'zh-CN-XiaoxiaoNeural',
        synthesize: (_) async {
          edgeCalls++;
          return Uint8List.fromList([1]);
        },
        play: (_) async {},
        stop: () async {},
      );
      final mini = CloudVoicePlayer(
        provider: 'minimax',
        voiceId: 'zh-CN-XiaoxiaoNeural',
        synthesize: (_) async {
          miniCalls++;
          return Uint8List.fromList([2]);
        },
        play: (_) async {},
        stop: () async {},
      );
      await edge.speak('开始');
      await mini.speak('开始');
      expect(edgeCalls, 1);
      expect(miniCalls, 1, reason: '同 voiceId 不同 provider 不能命中同一缓存');
    });
  });
}
