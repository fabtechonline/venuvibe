class Booking {
  const Booking({
    required this.id,
    required this.userId,
    required this.startTime,
    required this.endTime,
    required this.totalPrice,
    required this.createdAt,
    this.resourceId,
    this.durationId,
    this.commissionAmount,
    this.status = 'confirmed',
    this.paymentStatus = 'pending',
    this.cancellationReason,
    this.splitPayment = false,
    this.splitLink,
    this.basePrice,
    this.addonsTotal = 0,
    this.discountAmount = 0,
    this.paymentDueAt,
    this.recurringGroupId,
    this.resourceName,
    this.tenantName,
    this.userName,
  });

  factory Booking.fromJson(Map<String, dynamic> json) {
    final resourcesJson = json['resources'] as Map<String, dynamic>?;
    final tenantsJson = resourcesJson?['tenants'] as Map<String, dynamic>?;
    final profilesJson = json['profiles'] as Map<String, dynamic>?;
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
      basePrice: (json['base_price'] as num?)?.toDouble(),
      addonsTotal: (json['addons_total'] as num?)?.toDouble() ?? 0,
      discountAmount: (json['discount_amount'] as num?)?.toDouble() ?? 0,
      paymentDueAt: json['payment_due_at'] == null
          ? null
          : DateTime.parse(json['payment_due_at'] as String).toLocal(),
      recurringGroupId: json['recurring_group_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      resourceName: resourcesJson?['name'] as String?,
      tenantName: tenantsJson?['name'] as String?,
      userName: profilesJson?['full_name'] as String?,
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
  final double? basePrice;
  final double addonsTotal;
  final double discountAmount;

  /// Deadline to pay an approved custom booking before the slot is released.
  final DateTime? paymentDueAt;

  /// Set on every booking of one weekly series.
  final String? recurringGroupId;
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

  /// Statuses that hold the slot and count as a live booking for the user.
  static const activeStatuses = {'confirmed', 'pending_approval', 'approved'};

  bool get isCancellable =>
      activeStatuses.contains(status) && startTime.isAfter(DateTime.now());
  bool get isUpcoming =>
      activeStatuses.contains(status) && startTime.isAfter(DateTime.now());
  bool get isPast => endTime.isBefore(DateTime.now());

  /// Custom request waiting on the venue owner's decision.
  bool get isAwaitingApproval => status == 'pending_approval';

  /// Approved by the venue; customer still needs to pay to confirm.
  bool get isAwaitingPayment => status == 'approved';

  /// Custom request declined by the venue.
  bool get isRejected => status == 'rejected';

  /// Part of a weekly recurring series.
  bool get isRecurring => recurringGroupId != null;

  /// Whether the customer can move this booking to a new slot of the same
  /// length (confirmed slot bookings only, same window as cancellation).
  bool isReschedulableWithin(int windowHours) =>
      status == 'confirmed' &&
      durationId != null &&
      DateTime.now().isBefore(cancellationDeadline(windowHours));

  /// The moment after which free cancellation is no longer allowed
  /// (i.e. [windowHours] before the booking starts).
  DateTime cancellationDeadline(int windowHours) =>
      startTime.subtract(Duration(hours: windowHours));

  /// Whether the booking can still be cancelled for free, honouring the
  /// platform's free-cancellation window (hours before start time).
  /// Unpaid approval-pipeline bookings can always be cancelled.
  bool isCancellableWithin(int windowHours) =>
      isAwaitingApproval ||
      isAwaitingPayment ||
      (status == 'confirmed' &&
          DateTime.now().isBefore(cancellationDeadline(windowHours)));
}
