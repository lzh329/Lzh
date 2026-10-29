import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'package:fittrack/features/body_log/domain/entities/body_metric_entity.dart';

import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/core/services/notification_service.dart';
import 'package:fittrack/features/body_log/domain/repositories/body_metric_repository.dart';
import 'package:fittrack/features/body_log/domain/repositories/photo_repository.dart';
import 'package:fittrack/features/goal/domain/repositories/goal_repository.dart';

/// 体重/围度录入表单（从 body_metric_page 原样搬出，逻辑未改）
///
/// ⚠️ 技术债：内部仍用 `setState` 管理输入与保存后刷新，
/// 与本仓 "异步状态一律 Riverpod" 的约定不一致。本轮只做搬运，
/// 没有顺手改造（改造要连带 onSaved 回调与父页面刷新，属独立任务）。
class AddMetricForm extends StatefulWidget {
  final BodyMetricRepository bodyRepo;
  final PhotoRepository photoRepo;
  final GoalRepository goalRepo;
  final VoidCallback onSaved;

  const AddMetricForm({
    super.key,
    required this.bodyRepo,
    required this.photoRepo,
    required this.goalRepo,
    required this.onSaved,
  });

  @override
  State<AddMetricForm> createState() => AddMetricFormState();
}

class AddMetricFormState extends State<AddMetricForm> {
  final _weightCtrl = TextEditingController();
  final _waistCtrl = TextEditingController();
  final _hipCtrl = TextEditingController();
  final _chestCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  DateTime _date = DateTime.now();
  File? _photoFile;
  final _picker = ImagePicker();

  @override
  void dispose() {
    _weightCtrl.dispose();
    _waistCtrl.dispose();
    _hipCtrl.dispose();
    _chestCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    final file =
        await _picker.pickImage(source: ImageSource.camera, maxWidth: 1080);
    if (file != null) {
      setState(() => _photoFile = File(file.path));
    }
  }

  void _removePhoto() => setState(() => _photoFile = null);

  void _showWeightFeedback(double currentJin) async {
    // 查询上次体重（倒数第二条记录）
    final allMetrics = await widget.bodyRepo.getAll();
    double? changeJin;
    double? totalLossJin;

    if (allMetrics.length >= 2) {
      final prev = allMetrics[allMetrics.length - 2];
      changeJin = currentJin - prev.weightKg * 2;
    }

    // 累计减重（首条 vs 当前）
    if (allMetrics.isNotEmpty) {
      final first = allMetrics.first;
      totalLossJin = first.weightKg * 2 - currentJin;
    }

    await NotificationService().showWeightFeedback(
      currentWeightJin: currentJin,
      changeJin: changeJin,
      totalLossJin:
          totalLossJin != null && totalLossJin > 0 ? totalLossJin : null,
    );
  }

  /// 计算累计减重的 5 斤档位（0, 1, 2, ... 代表 0斤, 5斤, 10斤...）
  int _milestoneLevel(List<BodyMetricEntity> metrics) {
    if (metrics.length < 2) return 0;
    final lossJin = (metrics.first.weightKg - metrics.last.weightKg) * 2;
    return lossJin > 0 ? (lossJin ~/ 5) : 0;
  }

  /// 检测是否跨过新的 5 斤里程碑
  void _checkMilestone(int oldLevel) async {
    final metricsAfter = await widget.bodyRepo.getAll();
    final newLevel = _milestoneLevel(metricsAfter);
    if (newLevel > oldLevel && newLevel > 0 && mounted) {
      _showMilestoneDialog(newLevel * 5, metricsAfter);
    }
  }

