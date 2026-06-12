import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:venue_vibe/src/core/supabase_config.dart';
import 'package:venue_vibe/src/models/booking.dart';
import 'package:venue_vibe/src/models/slot_block.dart';
import 'package:venue_vibe/src/repositories/booking_repository.dart';
import 'package:venue_vibe/src/repositories/resource_repository.dart';
import 'package:venue_vibe/src/theme/app_theme.dart';
import 'package:venue_vibe/src/utils/currency_formatter.dart';

class SchedulerCalendar extends ConsumerStatefulWidget {
  const SchedulerCalendar({super.key, this.initialResourceId});
  final String? initialResourceId;

  @override
  ConsumerState<SchedulerCalendar> createState() => _SchedulerCalendarState();
}

class _SchedulerCalendarState extends ConsumerState<SchedulerCalendar> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _rangeStart = DateTime.now();
  DateTime? _rangeEnd;
  CalendarFormat _format = CalendarFormat.month;
  String? _resourceFilter; // null = all resources

  @override
  void initState() {
    super.initState();
    _resourceFilter = widget.initialResourceId;
  }

  @override
  void didUpdateWidget(SchedulerCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialResourceId != oldWidget.initialResourceId &&
        widget.initialResourceId != null) {
      _resourceFilter = widget.initialResourceId;
    }
  }

  DateTime _dayOnly(DateTime t) => DateTime(t.year, t.month, t.day);

  bool _inRange(DateTime t) {
    if (_rangeStart == null) return false;
    final d = _dayOnly(t);
    final s = _dayOnly(_rangeStart!);
    final e = _dayOnly(_rangeEnd ?? _rangeStart!);
    return !d.isBefore(s) && !d.isAfter(e);
  }

  bool get _isMultiDay =>
      _rangeEnd != null && !isSameDay(_rangeStart, _rangeEnd);

  String _rangeLabel() {
    if (_rangeStart == null) return 'Select a date';
    if (!_isMultiDay) {
      return DateFormat('EEEE, MMMM d').format(_rangeStart!);
    }
    final fmt = DateFormat('EEE, MMM d');
    return '${fmt.format(_rangeStart!)} – ${fmt.format(_rangeEnd!)}';
  }

  bool _matchesFilter(String? resourceId) =>
      _resourceFilter == null || resourceId == _resourceFilter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeFormat = DateFormat.jm();
    final currencyCode = ref.watch(currencyCodeProvider);
    final resources = ref.watch(tenantResourcesProvider).valueOrNull ?? [];
    // Opened from a resource card: lock onto that resource (no filter pills).
    final locked = widget.initialResourceId != null;
    var title = 'Scheduler';
    if (locked) {
      for (final r in resources) {
        if (r.id == widget.initialResourceId) {
          title = '${r.name} · Schedule';
          break;
        }
      }
    }
    final bookingsAsync = ref.watch(tenantBookingsProvider);
    final blocks =
        (ref.watch(tenantSlotBlocksProvider).valueOrNull ?? <SlotBlock>[])
            .where((b) => _matchesFilter(b.resourceId))
            .toList();
    final allBookings = bookingsAsync.valueOrNull ?? <Booking>[];

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          // ─── Resource Filter (hidden when locked to one resource) ───
          if (!locked)
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: const Text('All resources'),
                      selected: _resourceFilter == null,
                      onSelected: (_) => setState(() => _resourceFilter = null),
                    ),
                  ),
                  for (final r in resources)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(r.name),
                        selected: _resourceFilter == r.id,
                        onSelected: (_) =>
                            setState(() => _resourceFilter = r.id),
                      ),
                    ),
                ],
              ),
            ),

          // ─── Calendar (tap once = day, tap a second day = range) ───
          Card(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TableCalendar<Object>(
              firstDay: DateTime.now().subtract(const Duration(days: 365)),
              lastDay: DateTime.now().add(const Duration(days: 365)),
              focusedDay: _focusedDay,
              calendarFormat: _format,
              onFormatChanged: (f) => setState(() => _format = f),
              rangeStartDay: _rangeStart,
              rangeEndDay: _rangeEnd,
              rangeSelectionMode: RangeSelectionMode.toggledOn,
              onRangeSelected: (start, end, focused) {
                setState(() {
                  _rangeStart = start;
                  _rangeEnd = end;
                  _focusedDay = focused;
                });
              },
              eventLoader: (day) => <Object>[
                ...blocks.where((b) => isSameDay(b.startTime, day)),
                ...allBookings.where(
                  (b) =>
                      _matchesFilter(b.resourceId) &&
                      isSameDay(b.startTime, day),
                ),
              ],
              calendarStyle: CalendarStyle(
                rangeStartDecoration: const BoxDecoration(
                  color: AppTheme.primaryBlue,
                  shape: BoxShape.circle,
                ),
                rangeEndDecoration: const BoxDecoration(
                  color: AppTheme.primaryBlue,
                  shape: BoxShape.circle,
                ),
                rangeHighlightColor:
                    AppTheme.primaryBlue.withValues(alpha: 0.15),
                todayDecoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                markerDecoration: const BoxDecoration(
                  color: AppTheme.primaryBlue,
                  shape: BoxShape.circle,
                ),
                markersMaxCount: 3,
              ),
              headerStyle: const HeaderStyle(titleCentered: true),
            ),
          ),

          // ─── Selection header ───
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _rangeLabel(),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _showBlockDialog(context),
                  icon: const Icon(Icons.block, size: 16),
                  label: const Text('Block Slot'),
                ),
              ],
            ),
          ),

          // ─── Bookings & blocks in the selected range ───
          Expanded(
            child: bookingsAsync.when(
              data: (bookings) {
                final rangeBookings = bookings
                    .where(
                      (b) =>
                          _matchesFilter(b.resourceId) && _inRange(b.startTime),
                    )
                    .toList()
                  ..sort((a, b) => a.startTime.compareTo(b.startTime));
                final rangeBlocks = blocks
                    .where((b) => _inRange(b.startTime))
                    .toList()
                  ..sort((a, b) => a.startTime.compareTo(b.startTime));

                if (rangeBookings.isEmpty && rangeBlocks.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.event_available,
                          size: 48,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _resourceFilter == null
                              ? 'Nothing scheduled in this period'
                              : 'Nothing scheduled for this resource',
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  );
                }

                final days = <DateTime>{
                  for (final b in rangeBookings) _dayOnly(b.startTime),
                  for (final blk in rangeBlocks) _dayOnly(blk.startTime),
                }.toList()
                  ..sort();

                return ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final day in days) ...[
                      if (_isMultiDay)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
                          child: Text(
                            DateFormat('EEEE, MMMM d').format(day),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: Colors.grey[700],
                            ),
                          ),
                        ),
                      for (final blk in rangeBlocks
                          .where((b) => isSameDay(b.startTime, day)))
                        Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Container(
                              width: 4,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppTheme.neutralGrey,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            title: Text(blk.resourceName ?? 'Resource'),
                            subtitle: Text(
                              '${timeFormat.format(blk.startTime)} - '
                              '${timeFormat.format(blk.endTime)} · '
                              'Blocked (${blk.reason})',
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                color: AppTheme.errorRed,
                              ),
                              onPressed: () async {
                                await ref
                                    .read(resourceRepositoryProvider)
                                    .deleteSlotBlock(blk.id);
                                ref.invalidate(tenantSlotBlocksProvider);
                              },
                            ),
                          ),
                        ),
                      for (final b in rangeBookings
                          .where((b) => isSameDay(b.startTime, day)))
                        Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Container(
                              width: 4,
                              height: 40,
                              decoration: BoxDecoration(
                                color: b.status == 'confirmed'
                                    ? AppTheme.successGreen
                                    : AppTheme.warningOrange,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            title: Text(b.resourceName ?? 'Resource'),
                            subtitle: Text(
                              '${timeFormat.format(b.startTime)} - '
                              '${timeFormat.format(b.endTime)} · '
                              '${b.userName ?? "Customer"}',
                            ),
                            trailing: Text(
                              formatPrice(b.totalPrice, currencyCode),
                              style: const TextStyle(
                                color: AppTheme.primaryBlue,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }

  void _showBlockDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => _BlockSlotDialog(
        day: _rangeStart ?? DateTime.now(),
        initialResourceId: _resourceFilter,
      ),
    );
  }
}

