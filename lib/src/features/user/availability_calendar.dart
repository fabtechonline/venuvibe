import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:venue_vibe/src/core/supabase_config.dart';
import 'package:venue_vibe/src/models/busy_slot.dart';
import 'package:venue_vibe/src/models/duration_model.dart';
import 'package:venue_vibe/src/models/resource.dart';
import 'package:venue_vibe/src/models/resource_hours.dart';
import 'package:venue_vibe/src/repositories/resource_repository.dart';
import 'package:venue_vibe/src/theme/app_theme.dart';
import 'package:venue_vibe/src/utils/currency_formatter.dart';
import 'package:venue_vibe/src/utils/pricing.dart';
import 'package:venue_vibe/src/utils/slot_generator.dart';

enum _PickMode { slots, custom }

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
  _PickMode _mode = _PickMode.slots;
  TimeOfDay? _customStart;
  TimeOfDay? _customEnd;

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

  /// Guests can browse availability, but booking needs an account.
  /// Returns true (and routes to sign-in) when the user must log in first.
  bool _requireSignIn() {
    if (SupabaseConfig.client.auth.currentUser != null) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sign in to book this venue.')),
    );
    final here =
        Uri.encodeComponent('/resource/${widget.resourceId}/availability');
    context.go('/login?from=$here');
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final durationsAsync =
        ref.watch(resourceDurationsProvider(widget.resourceId));
    final resource = ref.watch(resourceProvider(widget.resourceId)).valueOrNull;
    final hours =
        ref.watch(resourceHoursProvider(widget.resourceId)).valueOrNull ??
            const <ResourceHours>[];

    final windows = resource == null
        ? const <DayWindow>[]
        : windowsForWeekday(hours, _selectedDay.weekday, resource);
    final customEnabled = (resource?.customSelectorEnabled ?? false) &&
        resource?.hourlyRate != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Time'),
      ),
      body: Column(
        children: [
          // ─── Calendar ───
          Card(
            margin: const EdgeInsets.all(12),
            child: TableCalendar<Object>(
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
                  _customStart = null;
                  _customEnd = null;
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

          // ─── Slots | Custom toggle (when the venue allows custom) ───
          if (customEnabled)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SegmentedButton<_PickMode>(
                segments: const [
                  ButtonSegment(
                    value: _PickMode.slots,
                    icon: Icon(Icons.grid_view, size: 16),
                    label: Text('Time slots'),
                  ),
                  ButtonSegment(
                    value: _PickMode.custom,
                    icon: Icon(Icons.tune, size: 16),
                    label: Text('Custom time'),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() => _mode = s.first),
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          if (customEnabled) const SizedBox(height: 8),

          if (_mode == _PickMode.custom && customEnabled)
            Expanded(
              child: _CustomRangePanel(
                resource: resource!,
                windows: windows,
                busy: _busy,
                day: _selectedDay,
                start: _customStart,
                end: _customEnd,
                onPickStart: () async {
                  final t = await showTimePicker(
                    context: context,
                    initialTime:
                        _customStart ?? const TimeOfDay(hour: 9, minute: 0),
                  );
                  if (t != null) setState(() => _customStart = t);
                },
                onPickEnd: () async {
                  final t = await showTimePicker(
                    context: context,
                    initialTime:
                        _customEnd ?? const TimeOfDay(hour: 11, minute: 0),
                  );
                  if (t != null) setState(() => _customEnd = t);
                },
                onRequest: (start, end, price) {
                  if (_requireSignIn()) return;
                  final hours =
                      (end.difference(start).inMinutes / 60).toStringAsFixed(1);
                  context.push(
                    '/checkout',
                    extra: {
                      'resourceId': widget.resourceId,
                      'startTime': start,
                      'endTime': end,
                      'durationLabel': 'Custom (${hours}h)',
                      'price': price,
                      'isCustom': true,
                    },
                  );
                },
              ),
            )
          else ...[
            // ─── Duration Selector (tiers below the minimum are hidden) ───
            SizedBox(
              height: 52,
              child: durationsAsync.when(
                data: (allDurs) {
                  final minMinutes = resource?.minBookingMinutes ?? 0;
                  final durs =
                      allDurs.where((d) => d.minutes >= minMinutes).toList();
                  if (durs.isNotEmpty &&
                      (_selectedDuration == null ||
                          !durs.any((d) => d.id == _selectedDuration!.id))) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() => _selectedDuration = durs.first);
                      }
                    });
                  }
                  if (durs.isEmpty) {
                    return Center(
                      child: Text(
                        'No bookable durations configured',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    );
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
                  : _SlotsGrid(
                      windows: windows,
                      busy: _busy,
                      day: _selectedDay,
                      resource: resource,
                      duration: _selectedDuration,
                      onTapSlot: (start, end) {
                        if (_requireSignIn()) return;
                        context.push(
                          '/checkout',
                          extra: {
                            'resourceId': widget.resourceId,
                            'startTime': start,
                            'endTime': end,
                            'durationLabel': _selectedDuration!.label,
                            'price': _selectedDuration!.price,
                            'durationId': _selectedDuration!.id,
                          },
                        );
                      },
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SlotsGrid extends StatelessWidget {
  const _SlotsGrid({
    required this.windows,
    required this.busy,
    required this.day,
    required this.resource,
    required this.duration,
    required this.onTapSlot,
  });
  final List<DayWindow> windows;
  final List<BusySlot> busy;
  final DateTime day;
  final Resource? resource;
  final DurationModel? duration;
  final void Function(DateTime start, DateTime end) onTapSlot;

  @override
  Widget build(BuildContext context) {
    if (windows.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storefront_outlined, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(
              'Closed on this day',
              style: TextStyle(color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    final slots = generateSlots(
      day: day,
      windows: windows,
      slotMinutes: duration?.minutes ?? 60,
      busy: busy,
      bufferMinutes: resource?.bufferMinutes ?? 0,
    );
    if (slots.isEmpty) {
      return Center(
        child: Text(
          'No slots fit this duration today',
          style: TextStyle(color: Colors.grey[500]),
        ),
      );
    }

    final timeFormat = DateFormat.Hm();
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 2.2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: slots.length,
      itemBuilder: (context, index) {
        final slot = slots[index];
        final status = slot.status;
        final isAvailable = status == 'available';

        Color bgColor;
        Color textColor;
        switch (status) {
          case 'available':
            bgColor = AppTheme.successGreen.withValues(alpha: 0.12);
            textColor = AppTheme.successGreen;
          case 'booked':
            bgColor = AppTheme.errorRed.withValues(alpha: 0.12);
            textColor = AppTheme.errorRed;
          case 'maintenance':
            bgColor = AppTheme.neutralGrey.withValues(alpha: 0.12);
            textColor = AppTheme.neutralGrey;
          case 'pending':
            bgColor = AppTheme.warningOrange.withValues(alpha: 0.12);
            textColor = AppTheme.warningOrange;
          default:
            bgColor = Colors.grey.shade100;
            textColor = Colors.grey;
        }

        return Material(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: isAvailable && duration != null
                ? () => onTapSlot(slot.start, slot.end)
                : null,
            borderRadius: BorderRadius.circular(12),
            child: Center(
              child: Text(
                '${timeFormat.format(slot.start)}\n'
                '${timeFormat.format(slot.end)}',
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
    );
  }
}

/// Custom date/time-range request: pick start & end, see the live price
/// (hourly rate pro-rated), validated against hours, breaks, busy slots and
/// the venue's minimum duration. The venue approves before payment.
class _CustomRangePanel extends ConsumerWidget {
  const _CustomRangePanel({
    required this.resource,
    required this.windows,
    required this.busy,
    required this.day,
    required this.start,
    required this.end,
    required this.onPickStart,
    required this.onPickEnd,
    required this.onRequest,
  });
  final Resource resource;
  final List<DayWindow> windows;
  final List<BusySlot> busy;
  final DateTime day;
  final TimeOfDay? start;
  final TimeOfDay? end;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final void Function(DateTime start, DateTime end, double price) onRequest;

  DateTime _at(TimeOfDay t) =>
      DateTime(day.year, day.month, day.day, t.hour, t.minute);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cc = ref.watch(currencyCodeProvider);
    final fmt = DateFormat.jm();

    DateTime? s;
    DateTime? e;
    String? problem;
    double? price;
    if (start != null && end != null) {
      s = _at(start!);
      e = _at(end!);
      problem = validateCustomRange(
        start: s,
        end: e,
        windows: windows,
        busy: busy,
        minBookingMinutes: resource.minBookingMinutes,
        bufferMinutes: resource.bufferMinutes,
      );
      if (problem == null) {
        price = customBasePrice(
          resource.hourlyRate!,
          e.difference(s).inMinutes,
        );
      }
    }

    final hoursLabel = windows.isEmpty
        ? 'Closed on this day'
        : windows.map((w) => '${w.open}–${w.close}').join('  &  ');

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Choose your own time',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Hours: $hoursLabel · Min '
                    '${resource.minBookingMinutes} min · '
                    '${formatPrice(resource.hourlyRate ?? 0, cc)}/hour',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onPickStart,
                          icon: const Icon(Icons.schedule, size: 18),
                          label: Text(
                            start == null ? 'Start' : fmt.format(_at(start!)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onPickEnd,
                          icon: const Icon(Icons.schedule, size: 18),
                          label: Text(
                            end == null ? 'End' : fmt.format(_at(end!)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (problem != null)
                    Text(
                      problem,
                      style: const TextStyle(color: AppTheme.errorRed),
                    )
                  else if (price != null)
                    Text(
                      'Price: ${formatPrice(price, cc)} '
                      '(excl. add-ons & platform fee)',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: AppTheme.primaryBlue,
                      ),
                    ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.warningOrange.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          size: 18,
                          color: AppTheme.warningOrange,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Custom bookings need the venue’s approval. '
                            'You’ll only pay once it’s accepted.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[800],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: price == null || s == null || e == null
                          ? null
                          : () => onRequest(s!, e!, price!),
                      icon: const Icon(Icons.send, size: 18),
                      label: const Text('Request booking'),
                    ),
                  ),
                ],
              ),
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
