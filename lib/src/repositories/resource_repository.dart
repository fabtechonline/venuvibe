import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:venue_vibe/src/core/supabase_config.dart';
import 'package:venue_vibe/src/models/addon.dart';
import 'package:venue_vibe/src/models/busy_slot.dart';
import 'package:venue_vibe/src/models/category.dart';
import 'package:venue_vibe/src/models/duration_model.dart';
import 'package:venue_vibe/src/models/pricing_period.dart';
import 'package:venue_vibe/src/models/resource.dart';
import 'package:venue_vibe/src/models/resource_hours.dart';
import 'package:venue_vibe/src/models/slot_block.dart';
import 'package:venue_vibe/src/repositories/tenant_repository.dart';
import 'package:venue_vibe/src/utils/pricing_periods.dart';

final resourceRepositoryProvider = Provider<ResourceRepository>((ref) {
  return ResourceRepository(SupabaseConfig.client);
});

final categoriesProvider = FutureProvider<List<Category>>((ref) async {
  return ref.read(resourceRepositoryProvider).getCategories();
});

final allResourcesProvider = FutureProvider<List<Resource>>((ref) async {
  return ref.read(resourceRepositoryProvider).getResources();
});

/// Resources owned by the currently signed-in tenant only.
final tenantResourcesProvider = FutureProvider<List<Resource>>((ref) async {
  final tenant = await ref.watch(currentTenantProvider.future);
  if (tenant == null) return [];
  return ref.read(resourceRepositoryProvider).getTenantResources(tenant.id);
});

final resourcesByCategoryProvider =
    FutureProvider.family<List<Resource>, String>((ref, categoryId) async {
  return ref
      .read(resourceRepositoryProvider)
      .getResourcesByCategory(categoryId);
});

final resourceDurationsProvider =
    FutureProvider.family<List<DurationModel>, String>((ref, resourceId) async {
  return ref.read(resourceRepositoryProvider).getDurations(resourceId);
});

final resourceProvider =
    FutureProvider.family<Resource, String>((ref, id) async {
  return ref.read(resourceRepositoryProvider).getResource(id);
});

/// Maintenance/blocked slots across the current tenant's resources.
final tenantSlotBlocksProvider = FutureProvider<List<SlotBlock>>((ref) async {
  final tenant = await ref.watch(currentTenantProvider.future);
  if (tenant == null) return [];
  return ref.read(resourceRepositoryProvider).getTenantSlotBlocks(tenant.id);
});

/// Per-weekday trading hours for a resource (empty = legacy single window).
final resourceHoursProvider =
    FutureProvider.family<List<ResourceHours>, String>((ref, resourceId) async {
  return ref.read(resourceRepositoryProvider).getResourceHours(resourceId);
});

/// Active add-ons a customer can attach to a booking of this resource.
final resourceAddonsProvider =
    FutureProvider.family<List<ResourceAddon>, String>((ref, resourceId) async {
  return ref.read(resourceRepositoryProvider).getAddons(resourceId);
});

/// Active pricing seasons of a resource, ordered by start date.
final resourcePricingPeriodsProvider =
    FutureProvider.family<List<PricingPeriod>, String>((ref, resourceId) async {
  return ref.read(resourceRepositoryProvider).getPricingPeriods(resourceId);
});

/// Active duration tiers belonging to one pricing season.
final periodDurationsProvider =
    FutureProvider.family<List<DurationModel>, String>((ref, periodId) async {
  return ref.read(resourceRepositoryProvider).getDurationsForPeriod(periodId);
});

/// Season-copy preflight failure with a user-readable reason.
class PricingCopyException implements Exception {
  PricingCopyException(this.message);
  final String message;

  @override
  String toString() => message;
}

class ResourceRepository {
  ResourceRepository(this._client);
  final SupabaseClient _client;

  Future<List<Category>> getCategories() async {
    final data = await _client
        .from('categories')
        .select()
        .eq('is_active', true)
        .order('sort_order');
    return data.map(Category.fromJson).toList();
  }

  Future<List<Resource>> getResources({String? search}) async {
    var query = _client.from('resources').select('''
      *,
      tenants(name),
      categories(name)
    ''').eq('is_active', true);

    if (search != null && search.isNotEmpty) {
      query = query.ilike('name', '%$search%');
    }

    final data = await query.order('created_at', ascending: false);
    return data.map(Resource.fromJson).toList();
  }

  Future<List<Resource>> getResourcesByCategory(String categoryId) async {
    final data = await _client.from('resources').select('''
      *,
      tenants(name),
      categories(name)
    ''').eq('is_active', true).eq('category_id', categoryId);
    return data.map(Resource.fromJson).toList();
  }

