import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:venue_vibe/src/models/addon.dart';
import 'package:venue_vibe/src/repositories/booking_repository.dart';
import 'package:venue_vibe/src/repositories/resource_repository.dart';
import 'package:venue_vibe/src/repositories/tenant_repository.dart';
import 'package:venue_vibe/src/theme/app_theme.dart';
import 'package:venue_vibe/src/utils/currency_formatter.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({
    required this.resourceId,
    required this.startTime,
    required this.endTime,
    required this.durationLabel,
    required this.price,
    this.durationId,
    this.isCustom = false,
    super.key,
  });
  final String resourceId;
  final DateTime startTime;
  final DateTime endTime;
  final String durationLabel;
  final double price;
  final String? durationId;
  final bool isCustom;

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  bool _splitPayment = false;
  bool _isLoading = false;
  int _repeatWeeks = 1;
  final Map<String, int> _addonQty = {};

  double _addonsTotal(List<ResourceAddon> addons) {
    var total = 0.0;
    for (final a in addons) {
      total += a.price * (_addonQty[a.id] ?? 0);
    }
    return total;
  }

  Future<void> _confirmBooking() async {
    setState(() => _isLoading = true);

    try {
      // Prices are recomputed server-side inside the RPC; what we show here
      // is a preview using the same formulas.
      final repo = ref.read(bookingRepositoryProvider);
      final String firstId;
      if (!widget.isCustom && _repeatWeeks > 1) {
        final created = await repo.createRecurringBookings(
          resourceId: widget.resourceId,
          startTime: widget.startTime,
          endTime: widget.endTime,
          durationId: widget.durationId!,
          weeks: _repeatWeeks,
          splitPayment: _splitPayment,
          addonQuantities: _addonQty,
        );
        firstId = created.first.id;
      } else {
        final created = await repo.createBookingWithAddons(
          resourceId: widget.resourceId,
          startTime: widget.startTime,
          endTime: widget.endTime,
          isCustom: widget.isCustom,
          durationId: widget.durationId,
          splitPayment: _splitPayment,
          addonQuantities: _addonQty,
        );
        firstId = created.id;
      }
      ref.invalidate(userBookingsProvider);
      if (mounted) {
        context.go(
          '/confirmation',
          extra: {
            'bookingId': firstId,
            'pendingApproval': widget.isCustom,
            'recurringCount': widget.isCustom ? 1 : _repeatWeeks,
          },
        );
      }
    } on PostgrestException catch (e) {
      // 23P01 = exclusion_violation from the bookings_no_overlap constraint
      // (migration 0001): someone grabbed this slot first. The "No pricing"
      // rejection (migration 0016) is already customer-facing as-is.
      // Series preflight errors already read well ("Cannot book the full
      // series — 19 Jun 2026: time unavailable; …").
      final message = e.code == '23P01'
          ? 'Sorry, that time slot was just booked. Please pick another.'
          : e.message.contains('No pricing') ||
                  e.message.contains('Cannot book the full series')
              ? e.message
              : 'Booking failed: ${e.message}';
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Booking failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat('EEE, MMM d, yyyy');
    final timeFormat = DateFormat.jm();
    final settingsAsync = ref.watch(platformSettingsProvider);
    final addons =
        ref.watch(resourceAddonsProvider(widget.resourceId)).valueOrNull ??
            const <ResourceAddon>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Approval notice for custom requests ───
            if (widget.isCustom) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.warningOrange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppTheme.warningOrange.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.hourglass_top,
                      color: AppTheme.warningOrange,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'This is a custom time request. The venue must '
                        'approve it before you pay — we’ll notify you.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ─── Booking Summary ───
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Booking Summary', style: theme.textTheme.titleLarge),
                  const Divider(height: 24),
                  _SummaryRow(
                    icon: Icons.calendar_today,
                    label: 'Date',
                    value: dateFormat.format(widget.startTime),
                  ),
                  const SizedBox(height: 12),
                  _SummaryRow(
                    icon: Icons.access_time,
                    label: 'Time',
                    value: '${timeFormat.format(widget.startTime)} - '
                        '${timeFormat.format(widget.endTime)}',
                  ),
                  const SizedBox(height: 12),
                  _SummaryRow(
                    icon: Icons.timelapse,
                    label: 'Duration',
                    value: widget.durationLabel,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ─── Add-ons ───
            if (addons.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Add-ons', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 4),
                    for (final a in addons)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Name on its own line; price + stepper below.
                            Text(
                              a.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    formatPrice(
                                      a.price,
                                      ref.watch(currencyCodeProvider),
                                    ),
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                _QtyStepper(
                                  qty: _addonQty[a.id] ?? 0,
                                  maxQty: a.maxQty,
                                  onChanged: (q) =>
                                      setState(() => _addonQty[a.id] = q),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ─── Repeat weekly (slot bookings only) ───
            if (!widget.isCustom) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.repeat, size: 20),
                        const SizedBox(width: 8),
                        const Expanded(child: Text('Repeat weekly')),
                        DropdownButton<int>(
                          value: _repeatWeeks,
                          underline: const SizedBox.shrink(),
                          items: [
                            const DropdownMenuItem(
                              value: 1,
                              child: Text('Book once'),
                            ),
                            for (var w = 2; w <= 12; w++)
                              DropdownMenuItem(
                                value: w,
                                child: Text('$w weeks'),
                              ),
                          ],
                          onChanged: (v) =>
                              setState(() => _repeatWeeks = v ?? 1),
                        ),
                      ],
                    ),
                    if (_repeatWeeks > 1)
                      Text(
                        'Same slot every week, starting '
                        '${DateFormat('EEE, MMM d').format(widget.startTime)}. '
                        'If any week is unavailable, nothing is booked.',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ─── Split Payment Toggle ───
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Split with Friends'),
                subtitle: const Text('Share the cost equally with attendees'),
                value: _splitPayment,
                onChanged: (v) => setState(() => _splitPayment = v),
              ),
            ),

            const SizedBox(height: 16),

            // ─── Price Breakdown ───
            settingsAsync.when(
              data: (settings) {
                final rate = settings?.commissionRate ?? 10.0;
                final addonsTotal = _addonsTotal(addons);
                final commission = (widget.price + addonsTotal) * (rate / 100);
                final total = widget.price + addonsTotal + commission;

                return Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryBlue.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppTheme.primaryBlue.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    children: [
                      _PriceRow(label: 'Base Price', amount: widget.price),
                      if (addonsTotal > 0) ...[
                        const SizedBox(height: 8),
                        _PriceRow(label: 'Add-ons', amount: addonsTotal),
                      ],
                      const SizedBox(height: 8),
                      _PriceRow(
                        label: 'Platform Fee (${rate.toStringAsFixed(0)}%)',
                        amount: commission,
                      ),
                      const Divider(height: 20),
                      _PriceRow(
                        label: _repeatWeeks > 1 ? 'Total per week' : 'Total',
                        amount: total,
                        isBold: true,
                      ),
                      if (_repeatWeeks > 1) ...[
                        const SizedBox(height: 8),
                        _PriceRow(
                          label: 'Series estimate (× $_repeatWeeks weeks)',
                          amount: total * _repeatWeeks,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Each week is priced by its season — the charged '
                          'total may differ.',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: Colors.grey[600]),
                        ),
                      ],
                      if (_splitPayment) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Split link will be generated after booking',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: AppTheme.primaryBlue),
                        ),
                      ],
                    ],
                  ),
                );
              },
              loading: () => const CircularProgressIndicator(),
              error: (e, _) => Text('$e'),
            ),
          ],
        ),
      ),
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
            child: ElevatedButton(
              onPressed: _isLoading ? null : _confirmBooking,
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      widget.isCustom
                          ? 'Request Booking'
                          : _repeatWeeks > 1
                              ? 'Book $_repeatWeeks weeks'
                              : 'Confirm & Pay',
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QtyStepper extends StatelessWidget {
  const _QtyStepper({
    required this.qty,
    required this.maxQty,
    required this.onChanged,
  });
  final int qty;
  final int maxQty;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: qty > 0 ? () => onChanged(qty - 1) : null,
        ),
        SizedBox(
          width: 24,
          child: Text(
            '$qty',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add_circle_outline),
          color: AppTheme.primaryBlue,
          onPressed: qty < maxQty ? () => onChanged(qty + 1) : null,
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(color: Colors.grey[600])),
        const Spacer(),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _PriceRow extends ConsumerWidget {
  const _PriceRow({
    required this.label,
    required this.amount,
    this.isBold = false,
  });
  final String label;
  final double amount;
  final bool isBold;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cc = ref.watch(currencyCodeProvider);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w400,
            fontSize: isBold ? 18 : 14,
          ),
        ),
        Text(
          formatPrice(amount, cc),
          style: TextStyle(
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w400,
            fontSize: isBold ? 18 : 14,
            color: isBold ? AppTheme.primaryBlue : null,
          ),
        ),
      ],
    );
  }
}
