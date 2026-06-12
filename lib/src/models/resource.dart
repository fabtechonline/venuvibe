class Resource {
  const Resource({
    required this.id,
    required this.tenantId,
    required this.name,
    required this.createdAt,
    this.categoryId,
    this.description,
    this.capacity = 1,
    this.amenities = const [],
    this.images = const [],
    this.timezone = 'UTC',
    this.isActive = true,
    this.openTime = '07:00',
    this.closeTime = '23:00',
    this.minBookingMinutes = 30,
    this.bufferMinutes = 0,
    this.customSelectorEnabled = false,
    this.hourlyRate,
    this.tenantName,
    this.categoryName,
    this.tenantContactPerson,
    this.tenantPhone,
    this.tenantEmail,
    this.tenantAddress,
    this.tenantCity,
  });

  factory Resource.fromJson(Map<String, dynamic> json) {
    return Resource(
      id: json['id'] as String,
      tenantId: json['tenant_id'] as String,
      categoryId: json['category_id'] as String?,
      name: json['name'] as String,
      description: json['description'] as String?,
      capacity: json['capacity'] as int? ?? 1,
      amenities: (json['amenities'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      images: (json['images'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      timezone: json['timezone'] as String? ?? 'UTC',
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      openTime: _normalizeTime(json['open_time'] as String?, '07:00'),
      closeTime: _normalizeTime(json['close_time'] as String?, '23:00'),
      minBookingMinutes: json['min_booking_minutes'] as int? ?? 30,
      bufferMinutes: json['buffer_minutes'] as int? ?? 0,
      customSelectorEnabled: json['custom_selector_enabled'] as bool? ?? false,
      hourlyRate: (json['hourly_rate'] as num?)?.toDouble(),
      tenantName: json['tenants'] != null
          ? (json['tenants'] as Map<String, dynamic>)['name'] as String?
          : null,
      categoryName: json['categories'] != null
          ? (json['categories'] as Map<String, dynamic>)['name'] as String?
          : null,
      tenantContactPerson: _tenantField(json, 'contact_person'),
      tenantPhone: _tenantField(json, 'phone'),
      tenantEmail: _tenantField(json, 'email'),
      tenantAddress: _tenantField(json, 'address'),
      tenantCity: _tenantField(json, 'city'),
    );
  }

  static String? _tenantField(Map<String, dynamic> json, String key) =>
      json['tenants'] != null
          ? (json['tenants'] as Map<String, dynamic>)[key] as String?
          : null;
  final String id;
  final String tenantId;
  final String? categoryId;
  final String name;
  final String? description;
  final int capacity;
  final List<String> amenities;
  final List<String> images;
  final String timezone;
  final bool isActive;
  final String openTime; // local wall-clock 'HH:MM'
  final String closeTime; // local wall-clock 'HH:MM'
  final int minBookingMinutes;
  final int bufferMinutes;
  final bool customSelectorEnabled;
  final double? hourlyRate;
  final DateTime createdAt;

  // Joined fields
  final String? tenantName;
  final String? categoryName;
  final String? tenantContactPerson;
  final String? tenantPhone;
  final String? tenantEmail;
  final String? tenantAddress;
  final String? tenantCity;

  int get openHour => _hourOf(openTime, 7);
  int get openMinute => _minuteOf(openTime);
  int get closeHour => _hourOf(closeTime, 23);
  int get closeMinute => _minuteOf(closeTime);

  Map<String, dynamic> toJson() => {
        'tenant_id': tenantId,
        'category_id': categoryId,
        'name': name,
        'description': description,
        'capacity': capacity,
        'amenities': amenities,
        'images': images,
        'timezone': timezone,
        'is_active': isActive,
        'open_time': openTime,
        'close_time': closeTime,
        'min_booking_minutes': minBookingMinutes,
        'buffer_minutes': bufferMinutes,
        'custom_selector_enabled': customSelectorEnabled,
        'hourly_rate': hourlyRate,
      };

  // Postgres `time` comes back as 'HH:MM:SS'; keep just 'HH:MM'.
  static String _normalizeTime(String? raw, String fallback) {
    if (raw == null || raw.length < 5) return fallback;
    return raw.substring(0, 5);
  }

  static int _hourOf(String t, int fallback) =>
      int.tryParse(t.split(':').first) ?? fallback;

  static int _minuteOf(String t) {
    final parts = t.split(':');
    return parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  }
}
