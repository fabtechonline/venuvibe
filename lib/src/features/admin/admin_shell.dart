import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Admin portal scaffold. Bottom navigation keeps the most-used sections;
/// Categories, Commission and Plans open as pushed full-screen pages from
/// the dashboard quick actions (with back buttons), matching the tenant
/// portal pattern.
class AdminShell extends StatelessWidget {
  const AdminShell({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _calculateIndex(location),
        onDestinationSelected: (index) {
          switch (index) {
            case 0:
              context.go('/admin');
            case 1:
              context.go('/admin/tenants');
            case 2:
              context.go('/admin/invoices');
            case 3:
              // Push so the customer view gets a back button to here.
              context.push('/');
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Overview',
          ),
          NavigationDestination(
            icon: Icon(Icons.business_outlined),
            selectedIcon: Icon(Icons.business),
            label: 'Tenants',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Invoices',
          ),
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront),
            label: 'Customer',
          ),
        ],
      ),
    );
  }

  int _calculateIndex(String location) {
    if (location.startsWith('/admin/tenants')) return 1;
    if (location.startsWith('/admin/invoices')) return 2;
    return 0;
  }
}
