import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:venue_vibe/src/repositories/favorite_repository.dart';
import 'package:venue_vibe/src/repositories/resource_repository.dart';
import 'package:venue_vibe/src/repositories/review_repository.dart';
import 'package:venue_vibe/src/theme/app_theme.dart';
import 'package:venue_vibe/src/utils/currency_formatter.dart';
import 'package:venue_vibe/src/widgets/star_rating.dart';

class ResourceDetailScreen extends ConsumerWidget {
  const ResourceDetailScreen({required this.resourceId, super.key});
  final String resourceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return FutureBuilder(
      future: ref.read(resourceRepositoryProvider).getResource(resourceId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(child: Text('Error: ${snapshot.error}')),
          );
        }

        final resource = snapshot.data!;
        final durations = ref.watch(resourceDurationsProvider(resourceId));
        final favIds = ref.watch(favoriteIdsProvider).valueOrNull ?? <String>{};
        final isFav = favIds.contains(resourceId);
        final rating =
            ref.watch(ratingsSummaryProvider).valueOrNull?[resourceId];
        final reviewsAsync = ref.watch(resourceReviewsProvider(resourceId));

        return Scaffold(
          body: CustomScrollView(
            slivers: [
              // ─── Hero Image ───
              SliverAppBar(
                expandedHeight: 280,
                pinned: true,
                actions: [
                  IconButton(
                    icon: Icon(
                      isFav ? Icons.favorite : Icons.favorite_border,
                      color: isFav ? AppTheme.errorRed : Colors.white,
                    ),
                    onPressed: () async {
                      await ref
                          .read(favoriteRepositoryProvider)
                          .toggleFavorite(resourceId, makeFavorite: !isFav);
                      ref
                        ..invalidate(favoriteIdsProvider)
                        ..invalidate(favoriteResourcesProvider);
                    },
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue.withValues(alpha: 0.08),
                      image: resource.images.isNotEmpty
                          ? DecorationImage(
                              image: NetworkImage(resource.images.first),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: resource.images.isEmpty
                        ? Center(
                            child: Icon(
                              Icons.meeting_room,
                              size: 80,
                              color:
                                  AppTheme.primaryBlue.withValues(alpha: 0.3),
                            ),
                          )
                        : null,
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ─── Title & Category ───
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              resource.name,
                              style: theme.textTheme.headlineLarge,
                            ),
                          ),
                          if (resource.categoryName != null)
                            Chip(
                              label: Text(resource.categoryName!),
                              backgroundColor:
                                  AppTheme.primaryBlue.withValues(alpha: 0.1),
                            ),
                        ],
                      ),

                      if (resource.tenantName != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'by ${resource.tenantName}',
                          style: theme.textTheme.bodyLarge
                              ?.copyWith(color: Colors.grey[600]),
                        ),
                      ],

                      if (rating != null) ...[
                        const SizedBox(height: 8),
                        StarRating(
                          rating: rating.average,
                          size: 18,
                          count: rating.count,
                        ),
                      ],

                      const SizedBox(height: 20),

                      // ─── Description ───
                      if (resource.description != null) ...[
                        Text(
                          resource.description!,
                          style: theme.textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 20),
                      ],

                      // ─── Info Row ───
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _InfoItem(
                              icon: Icons.people_outline,
                              label: 'Capacity',
                              value: '${resource.capacity}',
                            ),
                            _InfoItem(
                              icon: Icons.access_time,
                              label: 'Timezone',
                              value: resource.timezone,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // ─── Venue Contact ───
                      if (resource.tenantContactPerson != null ||
                          resource.tenantPhone != null ||
                          resource.tenantAddress != null) ...[
                        Text(
                          'Venue Contact',
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (resource.tenantContactPerson != null &&
                                  resource.tenantContactPerson!.isNotEmpty)
                                _ContactRow(
                                  icon: Icons.person_outline,
                                  value: resource.tenantContactPerson!,
                                ),
                              if (resource.tenantPhone != null &&
                                  resource.tenantPhone!.isNotEmpty)
                                _ContactRow(
                                  icon: Icons.phone_outlined,
                                  value: resource.tenantPhone!,
                                ),
                              if (resource.tenantEmail != null &&
                                  resource.tenantEmail!.isNotEmpty)
                                _ContactRow(
                                  icon: Icons.email_outlined,
                                  value: resource.tenantEmail!,
                                ),
                              if (resource.tenantAddress != null &&
                                  resource.tenantAddress!.isNotEmpty)
                                _ContactRow(
                                  icon: Icons.location_on_outlined,
                                  value: [
                                    resource.tenantAddress,
                                    resource.tenantCity,
                                  ]
                                      .where((s) => s != null && s.isNotEmpty)
                                      .join(', '),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // ─── Amenities ───
                      if (resource.amenities.isNotEmpty) ...[
                        Text('Amenities', style: theme.textTheme.titleLarge),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: resource.amenities
                              .map(
                                (a) => Chip(
                                  avatar: Icon(_getAmenityIcon(a), size: 18),
                                  label: Text(a),
                                ),
                              )
                              .toList(),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // ─── Available Durations ───
                      Text('Pricing', style: theme.textTheme.titleLarge),
                      const SizedBox(height: 12),
                      durations.when(
                        data: (durs) => Column(
                          children: durs
                              .map(
                                (d) => Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.grey.shade200,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.schedule,
                                        color: AppTheme.primaryBlue,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          d.label,
                                          style: theme.textTheme.titleMedium,
                                        ),
                                      ),
                                      Text(
                                        formatPrice(
                                          d.price,
                                          ref.watch(currencyCodeProvider),
                                        ),
                                        style: theme.textTheme.titleLarge
                                            ?.copyWith(
                                          color: AppTheme.primaryBlue,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                        loading: () => const CircularProgressIndicator(),
                        error: (e, _) => Text('Error: $e'),
                      ),

                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Text('Reviews', style: theme.textTheme.titleLarge),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () => showDialog<void>(
                              context: context,
                              builder: (_) =>
                                  _WriteReviewDialog(resourceId: resourceId),
                            ),
                            icon: const Icon(
                              Icons.rate_review_outlined,
                              size: 18,
                            ),
                            label: const Text('Write a review'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      reviewsAsync.when(
                        data: (reviews) {
                          if (reviews.isEmpty) {
                            return Text(
                              'No reviews yet — be the first.',
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(color: Colors.grey[500]),
                            );
                          }
                          return Column(
                            children: [
                              for (final r in reviews)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.grey.shade200,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              r.userName ?? 'Guest',
                                              style: theme.textTheme.titleSmall,
                                            ),
                                          ),
                                          StarRating(
                                            rating: r.rating.toDouble(),
                                            size: 14,
                                          ),
                                        ],
                                      ),
                                      if (r.comment != null &&
                                          r.comment!.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(r.comment!),
                                      ],
                                      const SizedBox(height: 4),
                                      Text(
                                        timeago.format(r.createdAt),
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(color: Colors.grey[500]),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          );
                        },
                        loading: () => const Padding(
                          padding: EdgeInsets.all(8),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                        error: (e, _) => Text('Error: $e'),
                      ),

                      const SizedBox(height: 80),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // ─── Book Now Button ───
          bottomNavigationBar: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () =>
                      context.push('/resource/$resourceId/availability'),
                  icon: const Icon(Icons.calendar_month),
                  label: const Text('View Availability & Book'),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  IconData _getAmenityIcon(String amenity) {
    final lower = amenity.toLowerCase();
    if (lower.contains('wifi')) return Icons.wifi;
    if (lower.contains('park')) return Icons.local_parking;
    if (lower.contains('ac') || lower.contains('air')) return Icons.ac_unit;
    if (lower.contains('shower')) return Icons.shower;
    if (lower.contains('locker')) return Icons.lock;
    return Icons.check_circle_outline;
  }
}

class _InfoItem extends StatelessWidget {
  const _InfoItem({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: AppTheme.primaryBlue),
        const SizedBox(height: 4),
        Text(
          value,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _WriteReviewDialog extends ConsumerStatefulWidget {
  const _WriteReviewDialog({required this.resourceId});
  final String resourceId;

  @override
  ConsumerState<_WriteReviewDialog> createState() => _WriteReviewDialogState();
}

class _WriteReviewDialogState extends ConsumerState<_WriteReviewDialog> {
  int _rating = 5;
  final _commentController = TextEditingController();
  bool _isSaving = false;
  String? _error;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await ref.read(reviewRepositoryProvider).upsertReview(
            resourceId: widget.resourceId,
            rating: _rating,
            comment: _commentController.text.trim(),
          );
      ref
        ..invalidate(resourceReviewsProvider(widget.resourceId))
        ..invalidate(ratingsSummaryProvider);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      setState(() {
        _isSaving = false;
        _error = 'You can review a space after a completed booking there.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Write a review'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          StarInput(
            value: _rating,
            onChanged: (v) => setState(() => _rating = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _commentController,
            decoration: const InputDecoration(labelText: 'Comment (optional)'),
            maxLines: 3,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: AppTheme.errorRed)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _submit,
          child: _isSaving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Submit'),
        ),
      ],
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.icon, required this.value});
  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey[600]),
          const SizedBox(width: 10),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
