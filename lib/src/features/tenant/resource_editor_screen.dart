import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:venue_vibe/src/core/supabase_config.dart';
import 'package:venue_vibe/src/models/resource.dart';
import 'package:venue_vibe/src/repositories/resource_repository.dart';
import 'package:venue_vibe/src/repositories/tenant_repository.dart';
import 'package:venue_vibe/src/theme/app_theme.dart';

class ResourceEditorScreen extends ConsumerStatefulWidget {
  const ResourceEditorScreen({super.key, this.resourceId});
  final String? resourceId;

  @override
  ConsumerState<ResourceEditorScreen> createState() =>
      _ResourceEditorScreenState();
}

class _ResourceEditorScreenState extends ConsumerState<ResourceEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _capacityController = TextEditingController(text: '10');
  final _amenityController = TextEditingController();
  String? _selectedCategoryId;
  final List<String> _amenities = [];
  final List<String> _images = [];
  String _openTime = '07:00';
  String _closeTime = '23:00';
  bool _isLoading = false;
  bool _uploadingImage = false;
  bool _isEdit = false;

  @override
  void initState() {
    super.initState();
    if (widget.resourceId != null) {
      _isEdit = true;
      _loadResource();
    }
  }

  Future<void> _loadResource() async {
    final r = await ref
        .read(resourceRepositoryProvider)
        .getResource(widget.resourceId!);
    _nameController.text = r.name;
    _descController.text = r.description ?? '';
    _capacityController.text = r.capacity.toString();
    _selectedCategoryId = r.categoryId;
    _amenities.addAll(r.amenities);
    _images.addAll(r.images);
    _openTime = r.openTime;
    _closeTime = r.closeTime;
    setState(() {});
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _capacityController.dispose();
    _amenityController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final tenant = await ref.read(currentTenantProvider.future);
      if (tenant == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No venue is linked to your account yet.'),
            ),
          );
        }
        return;
      }

      // Enforce the plan's resource limit on creation.
      if (!_isEdit) {
        final limit = await ref.read(tenantResourceLimitProvider.future);
        final existing = await ref.read(tenantResourcesProvider.future);
        if (existing.length >= limit) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  "You've reached your plan's limit of $limit "
                  "resource${limit == 1 ? '' : 's'}. Upgrade to add more.",
                ),
              ),
            );
          }
          return;
        }
      }

      final repo = ref.read(resourceRepositoryProvider);

      final resource = Resource(
        id: widget.resourceId ?? '',
        tenantId: tenant.id,
        categoryId: _selectedCategoryId ?? '',
        name: _nameController.text.trim(),
        description: _descController.text.trim(),
        capacity: int.tryParse(_capacityController.text) ?? 10,
        amenities: _amenities,
        images: _images,
        openTime: _openTime,
        closeTime: _closeTime,
        createdAt: DateTime.now(),
      );

      if (_isEdit) {
        await repo.updateResource(resource);
        ref.invalidate(resourceProvider(widget.resourceId!));
      } else {
        await repo.createResource(resource);
      }

      ref
        ..invalidate(allResourcesProvider)
        ..invalidate(tenantResourcesProvider);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickTime({required bool isOpen}) async {
    final parts = (isOpen ? _openTime : _closeTime).split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.tryParse(parts.first) ?? (isOpen ? 7 : 23),
        minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
      ),
    );
    if (picked == null) return;
    final formatted = '${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}';
    setState(() {
      if (isOpen) {
        _openTime = formatted;
      } else {
        _closeTime = formatted;
      }
    });
  }

  Future<void> _pickAndUpload() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 75,
    );
    if (picked == null) return;
    setState(() => _uploadingImage = true);
    try {
      final tenant = await ref.read(currentTenantProvider.future);
      if (tenant == null) throw Exception('No venue linked to your account');
      final bytes = await picked.readAsBytes();
      final ext =
          picked.name.contains('.') ? picked.name.split('.').last : 'jpg';
      final path = '${tenant.id}/${const Uuid().v4()}.$ext';
      final storage = SupabaseConfig.client.storage.from('resource-images');
      await storage.uploadBinary(
        path,
        bytes,
        fileOptions: const FileOptions(upsert: true),
      );
      setState(() => _images.add(storage.getPublicUrl(path)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categoriesAsync = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Resource' : 'New Resource'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Resource Name',
                    hintText: 'e.g. Tennis Court 1, Meeting Room A',
                  ),
                  validator: (v) =>
                      v == null || v.isEmpty ? 'Name is required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    hintText: 'Describe the space...',
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),

                // ─── Category Dropdown ───
                categoriesAsync.when(
                  data: (cats) => DropdownButtonFormField<String>(
                    initialValue: _selectedCategoryId,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: cats
                        .map(
                          (c) => DropdownMenuItem(
                            value: c.id,
                            child: Text(c.name),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _selectedCategoryId = v),
                    validator: (v) => v == null ? 'Category is required' : null,
                  ),
                  loading: () => const CircularProgressIndicator(),
                  error: (e, _) => Text('$e'),
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _capacityController,
                  decoration: const InputDecoration(labelText: 'Capacity'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 24),

                // ─── Operating Hours ───
                Text('Operating Hours', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickTime(isOpen: true),
                        icon: const Icon(Icons.schedule, size: 18),
                        label: Text('Opens  $_openTime'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickTime(isOpen: false),
                        icon: const Icon(Icons.schedule, size: 18),
                        label: Text('Closes  $_closeTime'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // ─── Amenities Builder ───
                Text('Amenities', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _amenityController,
                        decoration: const InputDecoration(
                          hintText: 'Add amenity (WiFi, Parking...)',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: () {
                        if (_amenityController.text.isNotEmpty) {
                          setState(() {
                            _amenities.add(_amenityController.text.trim());
                            _amenityController.clear();
                          });
                        }
                      },
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: _amenities
                      .map(
                        (a) => Chip(
                          label: Text(a),
                          onDeleted: () => setState(() => _amenities.remove(a)),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 24),

                // ─── Photos ───
                Text('Photos', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                SizedBox(
                  height: 96,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final url in _images)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  url,
                                  width: 96,
                                  height: 96,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: 2,
                                right: 2,
                                child: GestureDetector(
                                  onTap: () =>
                                      setState(() => _images.remove(url)),
                                  child: const CircleAvatar(
                                    radius: 11,
                                    backgroundColor: Colors.black54,
                                    child: Icon(
                                      Icons.close,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      GestureDetector(
                        onTap: _uploadingImage ? null : _pickAndUpload,
                        child: Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryBlue.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Center(
                            child: _uploadingImage
                                ? const CircularProgressIndicator(
                                    strokeWidth: 2,
                                  )
                                : const Icon(
                                    Icons.add_a_photo_outlined,
                                    color: AppTheme.primaryBlue,
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _save,
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(_isEdit ? 'Update Resource' : 'Create Resource'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