  Future<List<Resource>> getTenantResources(String tenantId) async {
    final data = await _client
        .from('resources')
        .select('*, categories(name)')
        .eq('tenant_id', tenantId);
    return data.map(Resource.fromJson).toList();
  }

  Future<Resource> getResource(String id) async {
    final data = await _client.from('resources').select('''
      *,
      tenants(name, address, city, phone, email, contact_person),
      categories(name)
    ''').eq('id', id).single();
    return Resource.fromJson(data);
  }

  Future<Resource> createResource(Resource resource) async {
    final data = await _client
        .from('resources')
        .insert(resource.toJson())
        .select()
        .single();
    return Resource.fromJson(data);
  }

  Future<void> updateResource(Resource resource) async {
    await _client
        .from('resources')
        .update(resource.toJson())
        .eq('id', resource.id);
  }

  Future<void> deleteResource(String id) async {
    await _client.from('resources').delete().eq('id', id);
  }

  Future<void> toggleResource(String id, {required bool isActive}) async {
    await _client
        .from('resources')
        .update({'is_active': isActive}).eq('id', id);
  }

  // Durations
  Future<List<DurationModel>> getDurations(String resourceId) async {
    final data = await _client
        .from('durations')
        .select()
        .eq('resource_id', resourceId)
        .eq('is_active', true)
        .order('minutes', ascending: true);
    return data.map(DurationModel.fromJson).toList();
  }

  Future<DurationModel> createDuration(DurationModel duration) async {
    final data = await _client
        .from('durations')
        .insert(duration.toJson())
        .select()
        .single();
    return DurationModel.fromJson(data);
  }

  /// Soft-deactivates when the tier is referenced by booking history
  /// (bookings.duration_id is a plain FK); hard-deletes otherwise.
  Future<void> deleteDuration(String id) async {
    final used = await _client
        .from('bookings')
        .select('id')
        .eq('duration_id', id)
        .limit(1);
    if (used.isEmpty) {
      await _client.from('durations').delete().eq('id', id);
    } else {
      await _client.from('durations').update({'is_active': false}).eq('id', id);
    }
  }

  /// Partial update of the custom-booking settings only.
  Future<void> setCustomBookingConfig(
    String resourceId, {
    required bool enabled,
    double? hourlyRate,
  }) async {
    await _client.from('resources').update({
      'custom_selector_enabled': enabled,
      'hourly_rate': hourlyRate,
    }).eq('id', resourceId);
  }

  Future<void> updateDuration(DurationModel duration) async {
    await _client
        .from('durations')
        .update(duration.toJson())
        .eq('id', duration.id);
  }

  // Pricing periods (seasons)
  Future<List<PricingPeriod>> getPricingPeriods(String resourceId) async {
    final data = await _client
        .from('pricing_periods')
        .select()
        .eq('resource_id', resourceId)
        .eq('is_active', true)
        .order('start_date', ascending: true);
    return data.map(PricingPeriod.fromJson).toList();
  }

  Future<List<DurationModel>> getDurationsForPeriod(String periodId) async {
    final data = await _client
        .from('durations')
        .select()
        .eq('period_id', periodId)
        .eq('is_active', true)
        .order('minutes', ascending: true);
    return data.map(DurationModel.fromJson).toList();
  }

  Future<PricingPeriod> createPricingPeriod(PricingPeriod period) async {
    final data = await _client
        .from('pricing_periods')
        .insert(period.toJson())
        .select()
        .single();
    return PricingPeriod.fromJson(data);
  }

  Future<void> updatePricingPeriod(PricingPeriod period) async {
    await _client
        .from('pricing_periods')
        .update(period.toJson())
        .eq('id', period.id);
  }

  /// Soft-deactivates when any of the season's tiers are referenced by
  /// booking history; hard-deletes otherwise (cascade removes its tiers).
  Future<void> deletePricingPeriod(String id) async {
    final tiers =
        await _client.from('durations').select('id').eq('period_id', id);
    final tierIds =
        tiers.map((row) => row['id']! as String).toList(growable: false);
    var used = false;
    if (tierIds.isNotEmpty) {
      final bookings = await _client
          .from('bookings')
          .select('id')
          .inFilter('duration_id', tierIds)
          .limit(1);
      used = bookings.isNotEmpty;
    }
    if (used) {
      await _client
          .from('pricing_periods')
          .update({'is_active': false}).eq('id', id);
    } else {
      await _client.from('pricing_periods').delete().eq('id', id);
    }
  }

