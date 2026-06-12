import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:venue_vibe/src/core/supabase_config.dart';
import 'package:venue_vibe/src/models/busy_slot.dart';
import 'package:venue_vibe/src/models/category.dart';
import 'package:venue_vibe/src/models/duration_model.dart';
import 'package:venue_vibe/src/models/resource.dart';
import 'package:venue_vibe/src/models/slot_block.dart';
import 'package:venue_vibe/src/repositories/tenant_repository.dart';

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
      tenants(name, address, city, phone, email),
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

  Future<void> toggleResource(String id, bool isActive) async {
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
        .order('minutes');
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

  Future<void> deleteDuration(String id) async {
    await _client.from('durations').delete().eq('id', id);
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
    final data = await _client.rpc(
      'get_busy_slots',
      params: {
        'p_resource_id': resourceId,
        'p_from': start.toUtc().toIso8601String(),
        'p_to': end.toUtc().toIso8601String(),
      },
    );
    return (data as List)
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
