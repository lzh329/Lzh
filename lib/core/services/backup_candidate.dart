import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../database/database.dart' show kSchemaVersion;

/// 可恢复备份的**来源类型**。
///
/// 为什么要分类，而不是「找到什么就用什么」：
/// - `export`：用户主动「导出数据库」带走的那份，最常见、最可信；
/// - `autoBackup`：App 每周自己做的。**它可能在"当时库是空的"状态下做的** ——
///   这正是「导出 → 恢复后得到空库」事故的来源，必须在列表里和别的来源区分开；
/// - `preRestore`：上一次恢复之前自动留下的那份，是丢数据时最后的救命稻草；
/// - `archive`：zip 备份包（含照片），清除数据 / 降级页产出。
enum BackupSourceKind { export, autoBackup, preRestore, archive }

extension BackupSourceKindLabel on BackupSourceKind {
  String get label => switch (this) {
        BackupSourceKind.export => '导出文件',
        BackupSourceKind.autoBackup => '自动备份',
        BackupSourceKind.preRestore => '恢复前副本',
        BackupSourceKind.archive => '备份包',
      };

  /// 是否自带照片。裸 `.sqlite` 只有库，zip 包才有 `photos/`。
  ///
  /// 用户选裸库恢复时照片不会被清空（恢复流程只在包里有照片时才导入），
  /// 这一点必须在 UI 上说清楚，否则用户会以为"照片也一起恢复了"。
  bool get includesPhotos => this == BackupSourceKind.archive;
}

/// 关键表行数摘要（候选列表与确认弹窗共用一份口径）。
@immutable
class BackupCounts {
  final int workouts;
  final int bodyMetrics;
  final int photos;

  /// 动作字典行数（内置 40 条）。只在诊断时用，不参与"是否有用户数据"的判断。
  final int exercises;

  const BackupCounts({
    this.workouts = 0,
    this.bodyMetrics = 0,
    this.photos = 0,
    this.exercises = 0,
  });

  static const BackupCounts zero = BackupCounts();

  /// 「关键表全为 0」= 这份备份里没有用户记录。
  ///
  /// 只比 workouts / body_metrics / photos：`exercises` 是新库也有的内置字典
  /// （40 条），拿它判断"有数据"会把真正的空库放过去 —— 而"空库被当成好备份"
  /// 正是这次事故的直接原因。
  bool get isEmpty => workouts == 0 && bodyMetrics == 0 && photos == 0;

  /// 列表里的一行摘要。
  ///
  /// 四张关键表都要露出来：动作数（exercises）看起来"跟用户数据无关"，
  /// 但它是判断"这份文件到底是不是一个能用的库"的第四个证据 —— 前三张全对、
  /// 动作 0 条，说明这份包缺内置字典，恢复后训练页会一片空白。
  String get summary =>
      '训练 $workouts / 体重 $bodyMetrics / 照片 $photos / 动作 $exercises';
}

/// 一份「可恢复的备份文件」在 UI 上需要的全部信息。
@immutable
class BackupCandidate {
  final String path;
  final BackupSourceKind kind;
  final DateTime modifiedAt;
  final int sizeBytes;

  /// 关键表行数。
  ///
  /// **null = 统计不出来**（zip 里没有 manifest / 库打不开），不能写成 0：
  /// 0 是"确认为空"（要红色强警告），null 是"不知道"（只提示无法对比）。
  /// 把两者混成一个数字，就等于又在"盲选"。
  final BackupCounts? counts;

  /// 文件里的 `user_version`（zip 取 manifest，sqlite 读文件头）
  final int? userVersion;

  /// 能不能被当成备份恢复：sqlite 要能打开，zip 要含库文件条目。
  final bool readable;

  const BackupCandidate({
    required this.path,
    required this.kind,
    required this.modifiedAt,
    required this.sizeBytes,
    required this.counts,
    required this.userVersion,
    required this.readable,
  });

  bool get isArchive => kind == BackupSourceKind.archive;

  String get fileName => p.basename(path);

  String get timeLabel => DateFormat('MM-dd HH:mm').format(modifiedAt);

  String get sizeLabel => humanSize(sizeBytes);

  /// 「这份备份是什么时候的」——确认弹窗的主语
  String get title => '${kind.label} · $timeLabel';

  static String humanSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}

