import 'package:intl/intl.dart';

class CalendarEvent {
  CalendarEvent({
    required this.id,
    required this.title,
    required DateTime? start,
    required DateTime? end,
    this.displayDuration,
  }) : assert(displayDuration == null || displayDuration > Duration.zero),
       _start = start?.toUtc(),
       _stop = end?.toUtc();

  final String id;
  final String title;

  /// Optional visual duration, independent of recorded times and labels.
  /// Explicit durations are not expanded to the grid's minimum tile height.
  final Duration? displayDuration;
  final DateTime? _start;
  final DateTime? _stop;
  DateTime? get start => _start;
  DateTime? get stop => _stop;

  String get timeLabel {
    final from = start;
    final to = stop;
    if (from == null) return 'Time unavailable';
    final startLabel = DateFormat.Hm().format(from);
    if (to == null) return '$startLabel UTC · End not recorded';
    if (to.isBefore(from)) return '$startLabel UTC · Invalid end time';
    final endLabel =
        from.year == to.year && from.month == to.month && from.day == to.day
        ? DateFormat.Hm().format(to)
        : DateFormat('MMM d, HH:mm').format(to);
    final duration = to.difference(from);
    return '$startLabel – $endLabel UTC · ${duration.inHours}h ${duration.inMinutes.remainder(60)}m';
  }

  DateTime get displayEnd {
    final from = start!;
    final duration = displayDuration;
    if (duration != null) return from.add(duration);
    final to = stop;
    return to != null && to.isAfter(from)
        ? to
        : from.add(const Duration(minutes: 30));
  }

  bool occursOn(DateTime day) {
    final utc = day.toUtc();
    final utcDay = DateTime.utc(utc.year, utc.month, utc.day);
    return start != null &&
        start!.isBefore(utcDay.add(const Duration(days: 1))) &&
        displayEnd.isAfter(utcDay);
  }
}
