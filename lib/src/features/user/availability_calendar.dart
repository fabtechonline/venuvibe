import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:venue_vibe/src/models/busy_slot.dart';
import 'package:venue_vibe/src/models/duration_model.dart';
import 'package:venue_vibe/src/models/resource.dart';
import 'package:venue_vibe/src/repositories/resource_repository.dart';
import 'package:venue_vibe/src/theme/app_theme.dart';
import 'package:venue_vibe/src/utils/currency_formatter.dart';

class AvailabilityCalendar extends ConsumerStatefulWidget {
  const AvailabilityCalendar({required this.resourceId, super.key});
  final String resourceId;

  @override
  ConsumerState<AvailabilityCalendar> createState() =>
      _AvailabilityCalendarState();
}

class _AvailabilityCalendarState extends ConsumerState<AvailabilityCalendar> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  CalendarFormat _calendarFormat = CalendarFormat.week;
  List<BusySlot> _busy = [];
  DurationModel? _selectedDuration;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAvailability();
  }

  Future<void> _loadAvailability() async {
    setState(() => _isLoading = true);
    final dayStart =
        DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    try {
      final busy = await ref
          .read(resourceRepositoryProvider)
          .getBusySlots(widget.resourceId, dayStart, dayEnd);
      setState(() {
        _busy = busy;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  String _getSlotStatus(DateTime start, DateTime end) {
    String? status;
    for (final b in _busy) {
      if (start.isBefore(b.end) && end.isAfter(b.start)) {
        if (b.kind == 'maintenance') return 'maintenance';
        status = b.kind; // 'booked' or 'pending'
      }
    }
    return status ?? 'available';
  }

  List<Map<String, dynamic>> _generateTimeSlots(Resource? resource) {
    final slots = <Map<String, dynamic>>[];
    final dayStart = DateTime(
      _selectedDay.year,
      _selectedDay.month,
      _selectedDay.day,
      resource?.openHour ?? 7,
      resource?.openMinute ?? 0,
    );
    final dayEnd = DateTime(
      _selectedDay.year,
      _selectedDay.month,
      _selectedDay.day,
      resource?.closeHour ?? 23,
      resource?.closeMinute ?? 0,
    );
    final slotMinutes = _selectedDuration?.minutes ?? 60;

    var current = dayStart;
    while (current.add(Duration(minutes: slotMinutes)).isBefore(dayEnd) ||
        current.add(Duration(minutes: slotMinutes)).isAtSameMomentAs(dayEnd)) {
      final end = current.add(Duration(minutes: slotMinutes));
      final status = _getSlotStatus(current, end);
      final isPast = current.isBefore(DateTime.now());
      slots.add({
        'start': current,
        'end': end,
        'status': isPast ? 'past' : status,
      });
      current = end;
    }
    return slots;
  }

  @override
  Widget build(BuildContext context) {
    final durationsAsync =
        ref.watch(resourceDurationsProvider(widget.resourceId));
    final resource =
        ref.watch(resourceProvider(widget.resourceId)).valueOrNull;
    final slots = _generateTimeSlots(resource);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Time'),
      ),
      body: Column(
        children: [
          // ─── Calendar ───
          Card(
            margin: const EdgeInsets.all(12),
            child: TableCalendar(
              firstDay: DateTime.now(),
              lastDay: DateTime.now().add(const Duration(days: 90)),
              focusedDay: _focusedDay,
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              calendarFormat: _calendarFormat,
              onFormatChanged: (format) =>
                  setState(() => _calendarFormat = format),
              onDaySelected: (selected, focused) {
                setState(() {
                  _selectedDay = selected;
                  _focusedDay = focused;
                });
                _loadAvailability();
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
                formatButtonShowsNext: false,
                titleCentered: true,
              ),
            ),
          ),

          // ─── Duration Selector ───
          SizedBox(
            height: 52,
            child: durationsAsync.when(
              data: (durs) {
                if (durs.isNotEmpty && _selectedDuration == null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() => _selectedDuration = durs.first);
                    }
                  });
                }
                return ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: durs
                      .map(
                        (d) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(
                              '${d.label} - ${formatPriceShort(d.price, ref.watch(currencyCodeProvider))}',
                            ),
                            selected: _selectedDuration?.id == d.id,
                            onSelected: (_) {
                              setState(() => _selectedDuration = d);
                            },
                          ),
                        ),
                      )
                      .toList(),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
            ),
          ),

          const SizedBox(height: 8),

          // ─── Legend ───
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _LegendDot(color: AppTheme.successGreen, label: 'Available'),
                SizedBox(width: 12),
                _LegendDot(color: AppTheme.errorRed, label: 'Booked'),
                SizedBox(width: 12),
                _LegendDot(color: AppTheme.neutralGrey, label: 'Blocked'),
                SizedBox(width: 12),
                _LegendDot(color: AppTheme.warningOrange, label: 'Pending'),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // ─── Time Slots Grid ───
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 2.2,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: slots.length,
                    itemBuilder: (context, index) {
                      final slot = slots[index];
                      final status = slot['status'] as String;
                      final start = slot['start'] as DateTime;
                      final end = slot['end'] as DateTime;
                      final isAvailable = status == 'available';
                      final timeFormat = DateFormat.Hm();

                      Color bgColor;
                      Color textColor;
                      switch (status) {
                        case 'available':
                          bgColor =
                              AppTheme.successGreen.withValues(alpha: 0.12);
                          textColor = AppTheme.successGreen;
                        case 'booked':
                          bgColor = AppTheme.errorRed.withValues(alpha: 0.12);
                          textColor = AppTheme.errorRed;
                        case 'maintenance':
                          bgColor =
                              AppTheme.neutralGrey.withValues(alpha: 0.12);
                          textColor = AppTheme.neutralGrey;
                        case 'pending':
                          bgColor =
                              AppTheme.warningOrange.withValues(alpha: 0.12);
                          textColor = AppTheme.warningOrange;
                        default:
                          bgColor = Colors.grey.shade100;
                          textColor = Colors.grey;
                      }

                      return Material(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          onTap: isAvailable && _selectedDuration != null
                              ? () => context.push(
                                    '/checkout',
                                    extra: {
                                      'resourceId': widget.resourceId,
                                      'startTime': start,
                                      'endTime': end,
                                      'durationLabel': _selectedDuration!.label,
                                      'price': _selectedDuration!.price,
                                    },
                                  )
                              : null,
                          borderRadius: BorderRadius.circular(12),
                          child: Center(
                            child: Text(
                              '${timeFormat.format(start)}\n${timeFormat.format(end)}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: textColor,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}
