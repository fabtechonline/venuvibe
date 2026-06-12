import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:venue_vibe/src/repositories/tenant_repository.dart';
import 'package:venue_vibe/src/theme/app_theme.dart';
import 'package:venue_vibe/src/utils/currency_formatter.dart';

class InvoicesScreen extends ConsumerWidget {
  const InvoicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final invoicesAsync = ref.watch(allInvoicesProvider);
    final cc = ref.watch(currencyCodeProvider);
    final periodFmt = DateFormat('MMM d, yyyy');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoices'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(allInvoicesProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => const _GenerateInvoicesDialog(),
        ),
        icon: const Icon(Icons.receipt_long),
        label: const Text('Generate'),
      ),
      body: invoicesAsync.when(
        data: (invoices) {
          if (invoices.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.receipt_long, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No invoices yet',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(color: Colors.grey[500]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Use Generate to bill a period',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: Colors.grey[400]),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: invoices.length,
            itemBuilder: (context, index) {
              final inv = invoices[index];
              final isPaid = inv.status == 'paid';
              final statusColor =
                  isPaid ? AppTheme.successGreen : AppTheme.warningOrange;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              inv.tenantName ?? 'Tenant',
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              inv.status.toUpperCase(),
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${periodFmt.format(inv.periodStart)} – '
                        '${periodFmt.format(inv.periodEnd)}',
                        style: theme.textTheme.bodySmall,
                      ),
                      const Divider(height: 20),
                      _AmountRow(
                        label: 'Subscription',
                        amount: inv.subscriptionAmount,
                        cc: cc,
                      ),
                      _AmountRow(
                        label: 'Commission',
                        amount: inv.commissionAmount,
                        cc: cc,
                      ),
                      const SizedBox(height: 4),
                      _AmountRow(
                        label: 'Total',
                        amount: inv.totalAmount,
                        cc: cc,
                        bold: true,
                      ),
                      if (!isPaid) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () async {
                              await ref
                                  .read(tenantRepositoryProvider)
                                  .updateInvoiceStatus(inv.id, 'paid');
                              ref.invalidate(allInvoicesProvider);
                            },
                            icon: const Icon(Icons.check, size: 16),
                            label: const Text('Mark paid'),
                          ),
                        ),
                      ],
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
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.label,
    required this.amount,
    required this.cc,
    this.bold = false,
  });
  final String label;
  final double amount;
  final String cc;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
      fontSize: bold ? 16 : 14,
      color: bold ? AppTheme.primaryBlue : null,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(formatPrice(amount, cc), style: style),
        ],
      ),
    );
  }
}

class _GenerateInvoicesDialog extends ConsumerStatefulWidget {
  const _GenerateInvoicesDialog();

  @override
  ConsumerState<_GenerateInvoicesDialog> createState() =>
      _GenerateInvoicesDialogState();
}

class _GenerateInvoicesDialogState
    extends ConsumerState<_GenerateInvoicesDialog> {
  late DateTime _start;
  late DateTime _end;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _start = DateTime(now.year, now.month);
    _end = now;
  }

  Future<void> _pick({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _start : _end,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _start = picked;
      } else {
        _end = picked;
      }
    });
  }

  Future<void> _generate() async {
    setState(() => _isLoading = true);
    try {
      final count = await ref
          .read(tenantRepositoryProvider)
          .generateInvoices(_start, _end);
      ref.invalidate(allInvoicesProvider);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Generated $count invoice(s)')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM d, yyyy');
    return AlertDialog(
      title: const Text('Generate Invoices'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Bills every tenant for the period: plan subscription + '
            'commission on their bookings.',
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pick(isStart: true),
                  child: Text('From\n${fmt.format(_start)}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pick(isStart: false),
                  child: Text('To\n${fmt.format(_end)}'),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _generate,
          child: _isLoading
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Generate'),
        ),
      ],
    );
  }
}
