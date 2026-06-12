import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:venue_vibe/src/repositories/resource_repository.dart';
import 'package:venue_vibe/src/repositories/tenant_repository.dart';
import 'package:venue_vibe/src/theme/app_theme.dart';

class ResourceListScreen extends ConsumerWidget {
  const ResourceListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final resourcesAsync = ref.watch(tenantResourcesProvider);
    final limit = ref.watch(tenantResourceLimitProvider).valueOrNull;
    final used = resourcesAsync.valueOrNull?.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Resources'),
        actions: [
          if (used != null && limit != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Chip(
                  label: Text('$used / $limit'),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: used >= limit
                      ? AppTheme.warningOrange.withValues(alpha: 0.15)
                      : null,
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(tenantResourcesProvider),
          ),
        ],
      ),
      body: resourcesAsync.when(
        data: (resources) {
          if (resources.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.meeting_room_outlined,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No resources yet',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(color: Colors.grey[500]),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () => context.push('/tenant/resources/edit'),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Resource'),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: resources.length,
            itemBuilder: (context, index) {
              final r = resources[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                      leading: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          image: r.images.isNotEmpty
                              ? DecorationImage(
                                  image: NetworkImage(r.images.first),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: r.images.isEmpty
                            ? Icon(
                                Icons.meeting_room,
                                color:
                                    AppTheme.primaryBlue.withValues(alpha: 0.5),
                              )
                            : null,
                      ),
                      title: Text(
                        r.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'Capacity ${r.capacity} · '
                        '${r.openTime} – ${r.closeTime}',
                      ),
                      trailing: Switch(
                        value: r.isActive,
                        onChanged: (v) async {
                          await ref
                              .read(resourceRepositoryProvider)
                              .toggleResource(r.id, v);
                          ref
                            ..invalidate(tenantResourcesProvider)
                            ..invalidate(allResourcesProvider);
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                      child: OverflowBar(
                        children: [
                          TextButton.icon(
                            onPressed: () => context.push(
                              '/tenant/resources/edit',
                              extra: r.id,
                            ),
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            label: const Text('Edit'),
                          ),
                          TextButton.icon(
                            onPressed: () => context.push(
                              '/tenant/scheduler',
                              extra: r.id,
                            ),
                            icon: const Icon(
                              Icons.calendar_month_outlined,
                              size: 18,
                            ),
                            label: const Text('Scheduler'),
                          ),
                          TextButton.icon(
                            onPressed: () => context.push(
                              '/tenant/rules',
                              extra: r.id,
                            ),
                            icon: const Icon(Icons.sell_outlined, size: 18),
                            label: const Text('Pricing'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/tenant/resources/edit'),
        icon: const Icon(Icons.add),
        label: const Text('Add Resource'),
      ),
    );
  }
}
