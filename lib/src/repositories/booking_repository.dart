import 'package:book_it/src/core/supabase_config.dart';
import 'package:book_it/src/models/booking.dart';
import 'package:book_it/src/repositories/tenant_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final bookingRepositoryProvider = Provider<BookingRepository>((ref) {
  return BookingRepository(SupabaseConfig.client);
});

final userBookingsProvider = FutureProvider<List<Booking>>((ref) async {
  final userId = SupabaseConfig.client.auth.currentUser?.id;
  if (userId == null) return [];
  return ref.read(bookingRepositoryProvider).getUserBookings(userId);
});

final totalBookingsProvider = FutureProvider<int>((ref) async {
  return ref.read(bookingRepositoryProvider).getTotalBookingsCount();
});

final totalRevenueProvider = FutureProvider<double>((ref) async {
  return ref.read(bookingRepositoryProvider).getTotalRevenue();
});

final tenantBookingsProvider = FutureProvider<List<Booking>>((ref) async {
  final tenant = await ref.watch(currentTenantProvider.future);
  if (tenant == null) return [];
  return ref.read(bookingRepositoryProvider).getTenantBookings(tenant.id);
});

/// Count of this tenant's bookings (confirmed + completed only).
final tenantBookingsCountProvider = FutureProvider<int>((ref) async {
  final bookings = await ref.watch(tenantBookingsProvider.future);
  return bookings
      .where((b) => b.status == 'confirmed' || b.status == 'completed')
      .length;
});

/// This tenant's earnings = base price (total minus the platform commission),
/// over confirmed + completed bookings.
final tenantRevenueProvider = FutureProvider<double>((ref) async {
  final bookings = await ref.watch(tenantBookingsProvider.future);
  return bookings
      .where((b) => b.status == 'confirmed' || b.status == 'completed')
      .fold<double>(
        0,
        (sum, b) => sum + (b.totalPrice - (b.commissionAmount ?? 0)),
      );
});

class BookingRepository {
  BookingRepository(this._client);
  final SupabaseClient _client;

  Future<List<Booking>> getUserBookings(String userId) async {
    final data = await _client
        .from('bookings')
        .select('*, resources(name, tenants(name))')
        .eq('user_id', userId)
        .order('start_time', ascending: false);
    return data.map(Booking.fromJson).toList();
  }

  Future<List<Booking>> getResourceBookings(
    String resourceId,
    DateTime start,
    DateTime end,
  ) async {
    final data = await _client
        .from('bookings')
        .select('*, profiles(full_name)')
        .eq('resource_id', resourceId)
        .gte('end_time', start.toUtc().toIso8601String())
        .lte('start_time', end.toUtc().toIso8601String())
        .inFilter('status', ['confirmed', 'pending']);
    return data.map(Booking.fromJson).toList();
  }

  Future<List<Booking>> getTenantBookings(
    String tenantId, {
    DateTime? start,
    DateTime? end,
  }) async {
    var query = _client.from('bookings').select('''
      *,
      resources!inner(name, tenant_id, tenants(name)),
      profiles(full_name)
    ''').eq('resources.tenant_id', tenantId);

    if (start != null) {
      query = query.gte('start_time', start.toUtc().toIso8601String());
    }
    if (end != null) {
      query = query.lte('end_time', end.toUtc().toIso8601String());
    }

    final data = await query.order('start_time', ascending: false);
    return data.map(Booking.fromJson).toList();
  }

  Future<Booking> createBooking(Booking booking) async {
    final data = await _client
        .from('bookings')
        .insert(booking.toJson())
        .select()
        .single();
    return Booking.fromJson(data);
  }

  Future<void> cancelBooking(String bookingId, {String? reason}) async {
    await _client.from('bookings').update({
      'status': 'cancelled',
      'cancellation_reason': reason ?? 'User cancelled',
    }).eq('id', bookingId);
  }

  Future<int> getTotalBookingsCount() async {
    final data = await _client
        .from('bookings')
        .select('id')
        .inFilter('status', ['confirmed', 'completed']);
    return data.length;
  }

  Future<double> getTotalRevenue() async {
    final data = await _client
        .from('bookings')
        .select('commission_amount')
        .inFilter('status', ['confirmed', 'completed']);
    double total = 0;
    for (final row in data) {
      total += (row['commission_amount'] as num?)?.toDouble() ?? 0;
    }
    return total;
  }
}
