import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:venue_vibe/src/core/supabase_config.dart';
import 'package:venue_vibe/src/models/resource.dart';
import 'package:venue_vibe/src/models/resource_hours.dart';
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
  static const _maxPhotos = 10;
  List<ResourceHours> _week = [];
  int _minBookingMinutes = 30;
  int _bufferMinutes = 0;
  // Edited in Pricing & Rules; carried through here so saves don't clobber.
  bool _customSelectorEnabled = false;
  double? _hourlyRate;
  bool _isLoading = false;
  bool _uploadingImage = false;
  bool _isEdit = false;

  @override
  void initState() {
    super.initState();
    _week = _defaultWeek('07:00', '23:00');
    if (widget.resourceId != null) {
      _isEdit = true;
      _loadResource();
    }
  }

  List<ResourceHours> _defaultWeek(String open, String close) => [
        for (var d = 1; d <= 7; d++)
          ResourceHours(
            resourceId: widget.resourceId ?? '',
            weekday: d,
            openTime: open,
            closeTime: close,
          ),
      ];

  Future<void> _loadResource() async {
    final repo = ref.read(resourceRepositoryProvider);
    final r = await repo.getResource(widget.resourceId!);
    final hours = await repo.getResourceHours(widget.resourceId!);
    _nameController.text = r.name;
    _descController.text = r.description ?? '';
    _capacityController.text = r.capacity.toString();
    _selectedCategoryId = r.categoryId;
    _amenities.addAll(r.amenities);
    _images.addAll(r.images);
    _minBookingMinutes = r.minBookingMinutes;
    _bufferMinutes = r.bufferMinutes;
    _customSelectorEnabled = r.customSelectorEnabled;
    _hourlyRate = r.hourlyRate;
    _week = _defaultWeek(r.openTime, r.closeTime);
    for (final h in hours) {
      _week[h.weekday - 1] = h;
    }
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

      // Legacy single window = the outer envelope of the weekly schedule,
      // so anything reading only open_time/close_time degrades gracefully.
      final openDays = _week.where((d) => !d.isClosed).toList();
      final legacyOpen = openDays.isEmpty
          ? '07:00'
          : openDays
              .map((d) => d.openTime)
              .reduce((a, b) => a.compareTo(b) <= 0 ? a : b);
      final legacyClose = openDays.isEmpty
          ? '23:00'
          : openDays
              .map((d) => d.closeTime)
              .reduce((a, b) => a.compareTo(b) >= 0 ? a : b);

      final resource = Resource(
        id: widget.resourceId ?? '',
        tenantId: tenant.id,
        categoryId: _selectedCategoryId ?? '',
        name: _nameController.text.trim(),
        description: _descController.text.trim(),
        capacity: int.tryParse(_capacityController.text) ?? 10,
        amenities: _amenities,
        images: _images,
        openTime: legacyOpen,
        closeTime: legacyClose,
        minBookingMinutes: _minBookingMinutes,
        bufferMinutes: _bufferMinutes,
        customSelectorEnabled: _customSelectorEnabled,
        hourlyRate: _hourlyRate,
        createdAt: DateTime.now(),
      );

      String resourceId;
      if (_isEdit) {
        await repo.updateResource(resource);
        resourceId = widget.resourceId!;
        ref.invalidate(resourceProvider(resourceId));
      } else {
        final created = await repo.createResource(resource);
        resourceId = created.id;
      }

      await repo.upsertResourceHours(resourceId, [
        for (final d in _week)
          ResourceHours(
            resourceId: resourceId,
            weekday: d.weekday,
            isClosed: d.isClosed,
            openTime: d.openTime,
            closeTime: d.closeTime,
            breakStart: d.breakStart,
            breakEnd: d.breakEnd,
          ),
      ]);
      ref
        ..invalidate(allResourcesProvider)
        ..invalidate(tenantResourcesProvider)
        ..invalidate(resourceHoursProvider(resourceId));
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

  Future<String?> _pickHHMM(String initial) async {
    final parts = initial.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.tryParse(parts.first) ?? 7,
        minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
      ),
    );
    if (picked == null) return null;
    return '${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}';
  }

  void _setDay(int index, ResourceHours day) =>
      setState(() => _week[index] = day);

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

                // ─── Trading Hours (per weekday, optional break) ───
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Trading Hours',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        final mon = _week[0];
                        setState(() {
                          for (var i = 1; i < 7; i++) {
                            _week[i] = ResourceHours(
                              resourceId: mon.resourceId,
                              weekday: i + 1,
                              isClosed: mon.isClosed,
                              openTime: mon.openTime,
                              closeTime: mon.closeTime,
                              breakStart: mon.breakStart,
                              breakEnd: mon.breakEnd,
                            );
                          }
                        });
                      },
                      icon: const Icon(Icons.copy_all, size: 16),
                      label: const Text('Copy Mon to all'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                for (var i = 0; i < 7; i++)
                  _DayHoursRow(
                    day: _week[i],
                    onChanged: (d) => _setDay(i, d),
                    pickTime: _pickHHMM,
                  ),
                const SizedBox(height: 24),

                // ─── Booking Rules ───
                Text('Booking Rules', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _minBookingMinutes,
                        decoration: const InputDecoration(
                          labelText: 'Minimum booking',
                        ),
                        items: const [
                          DropdownMenuItem(value: 15, child: Text('15 min')),
                          DropdownMenuItem(value: 30, child: Text('30 min')),
                          DropdownMenuItem(value: 45, child: Text('45 min')),
                          DropdownMenuItem(value: 60, child: Text('1 hour')),
                          DropdownMenuItem(value: 90, child: Text('1.5 hours')),
                          DropdownMenuItem(value: 120, child: Text('2 hours')),
                          DropdownMenuItem(value: 180, child: Text('3 hours')),
                          DropdownMenuItem(value: 240, child: Text('4 hours')),
                        ],
                        onChanged: (v) =>
                            setState(() => _minBookingMinutes = v ?? 30),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _bufferMinutes,
                        decoration: const InputDecoration(
                          labelText: 'Buffer between bookings',
                        ),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('None')),
                          DropdownMenuItem(value: 5, child: Text('5 min')),
                          DropdownMenuItem(value: 10, child: Text('10 min')),
                          DropdownMenuItem(value: 15, child: Text('15 min')),
                          DropdownMenuItem(value: 20, child: Text('20 min')),
                          DropdownMenuItem(value: 30, child: Text('30 min')),
                          DropdownMenuItem(value: 45, child: Text('45 min')),
                          DropdownMenuItem(value: 60, child: Text('1 hour')),
                        ],
                        onChanged: (v) =>
                            setState(() => _bufferMinutes = v ?? 0),
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
                Row(
                  children: [
                    Expanded(
                      child: Text('Photos', style: theme.textTheme.titleMedium),
                    ),
                    Text(
                      '${_images.length}/$_maxPhotos',
                      style: TextStyle(
                        color: _images.length >= _maxPhotos
                            ? AppTheme.warningOrange
                            : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
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
                      if (_images.length < _maxPhotos)
                        GestureDetector(
                          onTap: _uploadingImage ? null : _pickAndUpload,
                          child: Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(
                              color:
                                  AppTheme.primaryBlue.withValues(alpha: 0.06),
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

/// One weekday row of the trading-hours editor: closed switch, open/close
/// pickers and an optional break (lunch) window.
class _DayHoursRow extends StatelessWidget {
  const _DayHoursRow({
    required this.day,
    required this.onChanged,
    required this.pickTime,
  });
  final ResourceHours day;
  final ValueChanged<ResourceHours> onChanged;
  final Future<String?> Function(String initial) pickTime;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: Text(
              day.weekdayName.substring(0, 3),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (day.isClosed)
            Expanded(
              child: Text('Closed', style: TextStyle(color: Colors.grey[500])),
            )
          else
            Expanded(
              child: Wrap(
                spacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _TimeChip(
                    label: day.openTime,
                    onTap: () async {
                      final t = await pickTime(day.openTime);
                      if (t != null) onChanged(day.copyWith(openTime: t));
                    },
                  ),
                  const Text('–'),
                  _TimeChip(
                    label: day.closeTime,
                    onTap: () async {
                      final t = await pickTime(day.closeTime);
                      if (t != null) onChanged(day.copyWith(closeTime: t));
                    },
                  ),
                  if (day.hasBreak) ...[
                    const SizedBox(width: 2),
                    InputChip(
                      label: Text(
                        'Break ${day.breakStart}–${day.breakEnd}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      visualDensity: VisualDensity.compact,
                      onPressed: () async {
                        final s = await pickTime(day.breakStart!);
                        if (s == null) return;
                        final e = await pickTime(day.breakEnd!);
                        if (e == null) return;
                        onChanged(day.copyWith(breakStart: s, breakEnd: e));
                      },
                      onDeleted: () =>
                          onChanged(day.copyWith(clearBreak: true)),
                    ),
                  ] else
                    IconButton(
                      tooltip: 'Add break (e.g. lunch)',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.free_breakfast_outlined, size: 18),
                      onPressed: () async {
                        final s = await pickTime('13:00');
                        if (s == null) return;
                        final e = await pickTime('14:00');
                        if (e == null) return;
                        onChanged(day.copyWith(breakStart: s, breakEnd: e));
                      },
                    ),
                ],
              ),
            ),
          Switch(
            value: !day.isClosed,
            onChanged: (open) => onChanged(day.copyWith(isClosed: !open)),
          ),
        ],
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
      onPressed: onTap,
    );
  }
}
