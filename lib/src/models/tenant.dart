class Tenant {
  const Tenant({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.createdAt, this.description,
    this.logoUrl,
    this.address,
    this.city,
    this.country,
    this.timezone = 'UTC',
    this.phone,
    this.email,
    this.categoryId,
    this.subscriptionPlanId,
    this.isActive = true,
    this.status = 'pending',
  });

  factory Tenant.fromJson(Map<String, dynamic> json) {
    return Tenant(
      id: json['id'] as String,
      ownerId: json['owner_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      logoUrl: json['logo_url'] as String?,
      address: json['address'] as String?,
      city: json['city'] as String?,
      country: json['country'] as String?,
      timezone: json['timezone'] as String? ?? 'UTC',
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      categoryId: json['category_id'] as String?,
      subscriptionPlanId: json['subscription_plan_id'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      status: json['status'] as String? ?? 'pending',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
  final String id;
  final String ownerId;
  final String name;
  final String? description;
  final String? logoUrl;
  final String? address;
  final String? city;
  final String? country;
  final String timezone;
  final String? phone;
  final String? email;
  final String? categoryId;
  final String? subscriptionPlanId;
  final bool isActive;
  final String status; // pending, approved, suspended
  final DateTime createdAt;

  // Convenience getters matching screen references
  String get contactEmail => email ?? 'N/A';
  String? get contactPhone => phone;

  Map<String, dynamic> toJson() => {
        'owner_id': ownerId,
        'name': name,
        'description': description,
        'logo_url': logoUrl,
        'address': address,
        'city': city,
        'country': country,
        'timezone': timezone,
        'phone': phone,
        'email': email,
        'category_id': categoryId,
        'subscription_plan_id': subscriptionPlanId,
        'is_active': isActive,
        'status': status,
      };
}
