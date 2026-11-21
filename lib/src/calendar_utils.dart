import 'calendar_event.dart';

enum CalendarViewType {
  month,
  threeDays,
  day,

  /// A week timeline with seven columns fitted to the available width.
  fitWeek,

  /// A chronological event list for the focused UTC day.
  schedule;

  /// Whether this view uses an hourly timeline with zoom and empty-time taps.
  bool get isHourly => this != month && this != schedule;
}

bool sameUtcDay(DateTime? first, DateTime? second) {
  if (first == null || second == null) return false;

  final firstUtc = first.toUtc();
  final secondUtc = second.toUtc();
  return firstUtc.year == secondUtc.year &&
      firstUtc.month == secondUtc.month &&
      firstUtc.day == secondUtc.day;
}

DateTime calendarRangeStart(
  DateTime focused,
  CalendarViewType view,
  bool monday,
) {
  final utc = focused.toUtc();
  final day = DateTime.utc(utc.year, utc.month, utc.day);
  final firstWeekday = monday ? DateTime.monday : DateTime.sunday;
  final first = view == CalendarViewType.month
      ? DateTime.utc(day.year, day.month)
      : day;
  return view == CalendarViewType.month || view == CalendarViewType.fitWeek
      ? first.subtract(Duration(days: (first.weekday - firstWeekday + 7) % 7))
      : first;
}

int calendarDayCount(CalendarViewType view) => switch (view) {
  CalendarViewType.month => 42,
  CalendarViewType.fitWeek => 7,
  CalendarViewType.threeDays => 3,
  CalendarViewType.day || CalendarViewType.schedule => 1,
};

/// Moves to an adjacent period; three-day windows advance one day at a time.
DateTime calendarPageDate(
  DateTime focused,
  CalendarViewType view,
  bool monday,
  int direction,
) {
  assert(direction == -1 || direction == 1);
  final utc = focused.toUtc();
  if (view == CalendarViewType.month) {
    return DateTime.utc(utc.year, utc.month + direction);
  }
  final step = view == CalendarViewType.threeDays ? 1 : calendarDayCount(view);
  return calendarRangeStart(
    utc,
    view,
    monday,
  ).add(Duration(days: step * direction));
}

class CalendarEventPlacement<T extends CalendarEvent> {
  const CalendarEventPlacement({
    required this.item,
    required this.startMinute,
    required this.endMinute,
    required this.column,
    required this.columns,
  });

  final T item;
  final double startMinute;
  final double endMinute;
  final int column;
  final int columns;
}

List<CalendarEventPlacement<T>> layoutCalendarDay<T extends CalendarEvent>(
  List<T> items,
  DateTime day, {
  required double minimumMinutes,
}) {
  assert(minimumMinutes > 0 && minimumMinutes <= 1440);
  final utc = day.toUtc();
  day = DateTime.utc(utc.year, utc.month, utc.day);
  final events = items.where((item) => item.occursOn(day)).toList()
    ..sort((a, b) {
      final result = a.start!.compareTo(b.start!);
      return result != 0 ? result : a.id.compareTo(b.id);
    });
  final result = <CalendarEventPlacement<T>>[];
  var group = <({T item, double start, double end, int column})>[];
  var columnEnds = <double>[];
  var groupEnd = 0.0;
  void flush() {
    for (final event in group) {
      result.add(
        CalendarEventPlacement<T>(
          item: event.item,
          startMinute: event.start,
          endMinute: event.end,
          column: event.column,
          columns: columnEnds.length,
        ),
      );
    }
    group = [];
    columnEnds = [];
  }

  for (final item in events) {
    final itemMinimum = item.displayDuration == null ? minimumMinutes : 0.0;
    final start = (item.start!.difference(day).inSeconds / 60).clamp(
      0.0,
      1440.0 - itemMinimum,
    );
    final actualEnd = (item.displayEnd.difference(day).inSeconds / 60).clamp(
      0.0,
      1440.0,
    );
    final end = actualEnd.clamp(start + itemMinimum, 1440.0);
    if (group.isNotEmpty && start >= groupEnd) flush();
    var column = columnEnds.indexWhere((end) => end <= start);
    if (column == -1) {
      column = columnEnds.length;
      columnEnds.add(end);
    } else {
      columnEnds[column] = end;
    }
    if (group.isEmpty || end > groupEnd) groupEnd = end;
    group.add((item: item, start: start, end: end, column: column));
  }
  flush();
  return result;
}
