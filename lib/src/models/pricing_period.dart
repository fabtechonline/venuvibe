/// A named, non-overlapping date range that owns a resource's pricing:
/// duration tiers belong to a period, and a period may override the
/// resource's default hourly rate for custom bookings.
class PricingPeriod {
  const PricingPeriod({
    required this.id,
    required this.resourceId,
    required this.name,
    required this.startDate,
    required this.endDate,
    this.hourlyRate,
    this.isActive = true,
    this.createdAt,
  });

  factory PricingPeriod.fromJson(Map<String, dynamic> json) {
    return PricingPeriod(
      id: json['id'] as String,
      resourceId: json['resource_id'] as String,
      name: json['name'] as String,
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: DateTime.parse(json['end_date'] as String),
      hourlyRate: (json['hourly_rate'] as num?)?.toDouble(),
      isActive: json['is_active'] as bool? ?? true,
      createdAt: json['created_at'] == null
          ? null
          : DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;
  final String resourceId;
  final String name;

  /// Date-only (midnight); both bounds inclusive, matching the DB daterange.
  final DateTime startDate;
  final DateTime endDate;

  /// Custom-booking rate for this season; null = use the resource default.
  final double? hourlyRate;
  final bool isActive;
  final DateTime? createdAt;

  Map<String, dynamic> toJson() => {
        'resource_id': resourceId,
        'name': name,
        'start_date': startDate.toIso8601String().substring(0, 10),
        'end_date': endDate.toIso8601String().substring(0, 10),
        'hourly_rate': hourlyRate,
        'is_active': isActive,
      };

  PricingPeriod copyWith({
    String? name,
    DateTime? startDate,
    DateTime? endDate,
    double? hourlyRate,
    bool clearHourlyRate = false,
  }) =>
      PricingPeriod(
        id: id,
        resourceId: resourceId,
        name: name ?? this.name,
        startDate: startDate ?? this.startDate,
        endDate: endDate ?? this.endDate,
        hourlyRate: clearHourlyRate ? null : (hourlyRate ?? this.hourlyRate),
        isActive: isActive,
        createdAt: createdAt,
      );
}
