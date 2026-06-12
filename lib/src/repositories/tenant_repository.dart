import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:venue_vibe/src/core/supabase_config.dart';
import 'package:venue_vibe/src/models/category.dart';
import 'package:venue_vibe/src/models/platform_models.dart';
import 'package:venue_vibe/src/models/tenant.dart';

final tenantRepositoryProvider = Provider<TenantRepository>((ref) {
  return TenantRepository(SupabaseConfig.client);
});

final currentTenantProvider = FutureProvider<Tenant?>((ref) async {
  final userId = SupabaseConfig.client.auth.currentUser?.id;
  if (userId == null) return null;
  return ref.read(tenantRepositoryProvider).getTenantByOwner(userId);
});

final allTenantsProvider = FutureProvider<List<Tenant>>((ref) async {
  return ref.read(tenantRepositoryProvider).getAllTenants();
});

final platformSettingsProvider = FutureProvider<PlatformSettings?>((ref) async {
  return ref.read(tenantRepositoryProvider).getPlatformSettings();
});

final subscriptionPlansProvider =
    FutureProvider<List<SubscriptionPlan>>((ref) async {
  return ref.read(tenantRepositoryProvider).getSubscriptionPlans();
});

/// Max number of resources the current tenant may have, from their plan.
/// Falls back to the smallest plan's limit when no plan is assigned.
final tenantResourceLimitProvider = FutureProvider<int>((ref) async {
  final tenant = await ref.watch(currentTenantProvider.future);
  final plans = await ref.watch(subscriptionPlansProvider.future);
  if (tenant?.subscriptionPlanId != null) {
    for (final p in plans) {
      if (p.id == tenant!.subscriptionPlanId) return p.maxResources;
    }
  }
  if (plans.isEmpty) return 1;
  return plans.map((p) => p.maxResources).reduce((a, b) => a < b ? a : b);
});

final adminCategoriesProvider = FutureProvider<List<Category>>((ref) async {
  return ref.read(tenantRepositoryProvider).getAllCategories();
});

final allInvoicesProvider = FutureProvider<List<Invoice>>((ref) async {
  return ref.read(tenantRepositoryProvider).getAllInvoices();
});

final totalTenantsProvider = FutureProvider<int>((ref) async {
  return ref.read(tenantRepositoryProvider).getTotalTenants();
});

class TenantRepository {
  TenantRepository(this._client);
  final SupabaseClient _client;

  Future<Tenant?> getTenantByOwner(String ownerId) async {
    final data = await _client
        .from('tenants')
        .select()
        .eq('owner_id', ownerId)
        .maybeSingle();
    if (data == null) return null;
    return Tenant.fromJson(data);
  }

  Future<List<Tenant>> getAllTenants() async {
    final data = await _client.from('tenants').select().order('created_at');
    return data.map(Tenant.fromJson).toList();
  }

  Future<Tenant> createTenant(Tenant tenant) async {
    final data =
        await _client.from('tenants').insert(tenant.toJson()).select().single();
    return Tenant.fromJson(data);
  }

  Future<void> updateTenant(Tenant tenant) async {
    await _client.from('tenants').update(tenant.toJson()).eq('id', tenant.id);
  }

  Future<void> toggleTenantActive(String tenantId, bool isActive) async {
    await _client
        .from('tenants')
        .update({'is_active': isActive}).eq('id', tenantId);
  }

  Future<void> approveTenant(String tenantId) async {
    await _client.from('tenants').update({
      'status': 'approved',
      'is_active': true,
    }).eq('id', tenantId);
  }

  Future<void> suspendTenant(String tenantId) async {
    await _client.from('tenants').update({
      'status': 'suspended',
      'is_active': false,
    }).eq('id', tenantId);
  }

  // Platform Settings
  Future<PlatformSettings?> getPlatformSettings() async {
    // limit(1) keeps this resilient even if more than one row ever exists,
    // instead of throwing on a multi-row result.
    final data = await _client
        .from('platform_settings')
        .select()
        .order('created_at')
        .limit(1)
        .maybeSingle();
    if (data == null) return null;
    return PlatformSettings.fromJson(data);
  }

  Future<void> updatePlatformSettings(PlatformSettings settings) async {
    await _client
        .from('platform_settings')
        .update(settings.toJson())
        .eq('id', settings.id);
  }

  Future<void> upsertPlatformSettings(PlatformSettings settings) async {
    await _client.from('platform_settings').upsert(settings.toJson());
  }

  // Subscription Plans
  Future<List<SubscriptionPlan>> getSubscriptionPlans() async {
    final data = await _client
        .from('subscription_plans')
        .select()
        .eq('is_active', true)
        .order('price_monthly');
    return data.map(SubscriptionPlan.fromJson).toList();
  }

  Future<SubscriptionPlan> createPlan(SubscriptionPlan plan) async {
    final data = await _client
        .from('subscription_plans')
        .insert(plan.toJson())
        .select()
        .single();
    return SubscriptionPlan.fromJson(data);
  }

  Future<void> updatePlan(SubscriptionPlan plan) async {
    await _client
        .from('subscription_plans')
        .update(plan.toJson())
        .eq('id', plan.id);
  }

  // Categories (admin)
  Future<List<Category>> getAllCategories() async {
    final data = await _client.from('categories').select().order('sort_order');
    return data.map(Category.fromJson).toList();
  }

  Future<void> createCategory(Category category) async {
    await _client.from('categories').insert(category.toJson());
  }

  Future<void> updateCategory(Category category) async {
    await _client
        .from('categories')
        .update(category.toJson())
        .eq('id', category.id);
  }

  Future<void> deleteCategory(String id) async {
    await _client.from('categories').delete().eq('id', id);
  }

  // Stats
  Future<int> getTotalTenants() async {
    final data = await _client.from('tenants').select('id');
    return data.length;
  }

  Future<int> getTotalUsers() async {
    final data = await _client.from('profiles').select('id').eq('role', 'user');
    return data.length;
  }

  // Invoices
  Future<List<Invoice>> getAllInvoices() async {
    final data = await _client
        .from('invoices')
        .select('*, tenants(name)')
        .order('period_start', ascending: false);
    return (data as List)
        .map((e) => Invoice.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Generates pending invoices for every tenant for the given period via the
  /// admin-only generate_invoices RPC. Returns the number created.
  Future<int> generateInvoices(DateTime periodStart, DateTime periodEnd) async {
    final result = await _client.rpc(
      'generate_invoices',
      params: {
        'p_period_start': periodStart.toIso8601String().split('T').first,
        'p_period_end': periodEnd.toIso8601String().split('T').first,
      },
    );
    return (result as num?)?.toInt() ?? 0;
  }

  Future<void> updateInvoiceStatus(String id, String status) async {
    await _client.from('invoices').update({'status': status}).eq('id', id);
  }
}
