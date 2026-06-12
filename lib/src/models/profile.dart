class Profile {
  const Profile({
    required this.id,
    required this.role,
    required this.createdAt,
    this.fullName,
    this.phone,
    this.email,
    this.avatarUrl,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      role: json['role'] as String? ?? 'user',
      fullName: json['full_name'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
  final String id;
  final String role;
  final String? fullName;
  final String? phone;
  final String? email;
  final String? avatarUrl;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role,
        'full_name': fullName,
        'phone': phone,
        'email': email,
        'avatar_url': avatarUrl,
      };

  Profile copyWith({
    String? fullName,
    String? phone,
    String? email,
    String? avatarUrl,
    String? role,
  }) {
    return Profile(
      id: id,
      role: role ?? this.role,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      createdAt: createdAt,
    );
  }

  bool get isAdmin => role == 'admin';
  bool get isTenant => role == 'tenant';
  bool get isUser => role == 'user';
}
