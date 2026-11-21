import 'package:flutter/material.dart';
import 'package:utc_calendar/utc_calendar.dart';

void main() => runApp(const CalendarExampleApp());

class _ExampleEvent extends CalendarEvent {
  _ExampleEvent({
    required super.id,
    required super.title,
    required super.start,
    required super.end,
    required this.color,
  });

  final Color color;
}

class CalendarExampleApp extends StatelessWidget {
  const CalendarExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: ThemeData(colorSchemeSeed: Colors.indigo),
    home: const CalendarExamplePage(),
  );
}

class CalendarExamplePage extends StatefulWidget {
  const CalendarExamplePage({super.key});

  @override
  State<CalendarExamplePage> createState() => _CalendarExamplePageState();
}

class _CalendarExamplePageState extends State<CalendarExamplePage> {
  DateTime _focusedDay = DateTime.utc(2026, 10, 22);
  CalendarViewType _view = CalendarViewType.fitWeek;
  double _hourHeight = 64;

  late final _events = [
    _ExampleEvent(
      id: 'planning',
      title: 'Planning',
      start: DateTime.utc(2026, 10, 22, 9),
      end: DateTime.utc(2026, 10, 22, 10, 30),
      color: Colors.indigo,
    ),
    _ExampleEvent(
      id: 'reminder',
      title: 'Reminder',
      start: DateTime.utc(2026, 10, 22, 11),
      end: DateTime.utc(2026, 10, 22, 12),
      color: Colors.orange,
    ),
    _ExampleEvent(
      id: 'personal',
      title: 'Personal event',
      start: DateTime.utc(2026, 10, 23, 23, 30),
      end: DateTime.utc(2026, 10, 24, 1),
      color: Colors.teal,
    ),
  ];

  void _page(int direction) {
    setState(() {
      _focusedDay = calendarPageDate(_focusedDay, _view, true, direction);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('UTC Calendar example'),
      actions: [
        IconButton(
          tooltip: 'Previous period',
          onPressed: () => _page(-1),
          icon: const Icon(Icons.chevron_left),
        ),
        DropdownButton<CalendarViewType>(
          value: _view,
          items: [
            for (final view in CalendarViewType.values)
              DropdownMenuItem(
                value: view,
                child: Text(switch (view) {
                  CalendarViewType.month => 'Month',
                  CalendarViewType.fitWeek => 'Week',
                  CalendarViewType.threeDays => '3 Days',
                  CalendarViewType.day => 'Day',
                  CalendarViewType.schedule => 'Schedule',
                }),
              ),
          ],
          onChanged: (view) {
            if (view != null) setState(() => _view = view);
          },
        ),
        IconButton(
          tooltip: 'Next period',
          onPressed: () => _page(1),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    ),
    body: CalendarGrid<_ExampleEvent>(
      focusedDay: _focusedDay,
      view: _view,
      monday: true,
      items: _events,
      hourHeight: _hourHeight,
      onHourHeightChanged: (height) => setState(() => _hourHeight = height),
      eventColorBuilder: (context, event) => event.color,
      onDayTap: (day) => setState(() {
        _focusedDay = day;
        _view = CalendarViewType.day;
      }),
      onEmptyTimeTap: (time) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('New event at ${time.toIso8601String()}')),
      ),
      onEventTap: (event) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${event.title}: ${event.timeLabel}')),
      ),
      onEventLongPress: (event) => ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Long pressed: ${event.title}'))),
      onPreviousPeriod: () => _page(-1),
      onNextPeriod: () => _page(1),
    ),
  );
}
