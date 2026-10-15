import 'plan_day_entity.dart';

class PlanEntity {
  final int id;
  final String name;
  final String? note;
  final bool isActive;
  final List<PlanDayEntity> days;

  const PlanEntity({
    required this.id,
    required this.name,
    this.note,
    this.isActive = true,
    this.days = const [],
  });
}
