import 'package:book_it/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AdminShell extends StatelessWidget {
  const AdminShell({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final location = GoRouterState.of(context).matchedLocation;

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _calculateIndex(location),
            onDestinationSelected: (index) {
              switch (index) {
                case 0:
                  context.go('/admin');
                case 1:
                  context.go('/admin/categories');
                case 2:
                  context.go('/admin/tenants');
                case 3:
                  context.go('/admin/commission');
                case 4:
                  context.go('/admin/plans');
                case 5:
                  context.go('/admin/invoices');
              }
            },
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  const Icon(
                    Icons.admin_panel_settings,
                    color: AppTheme.primaryBlue,
                    size: 28,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Admin',
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
                label: Text('Overview'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.category_outlined),
                selectedIcon: Icon(Icons.category),
                label: Text('Categories'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.business_outlined),
                selectedIcon: Icon(Icons.business),
                label: Text('Tenants'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.percent_outlined),
                selectedIcon: Icon(Icons.percent),
                label: Text('Commission'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.card_membership_outlined),
                selectedIcon: Icon(Icons.card_membership),
                label: Text('Plans'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long),
                label: Text('Invoices'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }

  int _calculateIndex(String location) {
    if (location.startsWith('/admin/categories')) return 1;
    if (location.startsWith('/admin/tenants')) return 2;
    if (location.startsWith('/admin/commission')) return 3;
    if (location.startsWith('/admin/plans')) return 4;
    if (location.startsWith('/admin/invoices')) return 5;
    return 0;
  }
}
