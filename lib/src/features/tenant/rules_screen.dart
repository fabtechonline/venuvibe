import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:venue_vibe/src/models/addon.dart';
import 'package:venue_vibe/src/models/duration_model.dart';
import 'package:venue_vibe/src/models/pricing_period.dart';
import 'package:venue_vibe/src/models/resource.dart';
import 'package:venue_vibe/src/repositories/resource_repository.dart';
import 'package:venue_vibe/src/theme/app_theme.dart';
import 'package:venue_vibe/src/utils/currency_formatter.dart';
import 'package:venue_vibe/src/utils/pricing_periods.dart';

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
                        title: 'Pricing seasons',
                        actionLabel: 'Add Season',
                        onAction: () => _showPeriodDialog(context, r.id),
                      ),
                      _PeriodList(
                        resourceId: r.id,
                        onEditPeriod: (p) =>
                            _showPeriodDialog(context, r.id, existing: p),
                        onAddTier: (p) =>
                            _showDurationDialog(context, r.id, periodId: p.id),
                        onEditTier: (p, d) => _showDurationDialog(
                          context,
                          r.id,
                          periodId: p.id,
                          existing: d,
                        ),
                      ),
                      if (allResources.length > 1)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () => _showCopyDialog(
                              context,
                              r,
                              allResources.where((o) => o.id != r.id).toList(),
                            ),
                            icon: const Icon(Icons.copy_all_outlined, size: 16),
                            label: const Text('Copy from another resource'),
                          ),
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

  void _showPeriodDialog(
    BuildContext context,
    String resourceId, {
    PricingPeriod? existing,
  }) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final rateCtrl = TextEditingController(
      text: existing?.hourlyRate?.toStringAsFixed(2) ?? '',
    );
    var start = existing?.startDate;
    var end = existing?.endDate;
    String? error;
    final df = DateFormat('d MMM y');

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> pickDate({required bool isStart}) async {
            final picked = await showDatePicker(
              context: ctx,
              initialDate: (isStart ? start : end) ?? DateTime.now(),
              firstDate: DateTime.now().subtract(const Duration(days: 365)),
              lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
            );
            if (picked != null) {
              setDialogState(() {
                if (isStart) {
                  start = dateOnly(picked);
                } else {
                  end = dateOnly(picked);
                }
              });
            }
          }

          Future<void> save() async {
            final name = nameCtrl.text.trim();
            if (name.isEmpty || start == null || end == null) {
              setDialogState(
                () => error = 'Name, start and end dates are required.',
              );
              return;
            }
            if (end!.isBefore(start!)) {
              setDialogState(
                () => error = 'End date must be on or after the start date.',
              );
              return;
            }
            final rateText = rateCtrl.text.trim();
            final rate = rateText.isEmpty ? null : double.tryParse(rateText);
            if (rateText.isNotEmpty && rate == null) {
              setDialogState(
                () => error = 'Hourly rate must be a number, or left empty.',
              );
              return;
            }
            final repo = ref.read(resourceRepositoryProvider);
            final candidate = PricingPeriod(
              id: existing?.id ?? '',
              resourceId: resourceId,
              name: name,
              startDate: start!,
              endDate: end!,
              hourlyRate: rate,
            );
            try {
              final others = (await repo.getPricingPeriods(resourceId))
                  .where((p) => p.id != existing?.id)
                  .toList();
              if (findOverlapConflicts(others, [candidate]).isNotEmpty) {
                setDialogState(
                  () => error = 'These dates overlap an existing season.',
                );
                return;
              }
              if (existing == null) {
                await repo.createPricingPeriod(candidate);
              } else {
                await repo.updatePricingPeriod(candidate);
              }
            } on PostgrestException catch (e) {
              setDialogState(
                () => error = e.code == '23P01'
                    ? 'These dates overlap an existing season.'
                    : e.message,
              );
              return;
            }
            ref
              ..invalidate(resourcePricingPeriodsProvider(resourceId))
              ..invalidate(resourceDurationsProvider(resourceId));
            if (ctx.mounted) Navigator.pop(ctx);
          }

          return AlertDialog(
            title: Text(existing == null ? 'Add Season' : 'Edit Season'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Name (e.g. "Summer 2026")',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => pickDate(isStart: true),
                          icon: const Icon(Icons.event, size: 16),
                          label: Text(
                            start == null ? 'Start date' : df.format(start!),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => pickDate(isStart: false),
                          icon: const Icon(Icons.event, size: 16),
                          label: Text(
                            end == null ? 'End date' : df.format(end!),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: rateCtrl,
                    decoration: InputDecoration(
                      labelText: 'Hourly rate for this season (optional)',
                      prefixText:
                          '${currencySymbol(ref.read(currencyCodeProvider))} ',
                      helperText: "Empty = the venue's default hourly rate",
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      error!,
                      style: const TextStyle(
                        color: AppTheme.errorRed,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: save,
                child: Text(existing == null ? 'Add' : 'Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showCopyDialog(
    BuildContext context,
    Resource target,
    List<Resource> others,
  ) {
    var sourceId = others.first.id;
    String? error;
    var copying = false;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> copy() async {
            setDialogState(() {
              copying = true;
              error = null;
            });
            try {
              await ref.read(resourceRepositoryProvider).copyPricingFrom(
                    sourceResourceId: sourceId,
                    targetResourceId: target.id,
                  );
            } on PricingCopyException catch (e) {
              setDialogState(() {
                copying = false;
                error = e.message;
              });
              return;
            } on PostgrestException catch (e) {
              setDialogState(() {
                copying = false;
                error = e.code == '23P01'
                    ? 'A copied season overlaps an existing one.'
                    : e.message;
              });
              return;
            }
            ref
              ..invalidate(resourcePricingPeriodsProvider(target.id))
              ..invalidate(resourceDurationsProvider(target.id));
            if (ctx.mounted) Navigator.pop(ctx);
          }

          return AlertDialog(
            title: Text('Copy seasons to ${target.name}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: sourceId,
                  decoration: const InputDecoration(labelText: 'Copy from'),
                  items: others
                      .map(
                        (r) => DropdownMenuItem(
                          value: r.id,
                          child: Text(r.name, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setDialogState(() => sourceId = v);
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  'Copies every season — dates, pricing tiers and hourly '
                  "overrides. Seasons without their own rate use this venue's "
                  'default hourly rate.',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    error!,
                    style: const TextStyle(
                      color: AppTheme.errorRed,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: copying ? null : copy,
                child: copying
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Copy'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showDurationDialog(
    BuildContext context,
    String resourceId, {
    required String periodId,
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
                    periodId: periodId,
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
              ref
                ..invalidate(periodDurationsProvider(periodId))
                ..invalidate(resourceDurationsProvider(resourceId));
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

/// Seasons of one resource: gap warning, then an expandable card per season
/// holding its tier list.
class _PeriodList extends ConsumerWidget {
  const _PeriodList({
    required this.resourceId,
    required this.onEditPeriod,
    required this.onAddTier,
    required this.onEditTier,
  });
  final String resourceId;
  final ValueChanged<PricingPeriod> onEditPeriod;
  final ValueChanged<PricingPeriod> onAddTier;
  final void Function(PricingPeriod period, DurationModel tier) onEditTier;

  static final _df = DateFormat('d MMM y');

  String _fmtGap(PricingGap g) => g.start == g.end
      ? _df.format(g.start)
      : '${_df.format(g.start)} – ${_df.format(g.end)}';

  String _periodSubtitle(PricingPeriod p, String cc) {
    final dates = '${_df.format(p.startDate)} – ${_df.format(p.endDate)}';
    if (p.hourlyRate == null) return dates;
    return '$dates\nCustom rate: ${formatPrice(p.hourlyRate!, cc)}/hour';
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    PricingPeriod p,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete season?'),
        content: Text(
          'This removes "${p.name}" and its pricing tiers. Customers will '
          'not be able to book dates only this season covers.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorRed,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(resourceRepositoryProvider).deletePricingPeriod(p.id);
    ref
      ..invalidate(resourcePricingPeriodsProvider(resourceId))
      ..invalidate(resourceDurationsProvider(resourceId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final periodsAsync = ref.watch(resourcePricingPeriodsProvider(resourceId));
    final cc = ref.watch(currencyCodeProvider);
    return periodsAsync.when(
      data: (periods) {
        if (periods.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'No pricing seasons yet — customers cannot book until one '
              'covers their date',
              style: TextStyle(color: Colors.grey[500]),
            ),
          );
        }
        final gaps = computeGaps(periods);
        return Column(
          children: [
            if (gaps.isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 4, bottom: 4),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.orange[800],
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Days with no pricing (booking blocked): '
                        '${gaps.map(_fmtGap).join(', ')}',
                        style: TextStyle(
                          color: Colors.orange[900],
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            for (final p in periods)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(left: 8),
                shape: const Border(),
                title: Text(
                  p.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  _periodSubtitle(p, cc),
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      onPressed: () => onEditPeriod(p),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: AppTheme.errorRed,
                        size: 20,
                      ),
                      onPressed: () => _confirmDelete(context, ref, p),
                    ),
                  ],
                ),
                children: [
                  _DurationList(
                    resourceId: resourceId,
                    period: p,
                    onEdit: (d) => onEditTier(p, d),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => onAddTier(p),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add Duration'),
                    ),
                  ),
                ],
              ),
          ],
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Text('$e'),
    );
  }
}

class _DurationList extends ConsumerWidget {
  const _DurationList({
    required this.resourceId,
    required this.period,
    required this.onEdit,
  });
  final String resourceId;
  final PricingPeriod period;
  final ValueChanged<DurationModel> onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final durationsAsync = ref.watch(periodDurationsProvider(period.id));
    return durationsAsync.when(
      data: (durs) {
        if (durs.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'No pricing tiers in this season yet',
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
                          ref
                            ..invalidate(periodDurationsProvider(period.id))
                            ..invalidate(
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
          'rate. You approve every request before they pay. This is the '
          'default rate — individual seasons can override it.',
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
