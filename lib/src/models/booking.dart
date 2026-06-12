class Booking {
  const Booking({
    required this.id,
    required this.userId,
    required this.startTime, required this.endTime, required this.totalPrice, required this.createdAt, this.resourceId,
    this.durationId,
    this.commissionAmount,
    this.status = 'confirmed',
    this.paymentStatus = 'pending',
    this.cancellationReason,
    this.splitPayment = false,
    this.splitLink,
    this.resourceName,
    this.tenantName,
    this.userName,
  });

  factory Booking.fromJson(Map<String, dynamic> json) {
    return Booking(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      resourceId: json['resource_id'] as String?,
      durationId: json['duration_id'] as String?,
      // Stored as UTC; convert to local so screens display the correct
      // wall-clock time. toJson() converts back to UTC on write.
      startTime: DateTime.parse(json['start_time'] as String).toLocal(),
      endTime: DateTime.parse(json['end_time'] as String).toLocal(),
      totalPrice: (json['total_price'] as num).toDouble(),
      commissionAmount: (json['commission_amount'] as num?)?.toDouble(),
      status: json['status'] as String? ?? 'confirmed',
      paymentStatus: json['payment_status'] as String? ?? 'pending',
      cancellationReason: json['cancellation_reason'] as String?,
      splitPayment: json['split_payment'] as bool? ?? false,
      splitLink: json['split_link'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      resourceName: json['resources'] != null
          ? (json['resources'] as Map<String, dynamic>)['name'] as String?
          : null,
      tenantName: json['resources']?['tenants'] != null
          ? (json['resources']['tenants'] as Map<String, dynamic>)['name']
              as String?
          : null,
      userName: json['profiles'] != null
          ? (json['profiles'] as Map<String, dynamic>)['full_name'] as String?
          : null,
    );
  }
  final String id;
  final String userId;
  final String? resourceId;
  final String? durationId;
  final DateTime startTime;
  final DateTime endTime;
  final double totalPrice;
  final double? commissionAmount;
  final String status;
  final String paymentStatus;
  final String? cancellationReason;
  final bool splitPayment;
  final String? splitLink;
  final DateTime createdAt;

  // Joined fields
  final String? resourceName;
  final String? tenantName;
  final String? userName;

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'resource_id': resourceId,
        'duration_id': durationId,
        'start_time': startTime.toUtc().toIso8601String(),
        'end_time': endTime.toUtc().toIso8601String(),
        'total_price': totalPrice,
        'commission_amount': commissionAmount,
        'status': status,
        'payment_status': paymentStatus,
        'split_payment': splitPayment,
      };

  bool get isCancellable =>
      status == 'confirmed' && startTime.isAfter(DateTime.now());
  bool get isUpcoming =>
      status == 'confirmed' && startTime.isAfter(DateTime.now());
  bool get isPast => endTime.isBefore(DateTime.now());

  /// The moment after which free cancellation is no longer allowed
  /// (i.e. [windowHours] before the booking starts).
  DateTime cancellationDeadline(int windowHours) =>
      startTime.subtract(Duration(hours: windowHours));

  /// Whether the booking can still be cancelled for free, honouring the
  /// platform's free-cancellation window (hours before start time).
  bool isCancellableWithin(int windowHours) =>
      status == 'confirmed' &&
      DateTime.now().isBefore(cancellationDeadline(windowHours));
}
