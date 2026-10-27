import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/features/ai/data/ai_voice_input.dart';
import 'package:fittrack/features/ai/presentation/widgets/ai_chat_input_bar.dart';

/// v20：应用内语音输入
///
/// 纯逻辑（[mergeVoiceText]）+ 输入栏降级行为（无识别服务时只提示不崩）。
/// 假语音服务是手写的子类，不引第三方 mock 库。
void main() {
  group('mergeVoiceText：保留已有文字，重复内容不重复追加', () {
    test('已有文字为空时直接用识别结果（首尾空白裁掉）', () {
      expect(mergeVoiceText('', '帮我看看进度'), '帮我看看进度');
      expect(mergeVoiceText('   ', '  帮我看看进度 '), '帮我看看进度');
    });

    test('识别结果为空时保持原样（中间结果抖动不清空输入）', () {
      expect(mergeVoiceText('我今天练了腿', ''), '我今天练了腿');
      expect(mergeVoiceText('我今天练了腿', '   '), '我今天练了腿');
    });

    test('两段不同内容：中文直接接上，不插空格', () {
      expect(mergeVoiceText('我今天练了腿', '感觉还行'), '我今天练了腿感觉还行');
    });

    test('第二段包含第一段（累积型中间结果）时整段替换，不重复', () {
      expect(mergeVoiceText('我今天', '我今天练了腿'), '我今天练了腿');
      expect(mergeVoiceText('今天练了', '今天练了腿'), '今天练了腿');
    });

    test('重复同一句时幂等（念两遍不会出现两遍）', () {
      const once = '帮我算算今天吃了多少';
      expect(mergeVoiceText(once, once), once);
      expect(mergeVoiceText(once, once), mergeVoiceText(once, once));
    });

    test('已有文字里已经包含这段识别结果时不追加', () {
      expect(
        mergeVoiceText('我今天练了腿，感觉还行', '练了腿'),
        '我今天练了腿，感觉还行',
      );
    });

    test('已有文字带结尾标点：直接接上，不再补标点或空格', () {
      expect(mergeVoiceText('练完了。', '记得喝水'), '练完了。记得喝水');
      expect(mergeVoiceText('练完了！', '记得喝水'), '练完了！记得喝水');
      expect(mergeVoiceText('练完了，', '记得喝水'), '练完了，记得喝水');
    });

    test('已有文字已带尾部空格：不重复补空格', () {
      expect(mergeVoiceText('练完了 ', '记得喝水'), '练完了 记得喝水');
    });

    test('英文 / 数字结尾补一个空格，避免单词粘连', () {
      expect(mergeVoiceText('do', 'squat'), 'do squat');
      expect(mergeVoiceText('做了 3', 'sets'), '做了 3 sets');
    });
  });

  group('输入栏语音降级（注入假语音服务）', () {
    Future<void> pumpBar(
      WidgetTester tester, {
      required AiVoiceInput voice,
      required TextEditingController controller,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AiInputBar(
              controller: controller,
              focusNode: FocusNode(),
              isStreaming: false,
              image: null,
              onPickImage: () {},
              onRemoveImage: () {},
              onSend: () {},
              voice: voice,
            ),
          ),
        ),
      );
    }

    testWidgets('语音不可用：点麦克风只弹提示，不抛异常、不崩', (tester) async {
      final controller = TextEditingController();
      final voice = _FakeVoice(available: false);
      await pumpBar(tester, voice: voice, controller: controller);

      expect(find.byIcon(Icons.mic_none), findsOneWidget);
      await tester.tap(find.byIcon(Icons.mic_none));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('没有可用的语音识别服务'), findsOneWidget);
      // 失败后按钮保持空闲态，输入框内容未被改动
      expect(find.byIcon(Icons.mic_none), findsOneWidget);
      expect(controller.text, '');
    });

    testWidgets('开始听时 hint 变提示、图标换成红色麦克风', (tester) async {
      final controller = TextEditingController();
      final voice = _FakeVoice(available: true);
      await pumpBar(tester, voice: voice, controller: controller);

      expect(find.byIcon(Icons.mic_none), findsOneWidget);
      await tester.tap(find.byIcon(Icons.mic_none));
      // 录音中是循环脉冲动画，不能 pumpAndSettle
      await tester.pump();
      expect(find.text('在听…再点一下结束'), findsOneWidget);
      expect(find.byIcon(Icons.mic), findsOneWidget, reason: '录音中换红色麦克风图标');

      // 再点一下结束：恢复空闲态
      await tester.tap(find.byIcon(Icons.mic));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.mic_none), findsOneWidget);
      expect(voice.stopCount, 1);
    });

    testWidgets('识别结果写进输入框：保留已有文字且去重', (tester) async {
      final controller = TextEditingController(text: '帮我看看');
      final voice = _FakeVoice(available: true);
      await pumpBar(tester, voice: voice, controller: controller);

      await tester.tap(find.byIcon(Icons.mic_none));
      await tester.pump();

      // 中间结果：累积型，第二次包含第一次，不能拼成两遍
      voice.emit('今天练了');
      await tester.pump();
      expect(controller.text, '帮我看看今天练了');
      voice.emit('今天练了腿');
      await tester.pump();
      expect(controller.text, '帮我看看今天练了腿');

      // 最终结果后收尾，文字留在输入框里可直接发送
      voice.emit('今天练了腿', isFinal: true);
      await tester.pump();
      expect(controller.text, '帮我看看今天练了腿');
    });

    testWidgets('发送时若正在听会先停止识别', (tester) async {
      final controller = TextEditingController(text: '在听的时候点了发送');
      final voice = _FakeVoice(available: true);
      await pumpBar(tester, voice: voice, controller: controller);

      await tester.tap(find.byIcon(Icons.mic_none));
      await tester.pump();
      expect(voice.stopCount, 0);

      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
      expect(voice.stopCount, 1, reason: '发送前必须先结束识别');
    });
  });
}

/// 手写假语音服务：只实现输入栏用到的几个方法，不碰真实插件
class _FakeVoice extends AiVoiceInput {
  _FakeVoice({required this.available});

  /// false = 模拟设备没有语音识别服务 / 权限被拒
  final bool available;

  void Function(String text, bool isFinal)? _onResult;
  bool _listening = false;
  int stopCount = 0;

  @override
  bool get isListening => _listening;

  @override
  String? get lastError =>
      available ? null : AiVoiceInput.unavailableMessage;

  @override
  Future<bool> init() async => available;

  @override
  Future<void> start({
    required void Function(String text, bool isFinal) onResult,
  }) async {
    if (!available) {
      onError?.call(AiVoiceInput.unavailableMessage);
      return;
    }
    _onResult = onResult;
    _listening = true;
    onListeningChanged?.call(true);
  }

  @override
  Future<void> stop() async {
    stopCount++;
    _listening = false;
    onListeningChanged?.call(false);
  }

  @override
  Future<void> cancel() async {
    _listening = false;
    onListeningChanged?.call(false);
  }

  /// 模拟识别结果回调（测试里手动触发中间 / 最终结果）
  void emit(String text, {bool isFinal = false}) =>
      _onResult?.call(text, isFinal);
}
