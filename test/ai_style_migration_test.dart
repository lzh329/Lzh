import 'package:flutter_test/flutter_test.dart';

import 'package:fittrack/core/database/database.dart';

void main() {
  group('v18 迁移：默认风格切到豆包感', () {
    test('迁移 SQL 只把 guga 改成 doubao，不影响其他风格', () {
      const sql = AiStyleMigration.sqlLegacyGugaToDoubao;
      expect(sql, contains("SET ai_style = 'doubao'"));
      expect(sql, contains("WHERE ai_style = 'guga'"));
      // 只动 guga，不能误伤 gentle / strict / doubao
      expect(sql, isNot(contains("'gentle'")));
      expect(sql, isNot(contains("'strict'")));
    });

    test('schemaVersion 为 18', () {
      final db = AppDatabase();
      expect(db.schemaVersion, 18);
      // 不触发任何查询，直接关闭（LazyDatabase 不会打开 sqlite 文件）
      db.close();
    });
  });
}