  /// Copies all active seasons of [sourceResourceId] — date ranges, hourly
  /// overrides AND their tiers — onto [targetResourceId]. Fails up-front
  /// (writing nothing) when any copied range would overlap an existing one.
  Future<void> copyPricingFrom({
    required String sourceResourceId,
    required String targetResourceId,
  }) async {
    final source = await getPricingPeriods(sourceResourceId);
    if (source.isEmpty) {
      throw PricingCopyException(
        'That resource has no pricing seasons to copy.',
      );
    }
    final existing = await getPricingPeriods(targetResourceId);
    final conflicts = findOverlapConflicts(existing, source);
    if (conflicts.isNotEmpty) {
      throw PricingCopyException(
        'Cannot copy — overlapping seasons:\n${conflicts.join('\n')}',
      );
    }
    for (final p in source) {
      final created = await createPricingPeriod(
        PricingPeriod(
          id: '',
          resourceId: targetResourceId,
          name: p.name,
          startDate: p.startDate,
          endDate: p.endDate,
          hourlyRate: p.hourlyRate,
        ),
      );
      final tiers = await getDurationsForPeriod(p.id);
      if (tiers.isNotEmpty) {
        await _client.from('durations').insert([
          for (final t in tiers)
            {
              'resource_id': targetResourceId,
              'period_id': created.id,
              'label': t.label,
              'minutes': t.minutes,
              'price': t.price,
              'is_active': true,
            },
        ]);
      }
    }
  }

  // Per-weekday trading hours
  Future<List<ResourceHours>> getResourceHours(String resourceId) async {
    final data = await _client
        .from('resource_hours')
        .select()
        .eq('resource_id', resourceId)
        .order('weekday');
    return data.map(ResourceHours.fromJson).toList();
  }

  /// Replaces the resource's weekly schedule (one row per weekday).
  Future<void> upsertResourceHours(
    String resourceId,
    List<ResourceHours> hours,
  ) async {
    await _client.from('resource_hours').upsert(
          hours.map((h) => h.toJson()).toList(),
          onConflict: 'resource_id,weekday',
        );
  }

  // Add-ons
  Future<List<ResourceAddon>> getAddons(
    String resourceId, {
    bool activeOnly = true,
  }) async {
    var query =
        _client.from('resource_addons').select().eq('resource_id', resourceId);
    if (activeOnly) query = query.eq('is_active', true);
    final data = await query.order('name');
    return data.map(ResourceAddon.fromJson).toList();
  }

  Future<ResourceAddon> createAddon(ResourceAddon addon) async {
    final data = await _client
        .from('resource_addons')
        .insert(addon.toJson())
        .select()
        .single();
    return ResourceAddon.fromJson(data);
  }

  Future<void> updateAddon(ResourceAddon addon) async {
    await _client
        .from('resource_addons')
        .update(addon.toJson())
        .eq('id', addon.id);
  }

  /// Soft-deactivates when the add-on is referenced by past bookings
  /// (booking_addons keeps snapshots either way); hard-deletes otherwise.
  Future<void> deleteAddon(String id) async {
    final used = await _client
        .from('booking_addons')
        .select('id')
        .eq('addon_id', id)
        .limit(1);
    if (used.isEmpty) {
      await _client.from('resource_addons').delete().eq('id', id);
    } else {
      await _client
          .from('resource_addons')
          .update({'is_active': false}).eq('id', id);
    }
  }

  // Slot Blocks
  Future<List<SlotBlock>> getSlotBlocks(
    String resourceId,
    DateTime start,
    DateTime end,
  ) async {
    final data = await _client
        .from('slot_blocks')
        .select()
        .eq('resource_id', resourceId)
        .gte('end_time', start.toUtc().toIso8601String())
        .lte('start_time', end.toUtc().toIso8601String());
    return data.map(SlotBlock.fromJson).toList();
  }

  Future<List<SlotBlock>> getTenantSlotBlocks(String tenantId) async {
    final data = await _client
        .from('slot_blocks')
        .select('*, resources!inner(name, tenant_id)')
        .eq('resources.tenant_id', tenantId)
        .order('start_time');
    return (data as List)
        .map((e) => SlotBlock.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Busy ranges (bookings + maintenance blocks) for a resource via the
  /// get_busy_slots RPC. Works under RLS and returns no booking PII.
  Future<List<BusySlot>> getBusySlots(
    String resourceId,
    DateTime start,
    DateTime end,
  ) async {
    final data = await _client.rpc<List<dynamic>>(
      'get_busy_slots',
      params: {
        'p_resource_id': resourceId,
        'p_from': start.toUtc().toIso8601String(),
        'p_to': end.toUtc().toIso8601String(),
      },
    );
    return data
        .map((e) => BusySlot.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<SlotBlock> createSlotBlock(SlotBlock block) async {
    final data = await _client
        .from('slot_blocks')
        .insert(block.toJson())
        .select()
        .single();
    return SlotBlock.fromJson(data);
  }

  Future<void> deleteSlotBlock(String id) async {
    await _client.from('slot_blocks').delete().eq('id', id);
  }
}
