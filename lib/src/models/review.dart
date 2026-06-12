class Review {
  const Review({
    required this.id,
    required this.resourceId,
    required this.userId,
    required this.rating,
    required this.createdAt,
    this.comment,
    this.userName,
  });

  factory Review.fromJson(Map<String, dynamic> json) {
    return Review(
      id: json['id'] as String,
      resourceId: json['resource_id'] as String,
      userId: json['user_id'] as String,
      rating: json['rating'] as int,
      comment: json['comment'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      userName: json['profiles'] != null
          ? (json['profiles'] as Map<String, dynamic>)['full_name'] as String?
          : null,
    );
  }

  final String id;
  final String resourceId;
  final String userId;
  final int rating;
  final String? comment;
  final DateTime createdAt;
  final String? userName;
}

/// Aggregate rating for a resource.
class RatingSummary {
  const RatingSummary({required this.average, required this.count});
  final double average;
  final int count;
}
