class Category {
  const Category({
    required this.id,
    required this.name,
    required this.createdAt,
    this.icon,
    this.description,
    this.isActive = true,
    this.sortOrder = 0,
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'] as String,
      name: json['name'] as String,
      icon: json['icon'] as String?,
      description: json['description'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      sortOrder: json['sort_order'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
  final String id;
  final String name;
  final String? icon;
  final String? description;
  final bool isActive;
  final int sortOrder;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'name': name,
        'icon': icon,
        'description': description,
        'is_active': isActive,
        'sort_order': sortOrder,
      };

  Category copyWith({
    String? id,
    String? name,
    String? icon,
    String? description,
    bool? isActive,
    int? sortOrder,
    DateTime? createdAt,
  }) {
    return Category(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      description: description ?? this.description,
      isActive: isActive ?? this.isActive,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
