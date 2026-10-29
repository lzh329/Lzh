import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/features/dashboard/presentation/widgets/greeting_header.dart';

/// 问候语称呼拼接：昵称 → 咕嘎形态名 → 不加称呼
///
/// 为什么测纯函数而不是 widget：问候区头像走 `Image.asset`，
/// widget test 环境没有真实 asset，会抛 "Unable to load asset" 把用例打红；
/// 而这里要保证的恰恰是**字符串拼接**（不许出现「下午好，」空尾或
/// 「下午好，null」），纯函数能穷举覆盖，widget 层只是把它接上去。
void main() {
  group('greetingWithName', () {
    test('有称呼 → 「问候，称呼」', () {
      expect(GreetingHeader.greetingWithName('下午好', '小嘎'), '下午好，小嘎');
    });

    test('称呼为 null → 只有问候语（无空尾）', () {
      expect(GreetingHeader.greetingWithName('下午好', null), '下午好');
    });

    test('称呼为空串 / 全空格 → 只有问候语', () {
      expect(GreetingHeader.greetingWithName('下午好', ''), '下午好');
      expect(GreetingHeader.greetingWithName('下午好', '   '), '下午好');
    });

    test('称呼是字符串 "null"（历史脏数据）→ 也不渲染它', () {
      expect(GreetingHeader.greetingWithName('下午好', 'null'), '下午好');
    });

    test('优先级：昵称有值就用昵称，没有才用形态名', () {
      String pick(String? nickname, String? gugaName) =>
          GreetingHeader.greetingWithName('下午好', nickname ?? gugaName);

      expect(pick('小嘎', '新手'), '下午好，小嘎');
      expect(pick(null, '新手'), '下午好，新手');
      expect(pick(null, null), '下午好');
    });
  });
}
