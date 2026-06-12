import 'package:book_it/src/repositories/tenant_repository.dart';
import 'package:book_it/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TenantManager extends ConsumerWidget {
  const TenantManager({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tenantsAsync = ref.watch(allTenantsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tenants'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(allTenantsProvider),
          ),
        ],
      ),
      body: tenantsAsync.when(
        data: (tenants) {
          if (tenants.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.business_outlined,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No tenants registered',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(color: Colors.grey[500]),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: tenants.length,
            itemBuilder: (context, index) {
              final t = tenants[index];
              Color statusColor;
              switch (t.status) {
                case 'approved':
                  statusColor = AppTheme.successGreen;
                case 'suspended':
                  statusColor = AppTheme.errorRed;
                default:
                  statusColor = AppTheme.warningOrange;
              }

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ExpansionTile(
                  leading: CircleAvatar(
                    backgroundColor: statusColor.withValues(alpha: 0.12),
                    child: Icon(Icons.business, color: statusColor, size: 20),
                  ),
                  title: Text(t.name),
                  subtitle: Text(t.contactEmail),
                  trailing: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      t.status.toUpperCase(),
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (t.description != null)
                            Text(
                              t.description!,
                              style: theme.textTheme.bodyMedium,
                            ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(
                                Icons.phone,
                                size: 16,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 8),
                              Text(t.contactPhone ?? 'N/A'),
                              const SizedBox(width: 24),
                              Icon(
                                Icons.location_on,
                                size: 16,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 8),
                              Expanded(child: Text(t.address ?? 'N/A')),
                            ],
                          ),
                          const Divider(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              if (t.status == 'pending')
                                ElevatedButton.icon(
                                  onPressed: () async {
                                    await ref
                                        .read(tenantRepositoryProvider)
                                        .approveTenant(t.id);
                                    ref.invalidate(allTenantsProvider);
                                  },
                                  icon: const Icon(Icons.check, size: 16),
                                  label: const Text('Approve'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.successGreen,
                                  ),
                                ),
                              if (t.status != 'suspended')
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    await ref
                                        .read(tenantRepositoryProvider)
                                        .suspendTenant(t.id);
                                    ref.invalidate(allTenantsProvider);
                                  },
                                  icon: const Icon(Icons.block, size: 16),
                                  label: const Text('Suspend'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppTheme.errorRed,
                                    side: const BorderSide(
                                      color: AppTheme.errorRed,
                                    ),
                                  ),
                                ),
                              if (t.status == 'suspended')
                                ElevatedButton.icon(
                                  onPressed: () async {
                                    await ref
                                        .read(tenantRepositoryProvider)
                                        .approveTenant(t.id);
                                    ref.invalidate(allTenantsProvider);
                                  },
                                  icon: const Icon(Icons.restore, size: 16),
                                  label: const Text('Restore'),
                                ),
                            ],
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
    );
  }
}
