import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:venue_vibe/src/models/booking.dart';
import 'package:venue_vibe/src/repositories/booking_repository.dart';
import 'package:venue_vibe/src/theme/app_theme.dart';
import 'package:venue_vibe/src/utils/currency_formatter.dart';
import 'package:venue_vibe/src/utils/pricing.dart';

/// Custom booking requests awaiting this venue's decision. Approving may
/// reprice the venue portion (new hourly rate or a final price); any
/// reduction is shown to the customer as a discount.
class ApprovalsScreen extends ConsumerWidget {
  const ApprovalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingAsync = ref.watch(tenantPendingApprovalsProvider);
    final cc = ref.watch(currencyCodeProvider);
    final dateFmt = DateFormat('EEE, MMM d');
    final timeFmt = DateFormat.jm();

    return Scaffold(
      appBar: AppBar(title: const Text('Booking Approvals')),
      body: pendingAsync.when(
        data: (pending) {
          if (pending.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.fact_check_outlined,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No requests waiting for approval',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: pending.length,
            itemBuilder: (context, index) {
              final b = pending[index];
              final minutes = b.endTime.difference(b.startTime).inMinutes;
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
                              b.resourceName ?? 'Resource',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          Chip(
                            label: const Text('CUSTOM'),
                            visualDensity: VisualDensity.compact,
                            backgroundColor:
                                AppTheme.warningOrange.withValues(alpha: 0.15),
                            labelStyle: const TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${b.userName ?? 'Customer'} · '
                        '${dateFmt.format(b.startTime)} · '
                        '${timeFmt.format(b.startTime)} – '
                        '${timeFmt.format(b.endTime)} '
                        '(${(minutes / 60).toStringAsFixed(minutes % 60 == 0 ? 0 : 1)}h)',
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                      const SizedBox(height: 6),
                      _AddonsLine(bookingId: b.id),
                      Text(
                        'Requested: ${formatPrice(b.basePrice ?? 0, cc)} venue'
                        '${b.addonsTotal > 0 ? ' + ${formatPrice(b.addonsTotal, cc)} add-ons' : ''}'
                        ' · ${formatPrice(b.totalPrice, cc)} total',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.errorRed,
                              ),
                              onPressed: () => _showRejectDialog(
                                context,
                                ref,
                                b,
                              ),
                              icon: const Icon(Icons.close, size: 18),
                              label: const Text('Decline'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _showApproveDialog(
                                context,
                                ref,
                                b,
                              ),
                              icon: const Icon(Icons.check, size: 18),
                              label: const Text('Approve'),
                            ),
                          ),
                        ],
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

  void _showApproveDialog(BuildContext context, WidgetRef ref, Booking b) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _ApproveDialog(booking: b),
    );
  }

  void _showRejectDialog(BuildContext context, WidgetRef ref, Booking b) {
    final reasonCtrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Decline request'),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(
            labelText: 'Reason (shown to the customer)',
            hintText: 'e.g. Court unavailable for maintenance',
          ),
          maxLines: 2,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              try {
                await ref
                    .read(bookingRepositoryProvider)
                    .rejectCustomBooking(b.id, reasonCtrl.text);
                ref.invalidate(tenantBookingsProvider);
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              }
            },
            child: const Text('Decline'),
          ),
        ],
      ),
    );
  }
}

class _AddonsLine extends ConsumerWidget {
  const _AddonsLine({required this.bookingId});
  final String bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addons = ref.watch(bookingAddonsProvider(bookingId)).valueOrNull;
    if (addons == null || addons.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        'Add-ons: ${addons.map((a) => '${a.qty}× ${a.name}').join(', ')}',
        style: TextStyle(color: Colors.grey[700], fontSize: 13),
      ),
    );
  }
}

enum _PriceMode { keep, hourlyRate, finalTotal }

class _ApproveDialog extends ConsumerStatefulWidget {
  const _ApproveDialog({required this.booking});
  final Booking booking;

  @override
  ConsumerState<_ApproveDialog> createState() => _ApproveDialogState();
}

class _ApproveDialogState extends ConsumerState<_ApproveDialog> {
  _PriceMode _mode = _PriceMode.keep;
  final _valueCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _valueCtrl.dispose();
    super.dispose();
  }

  int get _minutes =>
      widget.booking.endTime.difference(widget.booking.startTime).inMinutes;

  /// The venue price that would result from the current dialog inputs.
  double get _newBase {
    final requested = widget.booking.basePrice ?? 0;
    final v = double.tryParse(_valueCtrl.text);
    switch (_mode) {
      case _PriceMode.keep:
        return requested;
      case _PriceMode.hourlyRate:
        return v == null ? requested : customBasePrice(v, _minutes);
      case _PriceMode.finalTotal:
        return v ?? requested;
    }
  }

  Future<void> _approve() async {
    setState(() => _saving = true);
    try {
      final v = double.tryParse(_valueCtrl.text);
      await ref.read(bookingRepositoryProvider).approveCustomBooking(
            widget.booking.id,
            finalTotal: _mode == _PriceMode.finalTotal ? v : null,
            hourlyRate: _mode == _PriceMode.hourlyRate ? v : null,
          );
      ref.invalidate(tenantBookingsProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cc = ref.watch(currencyCodeProvider);
    final requested = widget.booking.basePrice ?? 0;
    final newBase = _newBase;
    final discount = newBase < requested ? requested - newBase : 0.0;

    return AlertDialog(
      title: const Text('Approve booking'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Requested venue price: ${formatPrice(requested, cc)} '
            '(${(_minutes / 60).toStringAsFixed(1)}h)',
          ),
          const SizedBox(height: 12),
          RadioGroup<_PriceMode>(
            groupValue: _mode,
            onChanged: (v) => setState(() => _mode = v ?? _PriceMode.keep),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<_PriceMode>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('Keep requested price'),
                  value: _PriceMode.keep,
                ),
                RadioListTile<_PriceMode>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('Set a different hourly rate'),
                  value: _PriceMode.hourlyRate,
                ),
                RadioListTile<_PriceMode>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('Set the venue price directly'),
                  value: _PriceMode.finalTotal,
                ),
              ],
            ),
          ),
          if (_mode != _PriceMode.keep) ...[
            const SizedBox(height: 4),
            TextField(
              controller: _valueCtrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: _mode == _PriceMode.hourlyRate
                    ? 'Hourly rate'
                    : 'Venue price',
                prefixText: '${currencySymbol(cc)} ',
                isDense: true,
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            discount > 0
                ? 'New venue price: ${formatPrice(newBase, cc)} '
                    '(customer sees a ${formatPrice(discount, cc)} discount)'
                : 'New venue price: ${formatPrice(newBase, cc)}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _approve,
          child: _saving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Approve'),
        ),
      ],
    );
  }
}
