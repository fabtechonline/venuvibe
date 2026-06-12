import 'package:book_it/src/models/resource.dart';
import 'package:book_it/src/repositories/favorite_repository.dart';
import 'package:book_it/src/repositories/notification_repository.dart';
import 'package:book_it/src/repositories/resource_repository.dart';
import 'package:book_it/src/repositories/review_repository.dart';
import 'package:book_it/src/theme/app_theme.dart';
import 'package:book_it/src/widgets/star_rating.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  String? _selectedCategoryId;
  bool _favoritesOnly = false;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categoriesAsync = ref.watch(categoriesProvider);
    final resourcesAsync = _selectedCategoryId != null
        ? ref.watch(resourcesByCategoryProvider(_selectedCategoryId!))
        : ref.watch(allResourcesProvider);
    final unreadCount = ref.watch(unreadNotificationCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/venue_vibe_logo.png', height: 32),
            const SizedBox(width: 8),
            RichText(
              text: const TextSpan(
                children: [
                  TextSpan(
                    text: 'Venue ',
                    style: TextStyle(
                      color: Color(0xFF1B2A4A),
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                    ),
                  ),
                  TextSpan(
                    text: 'Vibe',
                    style: TextStyle(
                      color: AppTheme.primaryBlue,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: unreadCount > 0,
              label: Text('$unreadCount'),
              child: const Icon(Icons.notifications_outlined),
            ),
            onPressed: () => context.push('/notifications'),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          // ─── Search Bar ───
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search spaces, venues, facilities...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                        )
                      : null,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),

          // ─── Category Chips ───
          SliverToBoxAdapter(
            child: categoriesAsync.when(
              data: (categories) => SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        avatar: Icon(
                          _favoritesOnly
                              ? Icons.favorite
                              : Icons.favorite_border,
                          size: 18,
                          color: AppTheme.errorRed,
                        ),
                        label: const Text('Favorites'),
                        selected: _favoritesOnly,
                        onSelected: (v) => setState(() => _favoritesOnly = v),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: const Text('All'),
                        selected: _selectedCategoryId == null,
                        onSelected: (_) =>
                            setState(() => _selectedCategoryId = null),
                      ),
                    ),
                    ...categories.map(
                      (c) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          avatar: Icon(_getCategoryIcon(c.name), size: 18),
                          label: Text(c.name),
                          selected: _selectedCategoryId == c.id,
                          onSelected: (_) =>
                              setState(() => _selectedCategoryId = c.id),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              loading: () => const SizedBox(
                height: 48,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text('$e'),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 12)),

          // ─── Resources Grid ───
          resourcesAsync.when(
            data: (resources) {
              final favIds =
                  ref.watch(favoriteIdsProvider).valueOrNull ?? <String>{};
              final query = _searchController.text.toLowerCase();
              final filtered = resources.where((r) {
                final matchesSearch =
                    query.isEmpty || r.name.toLowerCase().contains(query);
                final matchesFav = !_favoritesOnly || favIds.contains(r.id);
                return matchesSearch && matchesFav;
              }).toList();

              if (filtered.isEmpty) {
                return SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.search_off,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No spaces found',
                          style: theme.textTheme.titleLarge
                              ?.copyWith(color: Colors.grey[500]),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Try adjusting your filters',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: Colors.grey[400]),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) =>
                        _ResourceCard(resource: filtered[index]),
                    childCount: filtered.length,
                  ),
                ),
              );
            },
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => SliverFillRemaining(
              child: Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getCategoryIcon(String name) {
    switch (name.toLowerCase()) {
      case 'sports':
        return Icons.sports_tennis;
      case 'events & parties':
        return Icons.celebration;
      case 'business & co-working':
        return Icons.business_center;
      case 'health & wellness':
        return Icons.spa;
      default:
        return Icons.category;
    }
  }
}

class _ResourceCard extends ConsumerWidget {
  const _ResourceCard({required this.resource});
  final Resource resource;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final rating = ref.watch(ratingsSummaryProvider).valueOrNull?[resource.id];
    final isFav = (ref.watch(favoriteIdsProvider).valueOrNull ?? <String>{})
        .contains(resource.id);
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => context.push('/resource/${resource.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Container(
                  height: 180,
                  width: double.infinity,
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
                            size: 48,
                            color: AppTheme.primaryBlue.withValues(alpha: 0.3),
                          ),
                        )
                      : null,
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Material(
                    color: Colors.white.withValues(alpha: 0.85),
                    shape: const CircleBorder(),
                    child: IconButton(
                      iconSize: 20,
                      icon: Icon(
                        isFav ? Icons.favorite : Icons.favorite_border,
                        color: AppTheme.errorRed,
                      ),
                      onPressed: () async {
                        await ref
                            .read(favoriteRepositoryProvider)
                            .toggleFavorite(
                              resource.id,
                              makeFavorite: !isFav,
                            );
                        ref
                          ..invalidate(favoriteIdsProvider)
                          ..invalidate(favoriteResourcesProvider);
                      },
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          resource.name,
                          style: theme.textTheme.titleLarge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (resource.categoryName != null)
                        Chip(
                          label: Text(
                            resource.categoryName!,
                            style: const TextStyle(fontSize: 11),
                          ),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                  if (resource.tenantName != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      resource.tenantName!,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  if (rating != null) ...[
                    const SizedBox(height: 6),
                    StarRating(
                      rating: rating.average,
                      count: rating.count,
                      size: 14,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.people_outline,
                        size: 16,
                        color: Colors.grey[600],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Capacity: ${resource.capacity}',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(width: 16),
                      if (resource.amenities.isNotEmpty) ...[
                        Icon(
                          Icons.check_circle_outline,
                          size: 16,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${resource.amenities.length} amenities',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
