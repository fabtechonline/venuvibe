import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:venue_vibe/src/features/admin/admin_dashboard.dart';
import 'package:venue_vibe/src/features/admin/admin_shell.dart';
import 'package:venue_vibe/src/features/admin/category_manager.dart';
import 'package:venue_vibe/src/features/admin/commission_screen.dart';
import 'package:venue_vibe/src/features/admin/invoices_screen.dart';
import 'package:venue_vibe/src/features/admin/plans_screen.dart';
import 'package:venue_vibe/src/features/admin/tenant_manager.dart';
import 'package:venue_vibe/src/features/auth/auth_screens.dart';
import 'package:venue_vibe/src/features/tenant/approvals_screen.dart';
import 'package:venue_vibe/src/features/tenant/resource_editor_screen.dart';
import 'package:venue_vibe/src/features/tenant/resource_list_screen.dart';
import 'package:venue_vibe/src/features/tenant/rules_screen.dart';
import 'package:venue_vibe/src/features/tenant/scheduler_calendar.dart';
import 'package:venue_vibe/src/features/tenant/tenant_dashboard.dart';
import 'package:venue_vibe/src/features/tenant/tenant_shell.dart';
import 'package:venue_vibe/src/features/tenant/venue_profile_screen.dart';
import 'package:venue_vibe/src/features/user/availability_calendar.dart';
import 'package:venue_vibe/src/features/user/checkout_screen.dart';
import 'package:venue_vibe/src/features/user/confirmation_screen.dart';
import 'package:venue_vibe/src/features/user/discover_screen.dart';
import 'package:venue_vibe/src/features/user/my_bookings_screen.dart';
import 'package:venue_vibe/src/features/user/notifications_screen.dart';
import 'package:venue_vibe/src/features/user/profile_screen.dart';
import 'package:venue_vibe/src/features/user/resource_detail_screen.dart';
import 'package:venue_vibe/src/features/user/user_shell.dart';
import 'package:venue_vibe/src/repositories/auth_repository.dart';

final goRouterProvider = Provider<GoRouter>((ref) {
  // Re-run redirect (without rebuilding the whole router) whenever auth state
  // or the loaded profile changes, so role guards apply the moment the role
  // resolves. ref.listen (not ref.watch) keeps the router instance stable.
  final refresh = ValueNotifier<int>(0);
  ref
    ..listen(authStateProvider, (_, __) => refresh.value++)
    ..listen(currentProfileProvider, (_, __) => refresh.value++)
    ..onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final isLoggedIn =
          ref.read(authStateProvider).valueOrNull?.session != null;
      final loc = state.matchedLocation;
      final isAuthRoute = loc == '/login';

      if (!isLoggedIn && !isAuthRoute) return '/login';
      if (isLoggedIn && isAuthRoute) return '/';

      // ─── Role guards ───
      // Only enforce once the profile (role) has loaded; while it's still
      // loading we leave navigation alone to avoid a redirect flicker. Supabase
      // RLS is the real enforcement layer — this just keeps the UI honest.
      final role = ref.read(currentProfileProvider).valueOrNull?.role;
      if (role != null) {
        if (loc.startsWith('/admin') && role != 'admin') return '/';
        if (loc.startsWith('/tenant') && role != 'tenant') return '/';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),

      // ─── User Routes ───
      ShellRoute(
        builder: (context, state, child) => UserShell(child: child),
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const DiscoverScreen(),
          ),
          GoRoute(
            path: '/bookings',
            builder: (context, state) => const MyBookingsScreen(),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfileScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/resource/:id',
        builder: (context, state) =>
            ResourceDetailScreen(resourceId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/resource/:id/availability',
        builder: (context, state) =>
            AvailabilityCalendar(resourceId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/checkout',
        builder: (context, state) {
          final extra = state.extra! as Map<String, dynamic>;
          return CheckoutScreen(
            resourceId: extra['resourceId'] as String,
            startTime: extra['startTime'] as DateTime,
            endTime: extra['endTime'] as DateTime,
            durationLabel: extra['durationLabel'] as String,
            price: extra['price'] as double,
            durationId: extra['durationId'] as String?,
            isCustom: extra['isCustom'] as bool? ?? false,
          );
        },
      ),
      GoRoute(
        path: '/confirmation',
        builder: (context, state) {
          // Plain String = confirmed booking id (backward compatible);
          // map adds the awaiting-approval variant for custom requests.
          final extra = state.extra;
          if (extra is Map<String, dynamic>) {
            return ConfirmationScreen(
              bookingId: extra['bookingId'] as String,
              pendingApproval: extra['pendingApproval'] as bool? ?? false,
            );
          }
          return ConfirmationScreen(bookingId: extra! as String);
        },
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationsScreen(),
      ),

      // ─── Tenant Routes ───
      ShellRoute(
        builder: (context, state, child) => TenantShell(child: child),
        routes: [
          GoRoute(
            path: '/tenant',
            builder: (context, state) => const TenantDashboard(),
          ),
          GoRoute(
            path: '/tenant/resources',
            builder: (context, state) => const ResourceListScreen(),
          ),
        ],
      ),
      // Pushed full-screen tenant pages (back button in the AppBar).
      GoRoute(
        path: '/tenant/scheduler',
        builder: (context, state) => SchedulerCalendar(
          initialResourceId: state.extra as String?,
        ),
      ),
      GoRoute(
        path: '/tenant/rules',
        builder: (context, state) => RulesScreen(
          initialResourceId: state.extra as String?,
        ),
      ),
      GoRoute(
        path: '/tenant/approvals',
        builder: (context, state) => const ApprovalsScreen(),
      ),
      GoRoute(
        path: '/tenant/profile',
        builder: (context, state) => const VenueProfileScreen(),
      ),
      GoRoute(
        path: '/tenant/resources/edit',
        builder: (context, state) {
          final resourceId = state.extra as String?;
          return ResourceEditorScreen(resourceId: resourceId);
        },
      ),

      // ─── Admin Routes ───
      ShellRoute(
        builder: (context, state, child) => AdminShell(child: child),
        routes: [
          GoRoute(
            path: '/admin',
            builder: (context, state) => const AdminDashboard(),
          ),
          GoRoute(
            path: '/admin/categories',
            builder: (context, state) => const CategoryManager(),
          ),
          GoRoute(
            path: '/admin/tenants',
            builder: (context, state) => const TenantManager(),
          ),
          GoRoute(
            path: '/admin/commission',
            builder: (context, state) => const CommissionScreen(),
          ),
          GoRoute(
            path: '/admin/plans',
            builder: (context, state) => const PlansScreen(),
          ),
          GoRoute(
            path: '/admin/invoices',
            builder: (context, state) => const InvoicesScreen(),
          ),
        ],
      ),
    ],
  );
});
