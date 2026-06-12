import 'package:book_it/src/repositories/booking_repository.dart';
import 'package:book_it/src/repositories/tenant_repository.dart';
import 'package:book_it/src/theme/app_theme.dart';
import 'package:book_it/src/utils/currency_formatter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AdminDashboard extends ConsumerWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final totalTenantsAsync = ref.watch(totalTenantsProvider);
    final totalBookingsAsync = ref.watch(totalBookingsProvider);
    final totalRevenueAsync = ref.watch(totalRevenueProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Platform Overview'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(totalTenantsProvider);
              ref.invalidate(totalBookingsProvider);
              ref.invalidate(totalRevenueProvider);
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Platform Health', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 20),

            // ─── Stats Row ───
            Row(
              children: [
                Expanded(
                  child: _AdminStatCard(
                    icon: Icons.business,
                    label: 'Tenants',
                    valueAsync: totalTenantsAsync,
                    color: AppTheme.primaryBlue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _AdminStatCard(
                    icon: Icons.event_available,
                    label: 'Bookings',
                    valueAsync: totalBookingsAsync,
                    color: AppTheme.successGreen,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _AdminStatCard(
                    icon: Icons.attach_money,
                    label: 'Revenue',
                    valueAsync: totalRevenueAsync,
                    color: AppTheme.warningOrange,
                    isCurrency: true,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            Text('Quick Actions', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),

            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _QuickActionChip(
                  icon: Icons.category,
                  label: 'Manage Categories',
                  onTap: () => context.go('/admin/categories'),
                ),
                _QuickActionChip(
                  icon: Icons.business,
                  label: 'Approve Tenants',
                  onTap: () => context.go('/admin/tenants'),
                ),
                _QuickActionChip(
                  icon: Icons.percent,
                  label: 'Set Commission',
                  onTap: () => context.go('/admin/commission'),
                ),
                _QuickActionChip(
                  icon: Icons.card_membership,
                  label: 'Subscription Plans',
                  onTap: () => context.go('/admin/plans'),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // ─── Platform Settings Preview ───
            ref.watch(platformSettingsProvider).when(
                  data: (settings) {
                    if (settings == null) {
                      return Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppTheme.warningOrange.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color:
                                AppTheme.warningOrange.withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.warning_amber,
                              color: AppTheme.warningOrange,
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Platform settings not configured. Go to Commission settings to initialize.',
                                style: TextStyle(color: AppTheme.warningOrange),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    return Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Platform Settings',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          _SettingRow(
                            label: 'Commission Rate',
                            value: '${settings.commissionRate}%',
                          ),
                          _SettingRow(
                            label: 'Currency',
                            value: settings.currency,
                          ),
                          _SettingRow(
                            label: 'Cancellation Window',
                            value: '${settings.cancellationWindowHours} hours',
                          ),
                        ],
                      ),
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text('$e'),
                ),
          ],
        ),
      ),
    );
  }
}

class _AdminStatCard extends ConsumerWidget {
  const _AdminStatCard({
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
            data: (v) => Text(
              isCurrency ? formatPrice((v as num).toDouble(), cc) : '$v',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            loading: () => SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            ),
            error: (_, __) => const Text('--'),
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: Colors.grey[600])),
        ],
      ),
    );
  }
}

class _QuickActionChip extends StatelessWidget {
  const _QuickActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      onPressed: onTap,
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
