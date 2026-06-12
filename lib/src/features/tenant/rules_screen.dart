import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:venue_vibe/src/models/addon.dart';
import 'package:venue_vibe/src/models/duration_model.dart';
import 'package:venue_vibe/src/models/resource.dart';
import 'package:venue_vibe/src/repositories/resource_repository.dart';
import 'package:venue_vibe/src/theme/app_theme.dart';
import 'package:venue_vibe/src/utils/currency_formatter.dart';

class RulesScreen extends ConsumerStatefulWidget {
  const RulesScreen({super.key, this.initialResourceId});
  final String? initialResourceId;

  @override
  ConsumerState<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends ConsumerState<RulesScreen> {
  String? _filterId;

  @override
  void initState() {
    super.initState();
    _filterId = widget.initialResourceId;
  }

  @override
  void didUpdateWidget(RulesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialResourceId != oldWidget.initialResourceId &&
        widget.initialResourceId != null) {
      _filterId = widget.initialResourceId;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resourcesAsync = ref.watch(tenantResourcesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Pricing & Rules')),
      body: resourcesAsync.when(
        data: (allResources) {
          final matches = allResources.where((r) => r.id == _filterId).toList();
          // Fall back to the full list if the filtered id is unknown.
          final filterName = matches.isEmpty ? null : matches.first.name;
          final resources = matches.isEmpty ? allResources : matches;
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

          final list = ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: resources.length,
            itemBuilder: (context, index) {
              final r = resources[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.name,
                        style: theme.textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Divider(),
                      _SectionHeader(
                        title: 'Pricing tiers',
                        actionLabel: 'Add Duration',
                        onAction: () => _showDurationDialog(context, r.id),
                      ),
                      _DurationList(
                        resourceId: r.id,
                        onEdit: (d) {
                          _showDurationDialog(context, r.id, existing: d);
                        },
                      ),
                      const Divider(),
                      _CustomBookingSection(resource: r),
                      const Divider(),
                      _SectionHeader(
                        title: 'Add-ons',
                        actionLabel: 'Add Add-on',
                        onAction: () => _showAddonDialog(context, r.id),
                      ),
                      _AddonList(
                        resourceId: r.id,
                        onEdit: (a) =>
                            _showAddonDialog(context, r.id, existing: a),
                      ),
                    ],
                  ),
                ),
              );
            },
          );

          if (filterName == null) return list;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: InputChip(
                  avatar: const Icon(Icons.filter_alt, size: 18),
                  label: Text(filterName),
                  onDeleted: () => setState(() => _filterId = null),
                  deleteIcon: const Icon(Icons.close, size: 18),
                ),
              ),
              Expanded(child: list),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }

  void _showDurationDialog(
    BuildContext context,
    String resourceId, {
    DurationModel? existing,
  }) {
    final labelCtrl = TextEditingController(text: existing?.label ?? '');
    final minsCtrl =
        TextEditingController(text: existing?.minutes.toString() ?? '');
    final priceCtrl =
        TextEditingController(text: existing?.price.toStringAsFixed(2) ?? '');

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Add Duration' : 'Edit Duration'),
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
              final repo = ref.read(resourceRepositoryProvider);
              if (existing == null) {
                await repo.createDuration(
                  DurationModel(
                    id: '',
                    resourceId: resourceId,
                    label: labelCtrl.text,
                    minutes: int.tryParse(minsCtrl.text) ?? 60,
                    price: double.tryParse(priceCtrl.text) ?? 0,
                    createdAt: DateTime.now(),
                  ),
                );
              } else {
                await repo.updateDuration(
                  existing.copyWith(
                    label: labelCtrl.text,
                    minutes: int.tryParse(minsCtrl.text) ?? existing.minutes,
                    price: double.tryParse(priceCtrl.text) ?? existing.price,
                  ),
                );
              }
              ref.invalidate(resourceDurationsProvider(resourceId));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(existing == null ? 'Add' : 'Save'),
          ),
        ],
      ),
    );
  }

  void _showAddonDialog(
    BuildContext context,
    String resourceId, {
    ResourceAddon? existing,
  }) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final priceCtrl =
        TextEditingController(text: existing?.price.toStringAsFixed(2) ?? '');
    final qtyCtrl =
        TextEditingController(text: (existing?.maxQty ?? 10).toString());

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Add Add-on' : 'Edit Add-on'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Name (e.g. "Racquet hire")',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: priceCtrl,
              decoration: InputDecoration(
                labelText: 'Price per unit',
                prefixText:
                    '${currencySymbol(ref.read(currencyCodeProvider))} ',
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: qtyCtrl,
              decoration: const InputDecoration(
                labelText: 'Max quantity per booking',
              ),
              keyboardType: TextInputType.number,
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
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              final repo = ref.read(resourceRepositoryProvider);
              final addon = ResourceAddon(
                id: existing?.id ?? '',
                resourceId: resourceId,
                name: name,
                price: double.tryParse(priceCtrl.text) ?? 0,
                maxQty: (int.tryParse(qtyCtrl.text) ?? 10).clamp(1, 999),
              );
              if (existing == null) {
                await repo.createAddon(addon);
              } else {
                await repo.updateAddon(addon);
              }
              ref.invalidate(resourceAddonsProvider(resourceId));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(existing == null ? 'Add' : 'Save'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });
  final String title;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        TextButton.icon(
          onPressed: onAction,
          icon: const Icon(Icons.add, size: 16),
          label: Text(actionLabel),
        ),
      ],
    );
  }
}

