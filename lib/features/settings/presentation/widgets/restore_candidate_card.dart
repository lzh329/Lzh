import 'package:flutter/material.dart';

import 'package:fittrack/core/services/backup_candidate.dart';
import 'package:fittrack/core/theme/app_colors.dart';

/// 一份候选
class RestoreCandidateCard extends StatelessWidget {
  final BackupCandidate candidate;
  final VoidCallback? onTap;

  const RestoreCandidateCard({super.key, required this.candidate, this.onTap});

  @override
  Widget build(BuildContext context) {
    final counts = candidate.counts;
    final empty = counts != null && counts.isEmpty;
    // 空库候选必须一眼看出来：它就是上次事故里被自动选中的那种文件
    final countsLabel = counts == null
        ? '行数无法统计'
        : (empty ? '关键记录全为 0' : counts.summary);
    final countsColor = (empty || counts == null)
        ? AppColors.danger
        : AppColors.textSecondary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _KindChip(kind: candidate.kind),
                const SizedBox(width: 8),
                Text(
                  candidate.timeLabel,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                Text(
                  candidate.sizeLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              candidate.fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              countsLabel,
              style: TextStyle(fontSize: 12, color: countsColor),
            ),
          ],
        ),
      ),
    );
  }
}

class _KindChip extends StatelessWidget {
  final BackupSourceKind kind;

  const _KindChip({required this.kind});

  @override
  Widget build(BuildContext context) {
    // 恢复前副本用主色：丢数据时用户最该先看的往往是它
    final color = switch (kind) {
      BackupSourceKind.preRestore => AppColors.primaryText,
      BackupSourceKind.archive => AppColors.analysis,
      BackupSourceKind.export => AppColors.infoStrong,
      BackupSourceKind.autoBackup => AppColors.textSecondary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(24),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        kind.label,
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
