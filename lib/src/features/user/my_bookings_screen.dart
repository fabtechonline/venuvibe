import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:venue_vibe/src/models/booking.dart';
import 'package:venue_vibe/src/repositories/booking_repository.dart';
import 'package:venue_vibe/src/repositories/tenant_repository.dart';
import 'package:venue_vibe/src/theme/app_theme.dart';
import 'package:venue_vibe/src/utils/currency_formatter.dart';

class MyBookingsScreen extends ConsumerWidget {
  const MyBookingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final bookingsAsync = ref.watch(userBookingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My Bookings')),
      body: bookingsAsync.when(
        data: (bookings) {
          if (bookings.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.event_busy, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No bookings yet',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(color: Colors.grey[500]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Start exploring spaces to make your first booking',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: Colors.grey[400]),
                  ),
                ],
              ),
            );
          }

          final upcoming = bookings.where((b) => b.isUpcoming).toList();
          final past = bookings
              .where((b) => b.isPast || b.status == 'cancelled')
              .toList();

          return DefaultTabController(
            length: 2,
            child: Column(
              children: [
                TabBar(
                  labelColor: AppTheme.primaryBlue,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: AppTheme.primaryBlue,
                  tabs: [
                    Tab(text: 'Upcoming (${upcoming.length})'),
                    Tab(text: 'Past (${past.length})'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _BookingList(bookings: upcoming, showCancel: true),
                      _BookingList(bookings: past, showCancel: false),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _BookingList extends ConsumerWidget {
  const _BookingList({
    required this.bookings,
    required this.showCancel,
  });
  final List<Booking> bookings;
  final bool showCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (bookings.isEmpty) {
      return Center(
        child: Text('No bookings', style: TextStyle(color: Colors.grey[500])),
      );
    }
    final theme = Theme.of(context);
    final dateFormat = DateFormat('EEE, MMM d');
    final timeFormat = DateFormat.jm();
    final settings = ref.watch(platformSettingsProvider).valueOrNull;
    final windowHours = settings?.cancellationWindowHours ?? 24;

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: bookings.length,
      itemBuilder: (context, index) {
        final b = bookings[index];
        Color statusColor;
        switch (b.status) {
          case 'confirmed':
            statusColor = AppTheme.successGreen;
          case 'cancelled':
            statusColor = AppTheme.errorRed;
          case 'completed':
            statusColor = AppTheme.primaryBlue;
          default:
            statusColor = AppTheme.warningOrange;
        }

        return Card(
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
                        b.status.toUpperCase(),
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                if (b.tenantName != null) ...[
                  const SizedBox(height: 4),
                  Text(b.tenantName!, style: theme.textTheme.bodySmall),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 16,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 8),
                    Text(dateFormat.format(b.startTime)),
                    const SizedBox(width: 16),
                    Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 8),
                    Text(
                      '${timeFormat.format(b.startTime)} - ${timeFormat.format(b.endTime)}',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      formatPrice(
                        b.totalPrice,
                        ref.watch(currencyCodeProvider),
                      ),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: AppTheme.primaryBlue,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    if (showCancel && b.isCancellableWithin(windowHours))
                      TextButton(
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Cancel Booking?'),
                              content: const Text(
                                'Are you sure you want to cancel this booking?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Keep'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text(
                                    'Cancel Booking',
                                    style: TextStyle(color: AppTheme.errorRed),
                                  ),
                                ),
                              ],
                            ),
                          );
                          if (confirm ?? false) {
                            await ref
                                .read(bookingRepositoryProvider)
                                .cancelBooking(b.id);
                            ref.invalidate(userBookingsProvider);
                          }
                        },
                        child: const Text(
                          'Cancel',
                          style: TextStyle(color: AppTheme.errorRed),
                        ),
                      )
                    else if (showCancel && b.isUpcoming)
                      Text(
                        'Within ${windowHours}h · non-refundable',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.grey[500]),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
