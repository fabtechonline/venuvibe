import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:venue_vibe/src/features/tenant/tenant_onboarding_screen.dart';
import 'package:venue_vibe/src/repositories/booking_repository.dart';
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
        final pendingCount =
            ref.watch(tenantPendingApprovalsProvider).valueOrNull?.length ?? 0;
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
                  // Push so the customer view gets a back button to here.
                  context.push('/');
              }
            },
            destinations: [
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: pendingCount > 0,
                  label: Text('$pendingCount'),
                  child: const Icon(Icons.dashboard_outlined),
                ),
                selectedIcon: Badge(
                  isLabelVisible: pendingCount > 0,
                  label: Text('$pendingCount'),
                  child: const Icon(Icons.dashboard),
                ),
                label: 'Dashboard',
              ),
              const NavigationDestination(
                icon: Icon(Icons.meeting_room_outlined),
                selectedIcon: Icon(Icons.meeting_room),
                label: 'Resources',
              ),
              const NavigationDestination(
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
    return 0;
  }
}
