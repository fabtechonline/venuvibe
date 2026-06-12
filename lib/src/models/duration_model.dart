class DurationModel {
  const DurationModel({
    required this.id,
    required this.resourceId,
    required this.label,
    required this.minutes,
    required this.price,
    required this.createdAt,
    this.isActive = true,
  });

  factory DurationModel.fromJson(Map<String, dynamic> json) {
    return DurationModel(
      id: json['id'] as String,
      resourceId: json['resource_id'] as String,
      label: json['label'] as String,
      minutes: json['minutes'] as int,
      price: (json['price'] as num).toDouble(),
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
  final String id;
  final String resourceId;
  final String label;
  final int minutes;
  final double price;
  final bool isActive;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'resource_id': resourceId,
        'label': label,
        'minutes': minutes,
        'price': price,
        'is_active': isActive,
      };

  DurationModel copyWith({String? label, int? minutes, double? price}) =>
      DurationModel(
        id: id,
        resourceId: resourceId,
        label: label ?? this.label,
        minutes: minutes ?? this.minutes,
        price: price ?? this.price,
        isActive: isActive,
        createdAt: createdAt,
      );
}
