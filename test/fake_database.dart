import 'package:drift/native.dart';

import 'package:fittrack/core/database/database.dart';

/// 测试用假库：内存 + 不灌种子（wipe 之外的用例不碰这些表）
AppDatabase fakeDatabase() =>
    AppDatabase.withExecutor(NativeDatabase.memory());
