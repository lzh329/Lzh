import 'package:flutter/material.dart';

import 'package:fittrack/core/theme/app_colors.dart';
import 'package:fittrack/features/ai/domain/coach_abilities.dart';

/// 「嘎教练能做什么」——只读清单页
///
/// 数据全部来自 [CoachAbilities]（它再从 AiMergedTools 现读），页面不手抄
/// 工具名：工具面一改，这页自动跟着变；漏写文案则由测试兜住。
class CoachAbilitiesPage extends StatelessWidget {
  const CoachAbilitiesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final reads = CoachAbilities.readAbilities();
    final writes = CoachAbilities.writeAbilities();

    return Scaffold(
      appBar: AppBar(title: const Text('嘎教练能做什么'), centerTitle: false),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          const _Intro(),
          const SizedBox(height: 18),
          _Section(
            title: '能查',
            hint: '${reads.length} 项 · 自动执行，不用你确认',
            children: [
              for (final r in reads) AbilityRow(text: r.text),
            ],
          ),
          const SizedBox(height: 20),
          _Section(
            title: '能改',
            hint: '${writes.length} 项 · 动手前会先问你',
            children: [
              for (final w in writes)
                AbilityRow(text: w.text, destructive: w.destructive),
            ],
          ),
          const SizedBox(height: 20),
          _Section(
            title: '会自动做',
            hint: '不用你开口，${CoachAbilities.automatic.length} 件事它自己会做',
            children: [
              for (final a in CoachAbilities.automatic) AbilityRow(text: a),
            ],
          ),
          const SizedBox(height: 18),
          const Text(
            '写操作都会先弹确认卡，你点「确认」才真的动数据；删除类还会用红色提示。',
            style: TextStyle(
                fontSize: 11, color: AppColors.textTertiary, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: const Text(
        '你直接跟它说话就行，不用记命令。下面这些是它现在真的能做到的事。',
        style: TextStyle(fontSize: 12, height: 1.6),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String hint;
  final List<Widget> children;

  const _Section({
    required this.title,
    required this.hint,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(hint,
            style: const TextStyle(
                fontSize: 11, color: AppColors.textTertiary)),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

/// 一行能力：中文名 + 一句示例说法（+ 危险标记）
class AbilityRow extends StatelessWidget {
  final AbilityText text;
  final bool destructive;

  const AbilityRow({super.key, required this.text, this.destructive = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(text.label,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              if (destructive) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withAlpha(30),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('删除类',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: AppColors.danger)),
                ),
              ],
            ],
          ),
          if (text.example.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text('「${text.example}」',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary)),
            ),
        ],
      ),
    );
  }
}