  /// 里程碑庆祝全屏弹窗
  void _showMilestoneDialog(int totalLossJin, List<BodyMetricEntity> metrics) {
    final firstWeightJin = (metrics.first.weightKg * 2).toStringAsFixed(1);
    final currentWeightJin = (metrics.last.weightKg * 2).toStringAsFixed(1);
    final days = metrics.last.date.difference(metrics.first.date).inDays;
    final theme = Theme.of(context);

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutBack,
        builder: (context, value, child) {
          return Transform.scale(
            scale: value,
            child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
          );
        },
        child: Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🎉', style: TextStyle(fontSize: 56)),
                const SizedBox(height: 16),
                Text('太棒了！',
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('你已累计减重', style: theme.textTheme.bodyLarge),
                const SizedBox(height: 4),
                Text(
                  '$totalLossJin 斤',
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryText,
                  ),
                ),
                const SizedBox(height: 20),
                const Divider(color: AppColors.border),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('$firstWeightJin 斤',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: AppColors.textTertiary)),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Icon(Icons.arrow_forward, size: 18),
                    ),
                    Text('$currentWeightJin 斤',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 4),
                Text('用时 $days 天',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.textTertiary)),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('继续努力 💪'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 标题 + 日期（一行） ──
        Row(
          children: [
            Text('录入数据', style: theme.textTheme.titleSmall),
            const Spacer(),
            TextButton.icon(
              onPressed: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                  locale: const Locale('zh'),
                );
                if (date != null) setState(() => _date = date);
              },
              icon: const Icon(Icons.calendar_today, size: 15),
              label: Text(DateFormat('M月d日').format(_date),
                  style: const TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),

        // ── 体重（必填） ──
        TextField(
          controller: _weightCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
              labelText: '体重', suffixText: '斤', isDense: true),
        ),
        const SizedBox(height: 4),

        // ── 更多数据（围度 / 备注 / 拍照） ──
        Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: false,
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 4),
            dense: true,
            iconColor: AppColors.textTertiary,
            collapsedIconColor: AppColors.textTertiary,
            title: Text(
              '更多数据（围度 / 备注 / 拍照）',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.textTertiary),
            ),
            children: [
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _waistCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: '腰围', suffixText: 'cm', isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _hipCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: '臀围', suffixText: 'cm', isDense: true),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              TextField(
                controller: _chestCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: '胸围', suffixText: 'cm', isDense: true),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _noteCtrl,
                decoration:
                    const InputDecoration(labelText: '备注（可选）', isDense: true),
              ),
              const SizedBox(height: 10),
              if (_photoFile != null)
                Stack(
                  alignment: Alignment.topRight,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        _photoFile!,
                        height: 140,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      style:
                          IconButton.styleFrom(backgroundColor: Colors.black45),
                      onPressed: _removePhoto,
                    ),
                  ],
                )
              else
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _takePhoto,
                    icon: const Icon(Icons.camera_alt, size: 16),
                    label: const Text('拍照记录', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 34),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // ── 保存 ──
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child:
                const Text('保存', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final weight = double.tryParse(_weightCtrl.text);
    if (weight == null || weight <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('请输入有效的体重')));
      }
      return;
    }

    // 里程碑检测：保存前的累计减重等级
    final metricsBefore = await widget.bodyRepo.getAll();
    final oldLevel = _milestoneLevel(metricsBefore);

    // 检查当日是否已有记录
    final existingEntries = await widget.bodyRepo.getAll(
      from: DateTime(_date.year, _date.month, _date.day),
      to: DateTime(_date.year, _date.month, _date.day),
    );

    if (existingEntries.isNotEmpty) {
      // 当日已有记录，更新第一条
      final existing = existingEntries.first;
      await widget.bodyRepo.update(
        id: existing.id,
        date: _date,
        weightKg: weight / 2,
        waistCm: double.tryParse(_waistCtrl.text),
        hipCm: double.tryParse(_hipCtrl.text),
        chestCm: double.tryParse(_chestCtrl.text),
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      );

      // 保存照片
      if (_photoFile != null) {
        await widget.photoRepo.addPhoto(
          date: _date,
          imageFile: _photoFile!,
          note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        );
      }

      // 自动更新体重目标进度
      final goals = await widget.goalRepo.getAll();
      for (final g
          in goals.where((g) => g.type == 'weight' && !g.isCompleted)) {
        await widget.goalRepo.updateProgress(g.id, weight);
      }

      // 即时反馈通知
      _showWeightFeedback(weight);

      // 里程碑检测
      _checkMilestone(oldLevel);

      _clearInputs();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已更新当日体重记录')));
      }
      widget.onSaved();
      return;
    }

    // 保存身体数据
    await widget.bodyRepo.create(
      date: _date,
      weightKg: weight / 2,
      waistCm: double.tryParse(_waistCtrl.text),
      hipCm: double.tryParse(_hipCtrl.text),
      chestCm: double.tryParse(_chestCtrl.text),
      note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
    );

    // 保存照片
    if (_photoFile != null) {
      await widget.photoRepo.addPhoto(
        date: _date,
        imageFile: _photoFile!,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      );
    }

    // 自动更新体重目标进度
    final goals = await widget.goalRepo.getAll();
    for (final g in goals.where((g) => g.type == 'weight' && !g.isCompleted)) {
      await widget.goalRepo.updateProgress(g.id, weight);
    }

    // 即时反馈通知
    _showWeightFeedback(weight);

    // 里程碑检测
    _checkMilestone(oldLevel);

    _clearInputs();
    widget.onSaved();
  }

  /// 清空表单（保留日期）
  void _clearInputs() {
    _weightCtrl.clear();
    _waistCtrl.clear();
    _hipCtrl.clear();
    _chestCtrl.clear();
    _noteCtrl.clear();
    setState(() => _photoFile = null);
  }
}
