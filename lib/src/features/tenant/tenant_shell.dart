import 'package:book_it/src/features/tenant/tenant_onboarding_screen.dart';
import 'package:book_it/src/repositories/tenant_repository.dart';
import 'package:book_it/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class TenantShell extends ConsumerWidget {
  const TenantShell({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenantAsync = ref.watch(currentTenantProvider);
    return tenantAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      data: (tenant) {
        if (tenant == null) return const TenantOnboarding();
        final theme = Theme.of(context);
        final location = GoRouterState.of(context).matchedLocation;
        return Scaffold(
      body: Row(
        children: [
          // ─── Sidebar Navigation ───
          NavigationRail(
            selectedIndex: _calculateIndex(location),
            onDestinationSelected: (index) {
              switch (index) {
                case 0:
                  context.go('/tenant');
                case 1:
                  context.go('/tenant/resources');
                case 2:
                  context.go('/tenant/scheduler');
                case 3:
                  context.go('/tenant/rules');
              }
            },
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  const Icon(
                    Icons.business,
                    color: AppTheme.primaryBlue,
                    size: 28,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Manager',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: AppTheme.primaryBlue),
                  ),
                ],
              ),
            ),
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: IconButton(
                    icon: const Icon(Icons.home_outlined),
                    onPressed: () => context.go('/'),
                    tooltip: 'Customer View',
                  ),
                ),
              ),
            ),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: Text('Dashboard'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.meeting_room_outlined),
                selectedIcon: Icon(Icons.meeting_room),
                label: Text('Resources'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.calendar_month_outlined),
                selectedIcon: Icon(Icons.calendar_month),
                label: Text('Scheduler'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.tune_outlined),
                selectedIcon: Icon(Icons.tune),
                label: Text('Rules'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(child: child),
        ],
      ),
        );
      },
    );
  }

  int _calculateIndex(String location) {
    if (location.startsWith('/tenant/resources')) return 1;
    if (location.startsWith('/tenant/scheduler')) return 2;
    if (location.startsWith('/tenant/rules')) return 3;
    return 0;
  }
}