/// 恢复前的二次确认内容（纯逻辑：文案 + 风险标记，便于单测）。
///
/// 放在 service 层而不是 UI 里，是因为这段文案直接决定"用户会不会点下去"，
/// 它比任何一个按钮都更需要被测到。
@immutable
class RestorePreview {
  /// 一行对比：「将用 10-31 23:56 的备份（体重 3 条 / 训练 5 次 / 照片 2 张）
  /// 覆盖当前数据（体重 0 / 训练 0 / 照片 0）」
  final String summary;

  /// 红色强警告（null = 不需要）。存在时 UI 必须用 `AppColors.danger` 渲染。
  final String? hardWarning;

  /// 轻提示（无法对比行数 / 版本偏新等）
  final List<String> notes;

  /// 是否属于「会清空现有数据」的高风险动作
  final bool destructive;

  const RestorePreview({
    required this.summary,
    required this.destructive,
    this.hardWarning,
    this.notes = const [],
  });

  /// 生成确认内容。
  ///
  /// [current] 为 null 表示当前库读不出行数（降级态 / 已损坏）。
  static RestorePreview of({
    required BackupCandidate candidate,
    required BackupCounts? current,
    int schemaVersion = kSchemaVersion,
  }) {
    final candidateCounts = candidate.counts;

    /// 候选自身就是空库 → **一定**属于"会清空"，与当前行数无关。
    ///
    /// 降级态（库打不开）读不出 `current`，而那恰恰是用户最急的现场；
    /// 「用空库覆盖」在任何情况下都等于清空，这道红色警告不能因为
    /// "对比不了"就消失。
    final candidateIsEmpty =
        candidate.readable && candidateCounts != null && candidateCounts.isEmpty;

    /// 原口径：候选比当前库更空（当前有数据）→ 高风险。
    ///
    /// 已被 [candidateIsEmpty] 覆盖，但保留这一支是为了让"候选更空 + 当前有数据"
    /// 这条规则字面成立 —— 将来 readable 的判定方式变了也不会悄悄失去保护。
    final wipesExistingData = candidateCounts != null &&
        candidateCounts.isEmpty &&
        current != null &&
        !current.isEmpty;

    final destructive = candidateIsEmpty || wipesExistingData;

    final buffer = StringBuffer('将用 ${candidate.timeLabel} 的${candidate.kind.label}');
    if (candidateCounts != null) {
      buffer.write('（体重 ${candidateCounts.bodyMetrics} 条 / '
          '训练 ${candidateCounts.workouts} 次 / '
          '照片 ${candidateCounts.photos} 张）');
    }
    buffer.write('覆盖当前数据');
    if (current != null) {
      buffer.write('（体重 ${current.bodyMetrics} / '
          '训练 ${current.workouts} / '
          '照片 ${current.photos}）');
    }
    buffer.write('。');

    final notes = <String>[];
    if (candidateCounts == null) {
      notes.add('这份备份没有行数信息，恢复前无法和现在的记录对比。');
    }
    if (!candidate.kind.includesPhotos) {
      notes.add('这份文件只有数据库，照片不会跟着恢复（现有照片保持不动）。');
    }
    if (current == null) {
      notes.add('当前数据库读不出行数，无法对比。');
    }

    String? hard;
    if (!candidate.readable) {
      hard = '这个文件读不出内容，多半已损坏或不是数据库备份。'
          '恢复会在校验阶段被拒绝，你现在数据不会被改动。';
    } else if (destructive) {
      // 降级态拿不到 current，就别说"清空你现在的 N 条"（那是编的）；
      // 但要讲清更重的一层：库本来就打不开，被覆盖后现场就没了。
      final scope = current == null
          ? '这份备份里的关键记录全是 0 —— 用它恢复等于把数据清空，'
              '而现在这个数据库本来就已经打不开，覆盖之后什么都找不回来。'
          : '这份备份里的关键记录全是 0。继续恢复会清空你现在的 '
              '${current.workouts} 次训练 / ${current.bodyMetrics} 条体重 / '
              '${current.photos} 张照片。';
      hard = '$scope\n被覆盖的数据只能在「恢复前副本」里找回。';
    } else if (candidate.userVersion != null &&
        candidate.userVersion! > schemaVersion) {
      hard = '这份备份来自更新版本的减肥嘎（数据版本 ${candidate.userVersion}，'
          '当前支持 $schemaVersion），恢复会被拒绝。';
    }

    return RestorePreview(
      summary: buffer.toString(),
      destructive: destructive,
      hardWarning: hard,
      notes: notes,
    );
  }
}

