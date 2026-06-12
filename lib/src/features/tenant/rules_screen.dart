import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:venue_vibe/src/models/duration_model.dart';
import 'package:venue_vibe/src/repositories/resource_repository.dart';
import 'package:venue_vibe/src/theme/app_theme.dart';
import 'package:venue_vibe/src/utils/currency_formatter.dart';

class RulesScreen extends ConsumerStatefulWidget {
  const RulesScreen({super.key});

  @override
  ConsumerState<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends ConsumerState<RulesScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resourcesAsync = ref.watch(tenantResourcesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Pricing & Rules')),
      body: resourcesAsync.when(
        data: (resources) {
          if (resources.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.tune, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'Create a resource first to set pricing rules',
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(color: Colors.grey[500]),
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
              final durationsAsync = ref.watch(resourceDurationsProvider(r.id));

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              r.name,
                              style: theme.textTheme.titleMedium,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () =>
                                _showAddDurationDialog(context, r.id),
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Add Duration'),
                          ),
                        ],
                      ),
                      const Divider(),
                      durationsAsync.when(
                        data: (durs) {
                          if (durs.isEmpty) {
                            return Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                'No pricing tiers configured yet',
                                style: TextStyle(color: Colors.grey[500]),
                              ),
                            );
                          }
                          return Column(
                            children: durs
                                .map(
                                  (d) => ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: CircleAvatar(
                                      backgroundColor: AppTheme.primaryBlue
                                          .withValues(alpha: 0.1),
                                      child: const Icon(
                                        Icons.schedule,
                                        color: AppTheme.primaryBlue,
                                        size: 20,
                                      ),
                                    ),
                                    title: Text(d.label),
                                    subtitle: Text('${d.minutes} minutes'),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          formatPrice(
                                            d.price,
                                            ref.watch(
                                              currencyCodeProvider,
                                            ),
                                          ),
                                          style: const TextStyle(
                                            color: AppTheme.primaryBlue,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 16,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            color: AppTheme.errorRed,
                                            size: 20,
                                          ),
                                          onPressed: () async {
                                            await ref
                                                .read(
                                                  resourceRepositoryProvider,
                                                )
                                                .deleteDuration(d.id);
                                            ref.invalidate(
                                              resourceDurationsProvider(
                                                r.id,
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                                .toList(),
                          );
                        },
                        loading: () => const CircularProgressIndicator(),
                        error: (e, _) => Text('$e'),
                      ),
                    ],
                  ),
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

  void _showAddDurationDialog(BuildContext context, String resourceId) {
    final labelCtrl = TextEditingController();
    final minsCtrl = TextEditingController();
    final priceCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Duration'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: labelCtrl,
              decoration: const InputDecoration(
                labelText: 'Label (e.g. "1 Hour")',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: minsCtrl,
              decoration: const InputDecoration(
                labelText: 'Minutes',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: priceCtrl,
              decoration: InputDecoration(
                labelText: 'Price',
                prefixText:
                    '${currencySymbol(ref.read(currencyCodeProvider))} ',
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final duration = DurationModel(
                id: '',
                resourceId: resourceId,
                label: labelCtrl.text,
                minutes: int.tryParse(minsCtrl.text) ?? 60,
                price: double.tryParse(priceCtrl.text) ?? 0,
                createdAt: DateTime.now(),
              );
              await ref
                  .read(resourceRepositoryProvider)
                  .createDuration(duration);
              ref.invalidate(resourceDurationsProvider(resourceId));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}
