import 'package:drift/drift.dart';

// ═══════════════════════════════════════════════════════════════════
// 迁移幂等助手
//
// 背景（重要）：drift 的 `onUpgrade` 回调 **不在事务里**
// （`db_base.dart` 中全包唯一的事务出现在 `alterTable()` 内部）。
// 因此一个迁移块里连写多条 DDL 是有风险的：
//
//   1. 若第 2 条 DDL 失败，第 1 条已经落盘，但 `user_version` 没有推进；
//   2. 下次启动会从同一个 `from` 重跑整个迁移块；
//   3. 重跑时 `ALTER TABLE ... ADD COLUMN` 会撞 "duplicate column name"
//      抛异常 —— App 启动即死，用户只能卸载重装
//      （本地优先、无后端 = 数据全丢）；迁移块里的种子 INSERT 则会
//      **静默重复插入**（不崩，但用户看到两份「新手减脂」）。
//
// 实测澄清（不要被常见的说法带偏）：drift 2.35.2 的 `m.createTable` 生成的是
// `CREATE TABLE IF NOT EXISTS`（`migration.dart:317`），本身已幂等；真正
// 非幂等的是 `m.addColumn` 与种子 INSERT。这两类才是必须治的病根，
// `createTableIfNotExists` 只是为了语义统一与未来 drift 行为变化的防御。
//
// 这里的做法是「先查后建」：DDL 之前先查 `sqlite_master` / `PRAGMA table_info`，
// 目标已存在就跳过，让迁移块可重入（re-entrant），重跑一定会收敛。
//
// 注意：本文件 **不** 解决原子性。单条 DDL 失败仍可能留下半迁移状态
// （例如表已建、列没加），只是保证下一次启动能继续把迁移跑完而不是崩溃。
//
// 事务策略（v21 已定稿）：**纯 DDL 的迁移块不包事务**，靠本文件的幂等收敛兜住；
// 只有含数据变换（backfill / 删列 / 改类型）的迁移才必须整段包 BEGIN/COMMIT。
// 详见 DEVELOPMENT_PLAYBOOK.md「七、数据库迁移铁律」。
// ═══════════════════════════════════════════════════════════════════

/// 判断「表名列表」中是否已经包含 [table]。
///
/// 抽成纯函数便于单测：sqlite 的标识符不区分大小写，所以比较时统一转小写。
bool tableExistsIn(Iterable<String> tableNames, String table) {
  final target = table.toLowerCase();
  for (final name in tableNames) {
    if (name.toLowerCase() == target) return true;
  }
  return false;
}

/// 判断「列名列表」中是否已经包含 [column]（同样忽略大小写）。
bool columnExistsIn(Iterable<String> columnNames, String column) {
  final target = column.toLowerCase();
  for (final name in columnNames) {
    if (name.toLowerCase() == target) return true;
  }
  return false;
}

/// 查 `sqlite_master` 判断 [table] 是否已经建好。
///
/// 用参数绑定而不是拼字符串（表名来自 drift 生成代码，仍按不可信处理）。
Future<bool> tableExistsInDatabase(Migrator m, String table) async {
  final rows = await m.database.customSelect(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
    variables: [Variable<String>(table)],
  ).get();
  return rows.isNotEmpty;
}

/// 查 `PRAGMA table_info` 判断 [table].[column] 是否已经存在。
///
/// PRAGMA 不支持参数绑定，只能拼标识符，故做双引号转义。
Future<bool> columnExistsInDatabase(
  Migrator m,
  String table,
  String column,
) async {
  final quoted = '"${table.replaceAll('"', '""')}"';
  final rows =
      await m.database.customSelect('PRAGMA table_info($quoted)').get();
  return columnExistsIn(rows.map((row) => row.read<String>('name')), column);
}

/// 幂等建表：表已存在就跳过（drift 的 onUpgrade 无事务，重跑会撞 already exists）。
Future<void> createTableIfNotExists(Migrator m, TableInfo table) async {
  final exists = await tableExistsInDatabase(m, table.actualTableName);
  if (!exists) await m.createTable(table);
}

/// 幂等加列：列已存在就跳过（重跑会撞 duplicate column name）。
Future<void> addColumnIfNotExists(
  Migrator m,
  TableInfo table,
  GeneratedColumn column,
) async {
  final exists = await columnExistsInDatabase(
    m,
    table.actualTableName,
    column.name,
  );
  if (!exists) await m.addColumn(table, column);
}
