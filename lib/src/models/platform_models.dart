class SubscriptionPlan {
  const SubscriptionPlan({
    required this.id,
    required this.name,
    required this.createdAt,
    this.description,
    this.maxResources = 5,
    this.priceMonthly = 0,
    this.features = const [],
    this.isPopular = false,
    this.isActive = true,
  });

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) {
    return SubscriptionPlan(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      maxResources: json['max_resources'] as int? ?? 5,
      priceMonthly: (json['price_monthly'] as num?)?.toDouble() ?? 0,
      features: (json['features'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      isPopular: json['is_popular'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
  final String id;
  final String name;
  final String? description;
  final int maxResources;
  final double priceMonthly;
  final List<String> features;
  final bool isPopular;
  final bool isActive;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'max_resources': maxResources,
        'price_monthly': priceMonthly,
        'features': features,
        'is_popular': isPopular,
        'is_active': isActive,
      };

  SubscriptionPlan copyWith({
    String? id,
    String? name,
    String? description,
    int? maxResources,
    double? priceMonthly,
    List<String>? features,
    bool? isPopular,
    bool? isActive,
    DateTime? createdAt,
  }) {
    return SubscriptionPlan(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      maxResources: maxResources ?? this.maxResources,
      priceMonthly: priceMonthly ?? this.priceMonthly,
      features: features ?? this.features,
      isPopular: isPopular ?? this.isPopular,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class PlatformSettings {
  const PlatformSettings({
    required this.id,
    this.currency = 'ZAR',
    this.commissionType = 'percentage',
    this.commissionRate = 10.0,
    this.cancellationWindowHours = 24,
    this.updatedAt,
  });

  factory PlatformSettings.fromJson(Map<String, dynamic> json) {
    return PlatformSettings(
      id: json['id'] as String,
      currency: json['currency'] as String? ?? 'ZAR',
      commissionType: json['commission_type'] as String? ?? 'percentage',
      commissionRate: (json['commission_rate'] as num?)?.toDouble() ?? 10.0,
      cancellationWindowHours: json['cancellation_window_hours'] as int? ?? 24,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }
  final String id;
  final String currency;
  final String commissionType;
  final double commissionRate;
  final int cancellationWindowHours;
  final DateTime? updatedAt;

  Map<String, dynamic> toJson() => {
        'currency': currency,
        'commission_type': commissionType,
        'commission_rate': commissionRate,
        'cancellation_window_hours': cancellationWindowHours,
      };
}

class Invoice {
  const Invoice({
    required this.id,
    required this.tenantId,
    required this.periodStart,
    required this.periodEnd,
    required this.createdAt,
    this.subscriptionAmount = 0,
    this.commissionAmount = 0,
    this.totalAmount = 0,
    this.status = 'pending',
    this.tenantName,
  });

  factory Invoice.fromJson(Map<String, dynamic> json) {
    return Invoice(
      id: json['id'] as String,
      tenantId: json['tenant_id'] as String,
      periodStart: DateTime.parse(json['period_start'] as String),
      periodEnd: DateTime.parse(json['period_end'] as String),
      subscriptionAmount:
          (json['subscription_amount'] as num?)?.toDouble() ?? 0,
      commissionAmount: (json['commission_amount'] as num?)?.toDouble() ?? 0,
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0,
      status: json['status'] as String? ?? 'pending',
      createdAt: DateTime.parse(json['created_at'] as String),
      tenantName: json['tenants'] != null
          ? (json['tenants'] as Map<String, dynamic>)['name'] as String?
          : null,
    );
  }
  final String id;
  final String tenantId;
  final DateTime periodStart;
  final DateTime periodEnd;
  final double subscriptionAmount;
  final double commissionAmount;
  final double totalAmount;
  final String status;
  final DateTime createdAt;

  // Joined field
  final String? tenantName;

  Map<String, dynamic> toJson() => {
        'tenant_id': tenantId,
        'period_start': periodStart.toIso8601String().split('T').first,
        'period_end': periodEnd.toIso8601String().split('T').first,
        'subscription_amount': subscriptionAmount,
        'commission_amount': commissionAmount,
        'total_amount': totalAmount,
        'status': status,
      };
}
