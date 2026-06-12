import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:venue_vibe/src/repositories/auth_repository.dart';
import 'package:venue_vibe/src/repositories/booking_repository.dart';
import 'package:venue_vibe/src/theme/app_theme.dart';
import 'package:venue_vibe/src/utils/currency_formatter.dart';

class TenantDashboard extends ConsumerWidget {
  const TenantDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profileAsync = ref.watch(currentProfileProvider);
    final totalBookingsAsync = ref.watch(tenantBookingsCountProvider);
    final totalRevenueAsync = ref.watch(tenantRevenueProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(tenantBookingsProvider),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Welcome ───
            profileAsync.when(
              data: (p) => Text(
                'Welcome back, ${p?.fullName ?? 'Manager'}!',
                style: theme.textTheme.headlineMedium,
              ),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 24),

            // ─── Stats Cards ───
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    icon: Icons.event_available,
                    label: 'Total Bookings',
                    valueAsync: totalBookingsAsync,
                    color: AppTheme.primaryBlue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    icon: Icons.attach_money,
                    label: 'Revenue',
                    valueAsync: totalRevenueAsync,
                    color: AppTheme.successGreen,
                    isCurrency: true,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // ─── Pending custom-booking approvals ───
            Consumer(
              builder: (context, ref, _) {
                final pending =
                    ref.watch(tenantPendingApprovalsProvider).valueOrNull ?? [];
                if (pending.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Card(
                    color: AppTheme.warningOrange.withValues(alpha: 0.08),
                    child: ListTile(
                      leading: Badge(
                        label: Text('${pending.length}'),
                        child: const CircleAvatar(
                          backgroundColor: AppTheme.warningOrange,
                          child: Icon(
                            Icons.fact_check_outlined,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      title: const Text('Booking requests'),
                      subtitle: Text(
                        '${pending.length} custom '
                        'booking${pending.length == 1 ? '' : 's'} awaiting '
                        'your approval',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/tenant/approvals'),
                    ),
                  ),
                );
              },
            ),

            // ─── Quick Actions ───
            Text('Quick Actions', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            _ActionCard(
              icon: Icons.add_business,
              title: 'Add Resource',
              subtitle: 'Create a new bookable space',
              onTap: () => context.push('/tenant/resources/edit'),
            ),
            _ActionCard(
              icon: Icons.block,
              title: 'Block Time Slot',
              subtitle: 'Reserve time for maintenance or private use',
              onTap: () => context.push('/tenant/scheduler'),
            ),
            _ActionCard(
              icon: Icons.storefront,
              title: 'Venue Profile',
              subtitle: 'Contact person, number and address shown to customers',
              onTap: () => context.push('/tenant/profile'),
            ),

            const SizedBox(height: 24),

            // ─── Recent Bookings ───
            Text("Today's Bookings", style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            _TodayBookingsSection(),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends ConsumerWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.valueAsync,
    required this.color,
    this.isCurrency = false,
  });
  final IconData icon;
  final String label;
  final AsyncValue valueAsync;
  final Color color;
  final bool isCurrency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cc = ref.watch(currencyCodeProvider);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 12),
          valueAsync.when(
            data: (v) => FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                isCurrency ? formatPrice((v as num).toDouble(), cc) : '$v',
                maxLines: 1,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
            loading: () => const CircularProgressIndicator(),
            error: (_, __) => const Text('--'),
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: Colors.grey[600])),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.1),
          child: Icon(icon, color: AppTheme.primaryBlue),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _TodayBookingsSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tenantBookingsAsync = ref.watch(tenantBookingsProvider);
    final timeFormat = DateFormat.jm();

    return tenantBookingsAsync.when(
      data: (bookings) {
        final now = DateTime.now();
        final today = bookings.where((b) {
          return b.startTime.year == now.year &&
              b.startTime.month == now.month &&
              b.startTime.day == now.day;
        }).toList();

        if (today.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    Icons.event_available,
                    size: 40,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No bookings today',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
          );
        }

        return Column(
          children: today.map((b) {
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor:
                      AppTheme.successGreen.withValues(alpha: 0.12),
                  child: const Icon(Icons.person, color: AppTheme.successGreen),
                ),
                title: Text(b.resourceName ?? 'Resource'),
                subtitle: Text(
                  '${timeFormat.format(b.startTime)} - ${timeFormat.format(b.endTime)}',
                ),
                trailing: Text(
                  formatPrice(
                    b.totalPrice,
                    ref.watch(currencyCodeProvider),
                  ),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppTheme.primaryBlue,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Text('Error: $e'),
    );
  }
}
