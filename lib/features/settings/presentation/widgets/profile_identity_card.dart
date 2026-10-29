import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:fittrack/core/providers.dart';
import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/settings/data/avatar_storage.dart';
import 'package:fittrack/features/settings/domain/entities/user_settings_entity.dart';

/// 个人档案顶部身份卡：头像 + 昵称（都可编辑）
///
/// 两个可点区域：
/// - 点头像 → 相册选图 → **拷贝到私有目录** → 存路径 → 删旧头像
/// - 点昵称 → 弹输入框（1~12 字；留空 = 清除，回到默认问候语）
///
/// 昵称/头像路径都可能是 null（用户没设过）→ 显示默认占位，
/// **绝不把 null 渲染成"null"或空尾**。
class ProfileIdentityCard extends ConsumerWidget {
  final UserSettingsEntity? settings;

  const ProfileIdentityCard({super.key, this.settings});

  static const int maxNicknameLength = 12;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final nickname = settings?.nickname;
    final avatarPath = settings?.avatarPath;
    final avatarFile = (avatarPath != null && File(avatarPath).existsSync())
        ? File(avatarPath)
        : null;

    final summary = <String>[
      if (settings?.heightCm != null)
        '身高 ${settings!.heightCm!.toStringAsFixed(0)}cm',
      if (settings?.targetWeightKg != null)
        '目标 ${(settings!.targetWeightKg! * 2).toStringAsFixed(1)} 斤',
    ];

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => _pickAvatar(context, ref, avatarPath),
              child: Stack(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withAlpha(28),
                      shape: BoxShape.circle,
                      image: avatarFile == null
                          ? null
                          : DecorationImage(
                              image: FileImage(avatarFile),
                              fit: BoxFit.cover,
                              // 文件在但内容损坏（截断/非图片）→ 保持占位底色，
                              // 不让解码异常变成红屏
                              onError: (_, __) {},
                            ),
                    ),
                    child: avatarFile == null
                        ? const Icon(Icons.person_outline,
                            size: 26, color: AppColors.primary)
                        : null,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: AppColors.surface,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.camera_alt_outlined,
                          size: 13, color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () => _editNickname(context, ref, nickname),
                    child: Row(
                      children: [
                        Text(
                          // 没设昵称 → 默认文案，不渲染 null
                          nickname == null || nickname.isEmpty
                              ? '设置昵称'
                              : nickname,
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.edit_outlined,
                            size: 13, color: AppColors.textTertiary),
                      ],
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    summary.isEmpty ? '还没填身体信息' : summary.join(' · '),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.textTertiary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAvatar(
    BuildContext context,
    WidgetRef ref,
    String? previousPath,
  ) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        imageQuality: 85,
      );
      if (picked == null) return; // 用户取消：静默

      final newPath = await copyAvatarToPrivate(
        picked.path,
        previousPath: previousPath,
      );
      if (newPath == null) {
        if (context.mounted) _toast(context, '头像保存失败，换一张试试');
        return;
      }
      await ref.read(userSettingsRepoProvider).saveAvatarPath(newPath);
      ref.invalidate(userSettingsProvider);
    } catch (e) {
      if (context.mounted) {
        _toast(context, '打开相册失败，检查权限后重试');
      }
    }
  }

  Future<void> _editNickname(
    BuildContext context,
    WidgetRef ref,
    String? current,
  ) async {
    final ctrl = TextEditingController(text: current ?? '');
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('设置昵称'),
        content: TextField(
          controller: ctrl,
          maxLength: maxNicknameLength,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '怎么称呼你？（留空恢复默认）',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == null) return; // 取消

    // 留空 = 清除 → 写 NULL（不是空串），问候语回到咕嘎形态名
    final trimmed = result.trim();
    // 超长截断（TextField 的 maxLength 已经挡了一层，这里兜底，
    // 防止粘贴/输入法绕过）→ 留空即清除
    final value = trimmed.isEmpty
        ? null
        : (trimmed.length > maxNicknameLength
            ? trimmed.substring(0, maxNicknameLength)
            : trimmed);
    await ref.read(userSettingsRepoProvider).saveNickname(value);
    ref.invalidate(userSettingsProvider);
  }

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }
}
