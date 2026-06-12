import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:venue_vibe/src/core/supabase_config.dart';
import 'package:venue_vibe/src/models/booking.dart';
import 'package:venue_vibe/src/repositories/booking_repository.dart';
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
    super.key,
  });
  final String resourceId;
  final DateTime startTime;
  final DateTime endTime;
  final String durationLabel;
  final double price;

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  bool _splitPayment = false;
  bool _isLoading = false;

  Future<void> _confirmBooking() async {
    setState(() => _isLoading = true);

    try {
      final userId = SupabaseConfig.client.auth.currentUser!.id;
      final settings =
          await ref.read(tenantRepositoryProvider).getPlatformSettings();
      final commissionRate = settings?.commissionRate ?? 10.0;
      final commission = widget.price * (commissionRate / 100);

      final booking = Booking(
        id: '',
        userId: userId,
        resourceId: widget.resourceId,
        startTime: widget.startTime,
        endTime: widget.endTime,
        totalPrice: widget.price + commission,
        commissionAmount: commission,
        paymentStatus: 'paid',
        splitPayment: _splitPayment,
        createdAt: DateTime.now(),
      );

      final created =
          await ref.read(bookingRepositoryProvider).createBooking(booking);
      ref.invalidate(userBookingsProvider);
      if (mounted) {
        context.go('/confirmation', extra: created.id);
      }
    } on PostgrestException catch (e) {
      // 23P01 = exclusion_violation from the bookings_no_overlap constraint
      // (migration 0001): someone grabbed this slot first.
      final message = e.code == '23P01'
          ? 'Sorry, that time slot was just booked. Please pick another.'
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

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                    value:
                        '${timeFormat.format(widget.startTime)} - ${timeFormat.format(widget.endTime)}',
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
                final commission = widget.price * (rate / 100);
                final total = widget.price + commission;

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
                      const SizedBox(height: 8),
                      _PriceRow(
                        label: 'Platform Fee (${rate.toStringAsFixed(0)}%)',
                        amount: commission,
                      ),
                      const Divider(height: 20),
                      _PriceRow(
                        label: 'Total',
                        amount: total,
                        isBold: true,
                      ),
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
                  : const Text('Confirm & Pay'),
            ),
          ),
        ),
      ),
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
