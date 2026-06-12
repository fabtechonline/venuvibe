import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:venue_vibe/src/core/supabase_config.dart';
import 'package:venue_vibe/src/models/addon.dart';
import 'package:venue_vibe/src/models/booking.dart';
import 'package:venue_vibe/src/repositories/tenant_repository.dart';

final bookingRepositoryProvider = Provider<BookingRepository>((ref) {
  return BookingRepository(SupabaseConfig.client);
});

final userBookingsProvider = FutureProvider<List<Booking>>((ref) async {
  final userId = SupabaseConfig.client.auth.currentUser?.id;
  if (userId == null) return [];
  final repo = ref.read(bookingRepositoryProvider);
  // Flip any stale approval-pipeline holds before reading, so the list never
  // shows a payable booking whose deadline has passed (the DB cron does the
  // same sweep every 10 minutes).
  try {
    await repo.expireStaleBookings();
  } catch (_) {
    // Non-fatal: the cron sweep and the pay-time guard still cover expiry.
  }
  return repo.getUserBookings(userId);
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

/// Custom booking requests awaiting this tenant's approval.
final tenantPendingApprovalsProvider =
    FutureProvider<List<Booking>>((ref) async {
  final bookings = await ref.watch(tenantBookingsProvider.future);
  return bookings.where((b) => b.isAwaitingApproval).toList();
});

/// Add-on line items of one booking (snapshots).
final bookingAddonsProvider =
    FutureProvider.family<List<BookingAddon>, String>((ref, bookingId) async {
  return ref.read(bookingRepositoryProvider).getBookingAddons(bookingId);
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
        .inFilter(
      'status',
      ['confirmed', 'pending', 'pending_approval', 'approved'],
    );
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

  /// Server-priced, atomic booking creation (booking + add-on lines).
  /// Slot bookings confirm immediately (placeholder-pay world); custom
  /// bookings land in 'pending_approval' for the venue owner to review.
  Future<Booking> createBookingWithAddons({
    required String resourceId,
    required DateTime startTime,
    required DateTime endTime,
    required bool isCustom,
    String? durationId,
    bool splitPayment = false,
    Map<String, int> addonQuantities = const {},
  }) async {
    final data = await _client.rpc<Map<String, dynamic>>(
      'create_booking_with_addons',
      params: {
        'p_resource_id': resourceId,
        'p_start': startTime.toUtc().toIso8601String(),
        'p_end': endTime.toUtc().toIso8601String(),
        'p_duration_id': durationId,
        'p_is_custom': isCustom,
        'p_split_payment': splitPayment,
        'p_addons': [
          for (final e in addonQuantities.entries)
            if (e.value > 0) {'addon_id': e.key, 'qty': e.value},
        ],
      },
    );
    return Booking.fromJson(data);
  }

  Future<List<BookingAddon>> getBookingAddons(String bookingId) async {
    final data = await _client
        .from('booking_addons')
        .select()
        .eq('booking_id', bookingId)
        .order('name');
    return data.map(BookingAddon.fromJson).toList();
  }

  /// Venue owner approves a custom request. Pass [finalTotal] to set the
  /// venue price directly, or [hourlyRate] to derive it; any reduction below
  /// the requested price is stored as a customer-visible discount.
  Future<Booking> approveCustomBooking(
    String bookingId, {
    double? finalTotal,
    double? hourlyRate,
  }) async {
    final data = await _client.rpc<Map<String, dynamic>>(
      'approve_custom_booking',
      params: {
        'p_booking_id': bookingId,
        'p_final_total': finalTotal,
        'p_hourly_rate': hourlyRate,
      },
    );
    return Booking.fromJson(data);
  }

  Future<Booking> rejectCustomBooking(String bookingId, String reason) async {
    final data = await _client.rpc<Map<String, dynamic>>(
      'reject_custom_booking',
      params: {'p_booking_id': bookingId, 'p_reason': reason},
    );
    return Booking.fromJson(data);
  }

  /// Placeholder payment for an approved booking — the future gateway
  /// integration replaces only this call (create-checkout-session + webhook
  /// produce the same confirmed/paid end state).
  Future<Booking> payBookingPlaceholder(String bookingId) async {
    final data = await _client.rpc<Map<String, dynamic>>(
      'pay_booking_placeholder',
      params: {'p_booking_id': bookingId},
    );
    return Booking.fromJson(data);
  }

  /// Releases expired approval-pipeline holds (idempotent definer RPC).
  Future<void> expireStaleBookings() async {
    await _client.rpc<dynamic>('expire_stale_bookings');
  }

  /// Moves a confirmed slot booking to a new time of the same length.
  /// The server reprices from the new date's pricing season and the
  /// no-overlap constraint rejects taken slots (23P01).
  Future<Booking> rescheduleBooking(
    String bookingId,
    DateTime newStart,
    DateTime newEnd,
  ) async {
    final data = await _client.rpc<Map<String, dynamic>>(
      'reschedule_booking',
      params: {
        'p_booking_id': bookingId,
        'p_new_start': newStart.toUtc().toIso8601String(),
        'p_new_end': newEnd.toUtc().toIso8601String(),
      },
    );
    return Booking.fromJson(data);
  }

  /// Books the same slot weekly for [weeks] occurrences (2–12), each priced
  /// by its date's season. All-or-nothing: any conflicting or unpriced date
  /// aborts the whole series with the dates listed in the error.
  Future<List<Booking>> createRecurringBookings({
    required String resourceId,
    required DateTime startTime,
    required DateTime endTime,
    required String durationId,
    required int weeks,
    bool splitPayment = false,
    Map<String, int> addonQuantities = const {},
  }) async {
    final data = await _client.rpc<List<dynamic>>(
      'create_recurring_bookings',
      params: {
        'p_resource_id': resourceId,
        'p_start': startTime.toUtc().toIso8601String(),
        'p_end': endTime.toUtc().toIso8601String(),
        'p_duration_id': durationId,
        'p_weeks': weeks,
        'p_split_payment': splitPayment,
        'p_addons': [
          for (final e in addonQuantities.entries)
            if (e.value > 0) {'addon_id': e.key, 'qty': e.value},
        ],
      },
    );
    return data
        .map((e) => Booking.fromJson(e as Map<String, dynamic>))
        .toList();
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
