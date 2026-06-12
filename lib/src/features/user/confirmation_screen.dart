import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:venue_vibe/src/theme/app_theme.dart';

class ConfirmationScreen extends StatelessWidget {
  const ConfirmationScreen({
    required this.bookingId,
    this.pendingApproval = false,
    this.recurringCount = 1,
    super.key,
  });
  final String bookingId;

  /// True for custom time requests: the venue still has to approve before
  /// the customer pays.
  final bool pendingApproval;

  /// Number of bookings created (> 1 for a weekly series).
  final int recurringCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent =
        pendingApproval ? AppTheme.warningOrange : AppTheme.successGreen;
    final isSeries = recurringCount > 1;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  pendingApproval ? Icons.hourglass_top : Icons.check_circle,
                  size: 64,
                  color: accent,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                pendingApproval
                    ? 'Request Sent!'
                    : isSeries
                        ? 'Series Booked!'
                        : 'Booking Confirmed!',
                style: theme.textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                pendingApproval
                    ? 'The venue is reviewing your custom booking.\n'
                        "You'll be notified — and pay — once it's approved."
                    : isSeries
                        ? '$recurringCount weekly bookings have been '
                            'reserved.\nEach week is priced by its season — '
                            'see My Bookings.'
                        : 'Your space has been reserved successfully.\n'
                            "You'll receive a confirmation shortly.",
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Ref: ${bookingId.substring(0, 8).toUpperCase()}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => context.go('/bookings'),
                  child: const Text('View My Bookings'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  onPressed: () => context.go('/'),
                  child: const Text('Back to Discover'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
