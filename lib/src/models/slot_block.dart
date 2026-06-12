class SlotBlock {
  const SlotBlock({
    required this.id,
    required this.resourceId,
    required this.startTime,
    required this.endTime,
    required this.createdAt,
    this.reason = 'maintenance',
    this.createdBy,
    this.resourceName,
  });

  factory SlotBlock.fromJson(Map<String, dynamic> json) {
    return SlotBlock(
      id: json['id'] as String,
      resourceId: json['resource_id'] as String,
      // Stored UTC; expose local so screens show the right wall-clock.
      startTime: DateTime.parse(json['start_time'] as String).toLocal(),
      endTime: DateTime.parse(json['end_time'] as String).toLocal(),
      reason: json['reason'] as String? ?? 'maintenance',
      createdBy: json['created_by'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      resourceName: json['resources'] != null
          ? (json['resources'] as Map<String, dynamic>)['name'] as String?
          : null,
    );
  }
  final String id;
  final String resourceId;
  final DateTime startTime;
  final DateTime endTime;
  final String reason;
  final String? createdBy;
  final DateTime createdAt;

  // Joined field
  final String? resourceName;

  Map<String, dynamic> toJson() => {
        'resource_id': resourceId,
        'start_time': startTime.toUtc().toIso8601String(),
        'end_time': endTime.toUtc().toIso8601String(),
        'reason': reason,
        'created_by': createdBy,
      };
}
