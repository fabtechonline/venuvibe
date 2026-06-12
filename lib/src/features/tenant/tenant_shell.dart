import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:venue_vibe/src/features/tenant/tenant_onboarding_screen.dart';
import 'package:venue_vibe/src/repositories/tenant_repository.dart';

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
        final location = GoRouterState.of(context).matchedLocation;
        return Scaffold(
          body: child,
          bottomNavigationBar: NavigationBar(
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
                case 4:
                  context.go('/');
              }
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: 'Dashboard',
              ),
              NavigationDestination(
                icon: Icon(Icons.meeting_room_outlined),
                selectedIcon: Icon(Icons.meeting_room),
                label: 'Resources',
              ),
              NavigationDestination(
                icon: Icon(Icons.calendar_month_outlined),
                selectedIcon: Icon(Icons.calendar_month),
                label: 'Scheduler',
              ),
              NavigationDestination(
                icon: Icon(Icons.tune_outlined),
                selectedIcon: Icon(Icons.tune),
                label: 'Rules',
              ),
              NavigationDestination(
                icon: Icon(Icons.storefront_outlined),
                selectedIcon: Icon(Icons.storefront),
                label: 'Customer',
              ),
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
