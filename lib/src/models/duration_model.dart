class DurationModel {
  const DurationModel({
    required this.id,
    required this.resourceId,
    required this.label,
    required this.minutes,
    required this.price,
    required this.createdAt,
    this.periodId,
    this.isActive = true,
  });

  factory DurationModel.fromJson(Map<String, dynamic> json) {
    return DurationModel(
      id: json['id'] as String,
      resourceId: json['resource_id'] as String,
      periodId: json['period_id'] as String?,
      label: json['label'] as String,
      minutes: json['minutes'] as int,
      price: (json['price'] as num).toDouble(),
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
  final String id;
  final String resourceId;
  final String? periodId;
  final String label;
  final int minutes;
  final double price;
  final bool isActive;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'resource_id': resourceId,
        // Omitted when null: the column is NOT NULL, so an update without a
        // period must not clobber the existing assignment.
        if (periodId != null) 'period_id': periodId,
        'label': label,
        'minutes': minutes,
        'price': price,
        'is_active': isActive,
      };

  DurationModel copyWith({String? label, int? minutes, double? price}) =>
      DurationModel(
        id: id,
        resourceId: resourceId,
        periodId: periodId,
        label: label ?? this.label,
        minutes: minutes ?? this.minutes,
        price: price ?? this.price,
        isActive: isActive,
        createdAt: createdAt,
      );
}
