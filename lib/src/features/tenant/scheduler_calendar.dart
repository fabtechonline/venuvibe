import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:venue_vibe/src/core/supabase_config.dart';
import 'package:venue_vibe/src/models/slot_block.dart';
import 'package:venue_vibe/src/repositories/booking_repository.dart';
import 'package:venue_vibe/src/repositories/resource_repository.dart';
import 'package:venue_vibe/src/theme/app_theme.dart';
import 'package:venue_vibe/src/utils/currency_formatter.dart';

class SchedulerCalendar extends ConsumerStatefulWidget {
  const SchedulerCalendar({super.key});

  @override
  ConsumerState<SchedulerCalendar> createState() => _SchedulerCalendarState();
}

class _SchedulerCalendarState extends ConsumerState<SchedulerCalendar> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tenantBookingsAsync = ref.watch(tenantBookingsProvider);
    final timeFormat = DateFormat.jm();
    final currencyCode = ref.watch(currencyCodeProvider);
    final dayBlocks =
        (ref.watch(tenantSlotBlocksProvider).valueOrNull ?? <SlotBlock>[])
            .where((b) => isSameDay(b.startTime, _selectedDay))
            .toList()
          ..sort((a, b) => a.startTime.compareTo(b.startTime));

    return Scaffold(
      appBar: AppBar(title: const Text('Scheduler')),
      body: Column(
        children: [
          // ─── Calendar ───
          Card(
            margin: const EdgeInsets.all(12),
            child: TableCalendar(
              firstDay: DateTime.now().subtract(const Duration(days: 30)),
              lastDay: DateTime.now().add(const Duration(days: 180)),
              focusedDay: _focusedDay,
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              onDaySelected: (selected, focused) {
                setState(() {
                  _selectedDay = selected;
                  _focusedDay = focused;
                });
              },
              calendarStyle: CalendarStyle(
                selectedDecoration: const BoxDecoration(
                  color: AppTheme.primaryBlue,
                  shape: BoxShape.circle,
                ),
                todayDecoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
              ),
              headerStyle: const HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
              ),
            ),
          ),

          // ─── Day Bookings ───
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  DateFormat('EEEE, MMMM d').format(_selectedDay),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _showBlockDialog(context),
                  icon: const Icon(Icons.block, size: 16),
                  label: const Text('Block Slot'),
                ),
              ],
            ),
          ),

          Expanded(
            child: tenantBookingsAsync.when(
              data: (bookings) {
                final dayBookings = bookings
                    .where((b) => isSameDay(b.startTime, _selectedDay))
                    .toList()
                  ..sort((a, b) => a.startTime.compareTo(b.startTime));

                if (dayBookings.isEmpty && dayBlocks.isEmpty) {
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
                          'Nothing scheduled on this day',
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  );
                }

                return ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final blk in dayBlocks)
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
                    for (final b in dayBookings)
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
      builder: (_) => _BlockSlotDialog(day: _selectedDay),
    );
  }
}

class _BlockSlotDialog extends ConsumerStatefulWidget {
  const _BlockSlotDialog({required this.day});
  final DateTime day;

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
      title: const Text('Block Time Slot'),
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