class _DurationList extends ConsumerWidget {
  const _DurationList({required this.resourceId, required this.onEdit});
  final String resourceId;
  final ValueChanged<DurationModel> onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final durationsAsync = ref.watch(resourceDurationsProvider(resourceId));
    return durationsAsync.when(
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
                    backgroundColor:
                        AppTheme.primaryBlue.withValues(alpha: 0.1),
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
                        formatPrice(d.price, ref.watch(currencyCodeProvider)),
                        style: const TextStyle(
                          color: AppTheme.primaryBlue,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        onPressed: () => onEdit(d),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: AppTheme.errorRed,
                          size: 20,
                        ),
                        onPressed: () async {
                          await ref
                              .read(resourceRepositoryProvider)
                              .deleteDuration(d.id);
                          ref.invalidate(
                            resourceDurationsProvider(resourceId),
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
    );
  }
}

/// Hourly rate + on/off switch for the customer-facing custom time selector.
class _CustomBookingSection extends ConsumerStatefulWidget {
  const _CustomBookingSection({required this.resource});
  final Resource resource;

  @override
  ConsumerState<_CustomBookingSection> createState() =>
      _CustomBookingSectionState();
}

class _CustomBookingSectionState extends ConsumerState<_CustomBookingSection> {
  late final TextEditingController _rateCtrl;
  late bool _enabled;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _rateCtrl = TextEditingController(
      text: widget.resource.hourlyRate?.toStringAsFixed(2) ?? '',
    );
    _enabled = widget.resource.customSelectorEnabled;
  }

  @override
  void dispose() {
    _rateCtrl.dispose();
    super.dispose();
  }

  Future<void> _save({required bool enabled}) async {
    final rate = double.tryParse(_rateCtrl.text);
    if (enabled && rate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Set an hourly rate before enabling custom bookings.'),
        ),
      );
      return;
    }
    setState(() {
      _saving = true;
      _enabled = enabled;
    });
    try {
      await ref.read(resourceRepositoryProvider).setCustomBookingConfig(
            widget.resource.id,
            enabled: enabled,
            hourlyRate: rate,
          );
      ref
        ..invalidate(tenantResourcesProvider)
        ..invalidate(resourceProvider(widget.resource.id));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final symbol = currencySymbol(ref.watch(currencyCodeProvider));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Custom bookings',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          'Let customers request their own date & time range at an hourly '
          'rate. You approve every request before they pay.',
          style: TextStyle(color: Colors.grey[600], fontSize: 12),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _rateCtrl,
                decoration: InputDecoration(
                  labelText: 'Hourly rate',
                  prefixText: '$symbol ',
                  isDense: true,
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onSubmitted: (_) => _save(enabled: _enabled),
              ),
            ),
            const SizedBox(width: 8),
            if (_saving)
              const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Switch(
                value: _enabled,
                onChanged: (v) => _save(enabled: v),
              ),
          ],
        ),
      ],
    );
  }
}

class _AddonList extends ConsumerWidget {
  const _AddonList({required this.resourceId, required this.onEdit});
  final String resourceId;
  final ValueChanged<ResourceAddon> onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addonsAsync = ref.watch(resourceAddonsProvider(resourceId));
    final cc = ref.watch(currencyCodeProvider);
    return addonsAsync.when(
      data: (addons) {
        if (addons.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'No add-ons yet (e.g. racquet hire, table hire)',
              style: TextStyle(color: Colors.grey[500]),
            ),
          );
        }
        return Column(
          children: [
            for (final a in addons)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name on its own line, controls on the row below.
                    Text(
                      a.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${formatPrice(a.price, cc)} · '
                            'Max ${a.maxQty} per booking',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 13,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          onPressed: () => onEdit(a),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: AppTheme.errorRed,
                            size: 20,
                          ),
                          onPressed: () async {
                            await ref
                                .read(resourceRepositoryProvider)
                                .deleteAddon(a.id);
                            ref.invalidate(resourceAddonsProvider(resourceId));
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        );
      },
      loading: () => const CircularProgressIndicator(),
      error: (e, _) => Text('$e'),
    );
  }
}