class _BlockSlotDialog extends ConsumerStatefulWidget {
  const _BlockSlotDialog({required this.day, this.initialResourceId});
  final DateTime day;
  final String? initialResourceId;

  @override
  ConsumerState<_BlockSlotDialog> createState() => _BlockSlotDialogState();
}

class _BlockSlotDialogState extends ConsumerState<_BlockSlotDialog> {
  String? _resourceId;
  TimeOfDay _start = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 10, minute: 0);
  final _reasonController = TextEditingController(text: 'maintenance');
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _resourceId = widget.initialResourceId;
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  DateTime _at(TimeOfDay t) => DateTime(
        widget.day.year,
        widget.day.month,
        widget.day.day,
        t.hour,
        t.minute,
      );

  Future<void> _pick({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _start : _end,
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _start = picked;
      } else {
        _end = picked;
      }
    });
  }

  Future<void> _save() async {
    if (_resourceId == null) {
      setState(() => _error = 'Pick a resource');
      return;
    }
    final start = _at(_start);
    final end = _at(_end);
    if (!end.isAfter(start)) {
      setState(() => _error = 'End must be after start');
      return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final reason = _reasonController.text.trim();
      await ref.read(resourceRepositoryProvider).createSlotBlock(
            SlotBlock(
              id: '',
              resourceId: _resourceId!,
              startTime: start,
              endTime: end,
              reason: reason.isEmpty ? 'maintenance' : reason,
              createdBy: SupabaseConfig.client.auth.currentUser?.id,
              createdAt: DateTime.now(),
            ),
          );
      ref.invalidate(tenantSlotBlocksProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _isSaving = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final resourcesAsync = ref.watch(tenantResourcesProvider);
    final fmt = DateFormat.jm();
    return AlertDialog(
      title: Text(
        'Block Slot · ${DateFormat('MMM d').format(widget.day)}',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          resourcesAsync.when(
            data: (resources) => DropdownButtonFormField<String>(
              initialValue: _resourceId,
              decoration: const InputDecoration(labelText: 'Resource'),
              items: resources
                  .map(
                    (r) => DropdownMenuItem(value: r.id, child: Text(r.name)),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _resourceId = v),
            ),
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('$e'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pick(isStart: true),
                  child: Text('From  ${fmt.format(_at(_start))}'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pick(isStart: false),
                  child: Text('To  ${fmt.format(_at(_end))}'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reasonController,
            decoration: const InputDecoration(labelText: 'Reason'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: AppTheme.errorRed)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Block'),
        ),
      ],
    );
  }
}
