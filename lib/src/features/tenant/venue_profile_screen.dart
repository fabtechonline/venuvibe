import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:venue_vibe/src/repositories/tenant_repository.dart';

/// Edit the venue's public details: contact person, phone, email and address.
/// Shown to customers on every resource's detail page.
class VenueProfileScreen extends ConsumerStatefulWidget {
  const VenueProfileScreen({super.key});

  @override
  ConsumerState<VenueProfileScreen> createState() => _VenueProfileScreenState();
}

class _VenueProfileScreenState extends ConsumerState<VenueProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  bool _loaded = false;
  bool _saving = false;
  String? _tenantId;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _contactCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _tenantId == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(tenantRepositoryProvider).updateTenantProfile(
        _tenantId!,
        {
          'name': _nameCtrl.text.trim(),
          'description': _descCtrl.text.trim(),
          'contact_person': _contactCtrl.text.trim(),
          'phone': _phoneCtrl.text.trim(),
          'email': _emailCtrl.text.trim(),
          'address': _addressCtrl.text.trim(),
          'city': _cityCtrl.text.trim(),
        },
      );
      ref.invalidate(currentTenantProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Venue profile saved')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tenantAsync = ref.watch(currentTenantProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Venue Profile')),
      body: tenantAsync.when(
        data: (tenant) {
          if (tenant == null) {
            return const Center(child: Text('No venue linked to your account'));
          }
          if (!_loaded) {
            _loaded = true;
            _tenantId = tenant.id;
            _nameCtrl.text = tenant.name;
            _descCtrl.text = tenant.description ?? '';
            _contactCtrl.text = tenant.contactPerson ?? '';
            _phoneCtrl.text = tenant.phone ?? '';
            _emailCtrl.text = tenant.email ?? '';
            _addressCtrl.text = tenant.address ?? '';
            _cityCtrl.text = tenant.city ?? '';
          }
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _nameCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Venue Name'),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _descCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Description'),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _contactCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Contact Person',
                        hintText: 'e.g. Marco Rossi',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _phoneCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Contact Number',
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _emailCtrl,
                      decoration: const InputDecoration(labelText: 'Email'),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _addressCtrl,
                      decoration: const InputDecoration(labelText: 'Address'),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _cityCtrl,
                      decoration: const InputDecoration(labelText: 'City'),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Save Profile'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}
