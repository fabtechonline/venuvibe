import 'package:book_it/src/core/supabase_config.dart';
import 'package:book_it/src/models/review.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final reviewRepositoryProvider = Provider<ReviewRepository>((ref) {
  return ReviewRepository(SupabaseConfig.client);
});

final resourceReviewsProvider =
    FutureProvider.family<List<Review>, String>((ref, resourceId) async {
  return ref.read(reviewRepositoryProvider).getResourceReviews(resourceId);
});

/// resource_id -> RatingSummary, for ratings on cards & detail.
final ratingsSummaryProvider =
    FutureProvider<Map<String, RatingSummary>>((ref) async {
  return ref.read(reviewRepositoryProvider).getRatingsSummary();
});

class ReviewRepository {
  ReviewRepository(this._client);
  final SupabaseClient _client;

  Future<List<Review>> getResourceReviews(String resourceId) async {
    final data = await _client
        .from('reviews')
        .select('*, profiles(full_name)')
        .eq('resource_id', resourceId)
        .order('created_at', ascending: false);
    return (data as List)
        .map((e) => Review.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, RatingSummary>> getRatingsSummary() async {
    final data = await _client.from('reviews').select('resource_id, rating');
    final byResource = <String, List<int>>{};
    for (final row in data as List) {
      final m = row as Map<String, dynamic>;
      (byResource[m['resource_id'] as String] ??= []).add(m['rating'] as int);
    }
    return byResource.map((id, ratings) {
      final avg = ratings.reduce((a, b) => a + b) / ratings.length;
      return MapEntry(id, RatingSummary(average: avg, count: ratings.length));
    });
  }

  /// Insert or update the current user's review for a resource. RLS requires
  /// the user to have a confirmed/completed booking on the resource.
  Future<void> upsertReview({
    required String resourceId,
    required int rating,
    String? comment,
  }) async {
    final userId = _client.auth.currentUser!.id;
    await _client.from('reviews').upsert(
      {
        'resource_id': resourceId,
        'user_id': userId,
        'rating': rating,
        'comment': comment,
      },
      onConflict: 'resource_id,user_id',
    );
  }
}
