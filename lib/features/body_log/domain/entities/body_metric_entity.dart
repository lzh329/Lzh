class BodyMetricEntity {
  final int id;
  final DateTime date;
  final double weightKg;
  final double? waistCm;
  final double? hipCm;
  final double? chestCm;
  final String? note;

  const BodyMetricEntity({
    required this.id,
    required this.date,
    required this.weightKg,
    this.waistCm,
    this.hipCm,
    this.chestCm,
    this.note,
  });
}
