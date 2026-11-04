import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/services/character_lines.dart';

/// C-10 禁用词零命中。
///
/// 为什么扫源码而不是只扫常量表：文案漏写到 widget 里是最常见的一种回归
/// （`Text('你瘦了')` 一行就进去了），只有扫描全部 `lib/` 才拦得住。
///
/// 两条豁免，都是有理由的：
/// 1. `character_lines.dart` 本身声明了禁用词表 —— 不豁免它这个测试永远红。
/// 2. **注释行**（`//` / `///` / `*` 开头）不算 UI 文案 —— 代码里说明"为什么不能说
///    『瘦了』"是必要的，把解释也禁掉只会逼人删注释。
void main() {
  test('lib/ 下所有非注释代码都不含禁用词', () {
    final offenders = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.endsWith('character_lines.dart'));

    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final trimmed = lines[i].trimLeft();
        // 注释行豁免
        if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
        for (final word in kForbiddenFormWords) {
          if (lines[i].contains(word)) {
            offenders.add('${file.path}:${i + 1} 命中「$word」→ ${lines[i].trim()}');
          }
        }
      }
    }

    expect(offenders, isEmpty,
        reason: '禁用词是"把形态和用户身材挂钩"的说法。\n${offenders.join('\n')}');
  });

  test('禁用词表本身的内容是定稿的 6 个词，且不含"肥"', () {
    expect(kForbiddenFormWords, [
      '瘦了',
      '变瘦',
      '苗条',
      '胖了',
      '减肥形态',
      '瘦身版',
    ]);
    expect(kForbiddenFormWords.contains('肥'), isFalse,
        reason: '咕嘎的档名「肥咕嘎」沿用现值，说的是角色不是用户');
  });

  test('新增文案（角色台词 / 形态名 / 解锁提示 / 页头）零命中', () {
    final samples = <String>[
      kCharacterSlogan,
      kMissingAssetPlaceholder,
      kMissingAssetShort,
      kAllFormsUnlocked,
      kRemainToNextForm(1.4, '普通咕嘎'),
      kGugaIntroLine,
      kNuonuoIntroLine,
      kPhoebeIntroLine,
      kGugaFormUpLine,
      kNuonuoFormUpLine,
      ...kGugaLinesByTier.values.expand((v) => v),
      ...kNuonuoLinesByTier.values.expand((v) => v),
      ...kPhoebeLinesByTier.values.expand((v) => v),
    ];
    for (final text in samples) {
      for (final word in kForbiddenFormWords) {
        expect(text.contains(word), isFalse, reason: '「$text」命中禁用词「$word」');
      }
    }
  });
}
