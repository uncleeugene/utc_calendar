import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:utc_calendar/utc_calendar.dart';

Future<void> _mountTimeline(
  WidgetTester tester, {
  CalendarViewType view = CalendarViewType.day,
  DateTime? focusedDay,
  bool monday = true,
  double textScale = 1,
  double hourHeight = 64,
  double? initialVerticalOffset,
  double initialHorizontalOffset = 0,
  double periodOffset = 0,
  int? previewDayIndex,
  List<CalendarEvent> items = const [],
  ValueChanged<DateTime>? onEmptyTimeTap,
  DateTimeRange? draft,
  String? highlightedEventId,
  void Function(CalendarEvent, DateTime)? onEventMoved,
  bool Function(CalendarEvent)? canMoveEvent,
  bool showHiddenEventHints = false,
  ValueChanged<DateTime>? onDayTap,
  ValueChanged<CalendarEvent>? onEventTap,
  ValueChanged<CalendarEvent>? onEventLongPress,
  VoidCallback? onNextPeriod,
  ValueChanged<double>? onHourHeightChanged,
  Widget? Function(BuildContext, CalendarEvent)? eventLeadingBuilder,
  String Function(CalendarEvent)? eventTooltipBuilder,
  Widget Function(BuildContext, CalendarEvent)? scheduleItemBuilder,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: CalendarGrid<CalendarEvent>(
          focusedDay: focusedDay ?? DateTime.utc(2026, 10, 22),
          view: view,
          monday: monday,
          items: items,
          hourHeight: hourHeight,
          initialVerticalOffset: initialVerticalOffset ?? 8 * hourHeight,
          initialHorizontalOffset: initialHorizontalOffset,
          periodOffset: periodOffset,
          previewDayIndex: previewDayIndex,
          onHourHeightChanged: onHourHeightChanged ?? (_) {},
          eventColorBuilder: (_, _) => Colors.purple,
          eventLeadingBuilder: eventLeadingBuilder,
          eventTooltipBuilder: eventTooltipBuilder,
          scheduleItemBuilder: scheduleItemBuilder,
          onEmptyTimeTap: onEmptyTimeTap,
          draft: draft,
          highlightedEventId: highlightedEventId,
          onEventMoved: onEventMoved,
          canMoveEvent: canMoveEvent,
          showHiddenEventHints: showHiddenEventHints,
          onDayTap: onDayTap ?? (_) {},
          onEventTap: onEventTap ?? (_) {},
          onEventLongPress: onEventLongPress ?? (_) {},
          onPreviousPeriod: () {},
          onNextPeriod: onNextPeriod ?? () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('moving events', () {
    final ghost = find.byKey(const ValueKey('calendar-move-ghost'));
    CalendarEvent event(String id, DateTime start, [Duration? length]) =>
        CalendarEvent(
          id: id,
          title: id,
          start: start,
          end: start.add(length ?? const Duration(hours: 1)),
        );

    Future<TestGesture> pickUp(WidgetTester tester, String title) async {
      final gesture = await tester.startGesture(
        tester.getCenter(find.text(title)),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      return gesture;
    }

    testWidgets('a long-press drag snaps to 15 minutes and reports the start', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final moves = <(String, DateTime)>[];
      await _mountTimeline(
        tester,
        items: [event('Oil change', DateTime.utc(2026, 10, 22, 9))],
        onEventMoved: (event, start) => moves.add((event.id, start)),
      );
      final gesture = await pickUp(tester, 'Oil change');
      expect(ghost, findsOneWidget);
      // 1 h 35 min down at 64 px per hour: snaps to 10:30.
      await gesture.moveBy(const Offset(0, 64 * 95 / 60));
      await tester.pump();
      expect(find.textContaining('10:30–11:30'), findsOneWidget);
      await gesture.up();
      await tester.pump();
      expect(moves, [('Oil change', DateTime.utc(2026, 10, 22, 10, 30))]);
      expect(ghost, findsNothing);
    });

    testWidgets('releasing in place moves nothing', (tester) async {
      final moves = <DateTime>[];
      await _mountTimeline(
        tester,
        items: [event('Oil change', DateTime.utc(2026, 10, 22, 9))],
        onEventMoved: (_, start) => moves.add(start),
      );
      final gesture = await pickUp(tester, 'Oil change');
      await gesture.moveBy(const Offset(0, 4));
      await gesture.up();
      await tester.pump();
      expect(moves, isEmpty);
    });

    testWidgets('dragging across columns moves to another day', (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final start = calendarRangeStart(
        DateTime.utc(2026, 10, 22),
        CalendarViewType.threeDays,
        true,
      );
      final moves = <DateTime>[];
      final periods = <double>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CalendarGrid<CalendarEvent>(
              focusedDay: DateTime.utc(2026, 10, 22),
              view: CalendarViewType.threeDays,
              monday: true,
              items: [event('Flight', start.add(const Duration(hours: 9)))],
              hourHeight: 64,
              initialVerticalOffset: 8 * 64,
              onHourHeightChanged: (_) {},
              eventColorBuilder: (_, _) => Colors.purple,
              onEventMoved: (_, value) => moves.add(value),
              onPeriodDrag: (offset, _, _) => periods.add(offset),
              onDayTap: (_) {},
              onEventTap: (_) {},
              onEventLongPress: (_) {},
              onPreviousPeriod: () {},
              onNextPeriod: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final dayWidth = (900 - 56) / 3;
      final gesture = await pickUp(tester, 'Flight');
      await gesture.moveBy(Offset(dayWidth, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(moves, [start.add(const Duration(days: 1, hours: 9))]);
      // Moving an event never swipes the period.
      expect(periods, isEmpty);
    });

    testWidgets('holding against the edge pages to the next period', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var nextPages = 0;
      await _mountTimeline(
        tester,
        items: [event('Oil change', DateTime.utc(2026, 10, 22, 9))],
        onEventMoved: (_, _) {},
        onNextPeriod: () => nextPages++,
      );
      final gesture = await pickUp(tester, 'Oil change');
      await gesture.moveTo(Offset(598, tester.getCenter(ghost).dy));
      await tester.pump(const Duration(milliseconds: 300));
      expect(nextPages, 0);
      await tester.pump(const Duration(milliseconds: 600));
      expect(nextPages, 1);
      await gesture.moveTo(const Offset(300, 400));
      await tester.pump(const Duration(seconds: 2));
      expect(nextPages, 1);
      await gesture.up();
      await tester.pump();
    });

    testWidgets("events that can't move keep the long-press action", (
      tester,
    ) async {
      final pressed = <String>[];
      await _mountTimeline(
        tester,
        items: [event('Linked', DateTime.utc(2026, 10, 22, 9))],
        onEventMoved: (_, _) => fail('must not move'),
        canMoveEvent: (_) => false,
        onEventLongPress: (event) => pressed.add(event.id),
      );
      await tester.longPress(find.text('Linked'));
      await tester.pump();
      expect(pressed, ['Linked']);
      expect(ghost, findsNothing);
    });

    testWidgets('month view moves events to another day at the same time', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(700, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final moves = <DateTime>[];
      await _mountTimeline(
        tester,
        view: CalendarViewType.month,
        items: [event('Flight', DateTime.utc(2026, 10, 14, 9, 45))],
        onEventMoved: (_, start) => moves.add(start),
      );
      final gesture = await pickUp(tester, 'Flight');
      await tester.pump();
      // Two rows down: two weeks later.
      final target = tester.getCenter(find.text('28').last);
      await gesture.moveTo(target);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(moves, [DateTime.utc(2026, 10, 28, 9, 45)]);
    });
  });

  testWidgets('a new grid paints at its initial scroll offset at once', (
    tester,
  ) async {
    // A preview grid is created mid-swipe; a frame at the wrong scroll offset
    // shows tiles from other hours for a moment.
    await tester.binding.setSurfaceSize(const Size(600, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Runs before the grid's own post-frame work, so it sees the frame as
    // it was painted.
    double? painted;
    tester.binding.addPostFrameCallback((_) {
      painted =
          tester.getTopLeft(find.text('Nine')).dy -
          tester
              .getTopLeft(find.byKey(const ValueKey('calendar-time-scroll')))
              .dy;
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CalendarGrid<CalendarEvent>(
            focusedDay: DateTime.utc(2026, 10, 22),
            view: CalendarViewType.threeDays,
            monday: true,
            items: [
              CalendarEvent(
                id: 'nine',
                title: 'Nine',
                start: DateTime.utc(2026, 10, 22, 9),
                end: DateTime.utc(2026, 10, 22, 10),
              ),
            ],
            hourHeight: 64,
            initialVerticalOffset: 8 * 64,
            onHourHeightChanged: (_) {},
            eventColorBuilder: (_, _) => Colors.purple,
            onDayTap: (_) {},
            onEventTap: (_) {},
            onEventLongPress: (_) {},
            onPreviousPeriod: () {},
            onNextPeriod: () {},
          ),
        ),
      ),
    );
    expect(painted, closeTo(64, 8));
  });

  testWidgets('the highlighted event brightens, then fades back', (
    tester,
  ) async {
    final items = [
      for (final id in ['back', 'other'])
        CalendarEvent(
          id: id,
          title: id,
          start: DateTime.utc(2026, 10, 22, id == 'back' ? 9 : 12),
          end: DateTime.utc(2026, 10, 22, id == 'back' ? 10 : 13),
        ),
    ];
    final glow = find.byKey(const ValueKey('calendar-highlight'));
    await _mountTimelineNoSettle(tester, items, null);
    await tester.pumpAndSettle();
    expect(glow, findsNothing);

    // Highlighting the already-shown tile starts the fade.
    await _mountTimelineNoSettle(tester, items, 'back');
    await tester.pump(const Duration(milliseconds: 300));
    expect(glow, findsOneWidget);
    expect(
      find.ancestor(of: find.text('back'), matching: glow),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
    expect(glow, findsNothing);
  });

  group('hidden events', () {
    Finder hint(String edge, String id) => find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith(
            'calendar-hidden-$edge-$id',
          ),
    );
    CalendarEvent event(String id, int hour) => CalendarEvent(
      id: id,
      title: id,
      start: DateTime.utc(2026, 10, 22, hour),
      end: DateTime.utc(2026, 10, 22, hour + 1),
    );

    testWidgets('events out of sight shade the edge they are behind', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _mountTimeline(
        tester,
        showHiddenEventHints: true,
        items: [event('early', 2), event('seen', 9), event('late', 22)],
      );
      expect(hint('above', 'early'), findsOneWidget);
      expect(hint('below', 'late'), findsOneWidget);
      expect(hint('above', 'seen'), findsNothing);
      expect(hint('below', 'seen'), findsNothing);
      final box = tester.widget<DecoratedBox>(
        find.descendant(
          of: hint('above', 'early'),
          matching: find.byType(DecoratedBox),
        ),
      );
      final gradient =
          (box.decoration as BoxDecoration).gradient! as LinearGradient;
      expect(gradient.colors.first, Colors.purple.withValues(alpha: 0.55));

      // Scrolling up to the early event brings it into view.
      await tester.drag(
        find.byKey(const ValueKey('calendar-time-scroll')),
        const Offset(0, 64 * 8),
      );
      await tester.pumpAndSettle();
      expect(hint('above', 'early'), findsNothing);
      expect(hint('below', 'late'), findsOneWidget);
    });

    testWidgets('a fully visible day has no hints', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _mountTimeline(
        tester,
        showHiddenEventHints: true,
        initialVerticalOffset: 0,
        items: [event('early', 2), event('late', 22)],
      );
      expect(hint('above', 'early'), findsNothing);
      expect(hint('below', 'late'), findsNothing);
    });
    testWidgets('hints are off unless asked for', (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await _mountTimeline(
        tester,
        items: [event('early', 2), event('late', 22)],
      );
      expect(hint('above', 'early'), findsNothing);
      expect(hint('below', 'late'), findsNothing);
    });
  });

  group('draft slot', () {
    final draftKey = find.byKey(const ValueKey('calendar-draft'));

    testWidgets('outlines the hour under events and lets taps through', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(600, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final taps = <DateTime>[];
      final eventTaps = <String>[];
      await _mountTimeline(
        tester,
        draft: DateTimeRange(
          start: DateTime.utc(2026, 10, 22, 9),
          end: DateTime.utc(2026, 10, 22, 10),
        ),
        items: [
          CalendarEvent(
            id: 'overlap',
            title: 'Overlapping',
            start: DateTime.utc(2026, 10, 22, 9, 30),
            end: DateTime.utc(2026, 10, 22, 10, 30),
          ),
        ],
        onEmptyTimeTap: taps.add,
        onEventTap: (event) => eventTaps.add(event.id),
      );
      expect(draftKey, findsOneWidget);
      final hour = tester.getTopLeft(
        find.byKey(const ValueKey('calendar-hour-9')),
      );
      final draft = tester.getRect(draftKey);
      expect(draft.top, closeTo(hour.dy, 1));
      expect(draft.height, closeTo(64, 1));

      // Empty part of the draft: still an empty-time tap.
      await tester.tapAt(Offset(draft.center.dx, draft.top + 10));
      expect(taps.single, DateTime.utc(2026, 10, 22, 9, 9));
      // Where it overlaps an event, the event wins.
      await tester.tap(find.text('Overlapping'));
      expect(eventTaps, ['overlap']);
    });

    testWidgets('splits across midnight and skips days not shown', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final start = calendarRangeStart(
        DateTime.utc(2026, 10, 22),
        CalendarViewType.threeDays,
        true,
      );
      await _mountTimeline(
        tester,
        view: CalendarViewType.threeDays,
        initialVerticalOffset: 0,
        draft: DateTimeRange(
          start: start.add(const Duration(hours: 23)),
          end: start.add(const Duration(hours: 25)),
        ),
      );
      expect(draftKey, findsNWidgets(2));
      for (final rect
          in tester
              .widgetList(draftKey)
              .map((widget) => tester.getRect(find.byWidget(widget)))) {
        expect(rect.height, closeTo(64, 1));
      }

      await _mountTimeline(
        tester,
        view: CalendarViewType.threeDays,
        draft: DateTimeRange(
          start: start.subtract(const Duration(hours: 2)),
          end: start.subtract(const Duration(hours: 1)),
        ),
      );
      expect(draftKey, findsNothing);
    });
  });

  testWidgets('custom schedule rows own their rendering and interactions', (
    tester,
  ) async {
    final events = [
      CalendarEvent(
        id: 'custom',
        title: 'Default title',
        start: DateTime.utc(2026, 10, 22, 9),
        end: null,
      ),
    ];
    var customTaps = 0;
    var defaultTaps = 0;
    await _mountTimeline(
      tester,
      view: CalendarViewType.schedule,
      items: events,
      onEventTap: (_) => defaultTaps++,
      scheduleItemBuilder: (_, event) => TextButton(
        onPressed: () => customTaps++,
        child: Text('Custom ${event.id}'),
      ),
    );
    expect(find.text('Default title'), findsNothing);
    await tester.tap(find.text('Custom custom'));
    await tester.pump();
    expect(customTaps, 1);
    expect(defaultTaps, 0);
    final list = tester.widget<ListView>(
      find.byKey(const ValueKey('calendar-schedule-list')),
    );
    expect(list.physics, isA<AlwaysScrollableScrollPhysics>());
    expect(tester.takeException(), isNull);
  });

  group('empty time taps', () {
    for (final view in [
      CalendarViewType.day,
      CalendarViewType.threeDays,
      CalendarViewType.fitWeek,
    ]) {
      for (final hourHeight in [40.0, 64.0, 120.0]) {
        testWidgets('$view at $hourHeight reports the UTC day and minute', (
          tester,
        ) async {
          await tester.binding.setSurfaceSize(const Size(1200, 700));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final times = <DateTime>[];
          await _mountTimeline(
            tester,
            view: view,
            hourHeight: hourHeight,
            onEmptyTimeTap: times.add,
          );
          final count = calendarDayCount(view);
          final dayWidth = (1200 - 56) / count;
          final y =
              tester
                  .getTopLeft(find.byKey(const ValueKey('calendar-hour-9')))
                  .dy +
              hourHeight * 17.75 / 60;
          final start = calendarRangeStart(
            DateTime.utc(2026, 10, 22),
            view,
            true,
          );
          for (var index = 0; index < count; index++) {
            await tester.tapAt(Offset(56 + dayWidth * (index + 0.5), y));
            await tester.pump();
          }
          expect(times, [
            for (var index = 0; index < count; index++)
              start.add(Duration(days: index, hours: 9, minutes: 17)),
          ]);
          expect(times.every((time) => time.isUtc), isTrue);
        });
      }
    }

    testWidgets('supports horizontal scrolling and translated previews', (
      tester,
    ) async {
      // Three 112px day columns overflow a narrow screen and scroll.
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final times = <DateTime>[];
      await _mountTimeline(
        tester,
        view: CalendarViewType.threeDays,
        initialHorizontalOffset: 40,
        periodOffset: -112,
        previewDayIndex: 1,
        onEmptyTimeTap: times.add,
      );
      final y = tester
          .getTopLeft(find.byKey(const ValueKey('calendar-hour-9')))
          .dy;
      // The second day is translated into the first column and scrolled left.
      await tester.tapAt(Offset(56 - 40 + 56, y + 32));
      await tester.pump();
      expect(times, [DateTime.utc(2026, 10, 23, 9, 30)]);
      await tester.tapAt(Offset(56 - 40 + 168, y + 32));
      await tester.pump();
      expect(times, hasLength(1));
    });

    group('new view modes', () {
      test('fit-week and schedule ranges and navigation remain UTC', () {
        for (final day in [
          DateTime.utc(2026, 11, 1, 23),
          DateTime.utc(2026, 12, 31, 23, 59),
        ]) {
          for (final monday in [true, false]) {
            final date = DateTime.utc(day.year, day.month, day.day);
            final weekStart = date.subtract(
              Duration(days: (date.weekday - (monday ? 1 : 7) + 7) % 7),
            );
            expect(
              calendarRangeStart(day, CalendarViewType.fitWeek, monday),
              weekStart,
            );
            expect(calendarDayCount(CalendarViewType.fitWeek), 7);
            expect(calendarDayCount(CalendarViewType.schedule), 1);
            expect(
              calendarRangeStart(day, CalendarViewType.schedule, monday),
              date,
            );
            for (final direction in [-1, 1]) {
              expect(
                calendarPageDate(
                  day,
                  CalendarViewType.fitWeek,
                  monday,
                  direction,
                ),
                weekStart.add(Duration(days: 7 * direction)),
              );
              expect(
                calendarPageDate(
                  day,
                  CalendarViewType.schedule,
                  monday,
                  direction,
                ),
                date.add(Duration(days: direction)),
              );
            }
          }
        }
        expect(CalendarViewType.fitWeek.isHourly, isTrue);
        expect(CalendarViewType.schedule.isHourly, isFalse);
      });

      for (final width in [320.3, 800.0, 1200.0]) {
        testWidgets('fit week fits seven columns at width $width', (
          tester,
        ) async {
          await tester.binding.setSurfaceSize(Size(width, 700));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final start = DateTime.utc(2026, 10, 19);
          final events = [
            for (var index = 0; index < 7; index++)
              CalendarEvent(
                id: 'day-$index',
                title: 'Day $index',
                start: start.add(Duration(days: index, hours: 9)),
                end: start.add(Duration(days: index, hours: 10)),
              ),
            for (var index = 0; index < 5; index++)
              CalendarEvent(
                id: 'overlap-$index',
                title: 'Overlapping event $index with a long title',
                start: start.add(const Duration(hours: 9)),
                end: start.add(const Duration(hours: 10)),
              ),
          ];
          final times = <DateTime>[];
          final tapped = <CalendarEvent>[];
          final longPressed = <CalendarEvent>[];
          await _mountTimeline(
            tester,
            view: CalendarViewType.fitWeek,
            items: events,
            textScale: 1.5,
            onEmptyTimeTap: times.add,
            onEventTap: tapped.add,
            onEventLongPress: longPressed.add,
          );
          final horizontal = tester
              .widgetList<SingleChildScrollView>(
                find.byType(SingleChildScrollView),
              )
              .singleWhere(
                (scroll) => scroll.scrollDirection == Axis.horizontal,
              );
          expect(horizontal.controller!.position.maxScrollExtent, 0);
          final columnWidth = (width - 56) / 7;
          for (var index = 0; index < 7; index++) {
            final day = start.add(Duration(days: index));
            final tile = find.byKey(
              ValueKey('day-${index}_${day.toIso8601String()}'),
            );
            final rect = tester.getRect(tile);
            expect(rect.left, greaterThanOrEqualTo(56 + columnWidth * index));
            expect(rect.right, lessThanOrEqualTo(width));
            expect(rect.width, lessThan(columnWidth));
          }
          final lastTile = find.byKey(
            ValueKey(
              'day-6_${start.add(const Duration(days: 6)).toIso8601String()}',
            ),
          );
          await tester.tap(lastTile);
          await tester.pump();
          await tester.longPress(lastTile);
          await tester.pumpAndSettle();
          expect(tapped, [events[6]]);
          expect(longPressed, [events[6]]);
          final y = tester
              .getTopLeft(find.byKey(const ValueKey('calendar-hour-10')))
              .dy;
          await tester.tapAt(
            Offset(width - columnWidth / 2, y + 64 * 17.75 / 60),
          );
          await tester.pump();
          expect(times, [DateTime.utc(2026, 10, 25, 10, 17)]);
          expect(tester.takeException(), isNull);
          // Unlike fit week, three 112px columns overflow narrow screens.
          await _mountTimeline(tester, view: CalendarViewType.threeDays);
          final threeDays = tester
              .widgetList<SingleChildScrollView>(
                find.byType(SingleChildScrollView),
              )
              .singleWhere(
                (scroll) => scroll.scrollDirection == Axis.horizontal,
              );
          expect(
            threeDays.controller!.position.maxScrollExtent,
            width < 56 + 3 * 112 ? greaterThan(0) : 0,
          );
        });
      }

      testWidgets(
        'schedule filters and orders events and retains builders and actions',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(320, 800));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final day = DateTime.utc(2026, 10, 22);
          final events = [
            CalendarEvent(
              id: 'b',
              title: 'Second at nine',
              start: day.add(const Duration(hours: 9)),
              end: null,
            ),
            CalendarEvent(
              id: 'future',
              title: 'Tomorrow',
              start: day.add(const Duration(days: 1)),
              end: null,
            ),
            CalendarEvent(
              id: 'a',
              title: 'First at nine with a long title that wraps',
              start: day.add(const Duration(hours: 9)),
              end: day.add(const Duration(hours: 10)),
            ),
            CalendarEvent(
              id: 'overnight',
              title: 'Overnight',
              start: day.subtract(const Duration(minutes: 30)),
              end: day.add(const Duration(minutes: 30)),
            ),
            CalendarEvent(
              id: 'untimed',
              title: 'No start',
              start: null,
              end: null,
            ),
            CalendarEvent(
              id: 'ended',
              title: 'Ended at midnight',
              start: day.subtract(const Duration(hours: 1)),
              end: day,
            ),
          ];
          final tapped = <CalendarEvent>[];
          final longPressed = <CalendarEvent>[];
          final times = <DateTime>[];
          var zooms = 0;
          await _mountTimeline(
            tester,
            view: CalendarViewType.schedule,
            items: events,
            textScale: 1.5,
            onEventTap: tapped.add,
            onEventLongPress: longPressed.add,
            onEmptyTimeTap: times.add,
            onHourHeightChanged: (_) => zooms++,
            eventLeadingBuilder: (_, _) => const Icon(Icons.star),
            eventTooltipBuilder: (event) => 'Details for ${event.id}',
          );
          expect(find.text('Tomorrow'), findsNothing);
          expect(find.text('No start'), findsNothing);
          expect(find.text('Ended at midnight'), findsNothing);
          expect(find.byIcon(Icons.star), findsNWidgets(3));
          final overnight = find.byKey(
            const ValueKey('calendar-schedule-overnight'),
          );
          final first = find.byKey(const ValueKey('calendar-schedule-a'));
          final second = find.byKey(const ValueKey('calendar-schedule-b'));
          expect(
            tester.getTopLeft(overnight).dy,
            lessThan(tester.getTopLeft(first).dy),
          );
          expect(
            tester.getTopLeft(first).dy,
            lessThan(tester.getTopLeft(second).dy),
          );
          expect(find.text(events[2].timeLabel), findsOneWidget);
          expect(find.byTooltip('Details for a'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('calendar-pinch-viewport')),
            findsNothing,
          );
          final material = tester.widget<Material>(
            find.descendant(of: first, matching: find.byType(Material)),
          );
          expect(material.color, Colors.purple.withValues(alpha: 0.14));
          await tester.tap(first);
          await tester.pump();
          await tester.longPress(first);
          await tester.pumpAndSettle();
          expect(tapped, [events[2]]);
          expect(longPressed, [events[2]]);
          await tester.tapAt(const Offset(200, 750));
          await tester.pump();
          expect(times, isEmpty);
          expect(zooms, 0);
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'schedule scrolls, resets on paging, and supports an empty day',
        (tester) async {
          final items = [
            for (var index = 0; index < 30; index++)
              CalendarEvent(
                id: '$index',
                title: 'Event $index',
                start: DateTime.utc(2026, 10, 22, 0, index),
                end: null,
              ),
          ];
          var pages = 0;
          await _mountTimeline(
            tester,
            view: CalendarViewType.schedule,
            items: items,
            onNextPeriod: () => pages++,
          );
          final list = find.byKey(const ValueKey('calendar-schedule-list'));
          final scroll = tester.widget<ListView>(list).controller!;
          expect(scroll.offset, 0);
          await tester.drag(list, const Offset(0, -400));
          await tester.pumpAndSettle();
          expect(scroll.offset, greaterThan(0));
          expect(pages, 0);
          final offset = scroll.offset;
          await _mountTimeline(
            tester,
            view: CalendarViewType.schedule,
            items: items,
            hourHeight: 120,
            onNextPeriod: () => pages++,
          );
          expect(scroll.offset, offset);
          await tester.drag(list, const Offset(-100, 0));
          await tester.pumpAndSettle();
          expect(pages, 1);
          await _mountTimeline(
            tester,
            view: CalendarViewType.schedule,
            focusedDay: DateTime.utc(2026, 10, 23),
            items: items,
          );
          expect(tester.widget<ListView>(list).controller!.offset, 0);
          expect(find.textContaining('Event '), findsNothing);
          expect(tester.takeException(), isNull);
          await _mountTimeline(
            tester,
            view: CalendarViewType.fitWeek,
            items: items,
          );
          expect(
            find.byKey(const ValueKey('calendar-time-scroll')),
            findsOneWidget,
          );
          await _mountTimeline(
            tester,
            view: CalendarViewType.schedule,
            items: items,
          );
          expect(tester.widget<ListView>(list).controller!.offset, 0);
          expect(find.text('Event 0'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    });

    testWidgets('keeps taps within the first and last UTC minute', (
      tester,
    ) async {
      final times = <DateTime>[];
      await _mountTimeline(
        tester,
        initialVerticalOffset: 0,
        onEmptyTimeTap: times.add,
      );
      final top = tester
          .getTopLeft(find.byKey(const ValueKey('calendar-hour-0')))
          .dy;
      await tester.tapAt(Offset(200, top + 0.5));
      await tester.pump();
      await _mountTimeline(
        tester,
        initialVerticalOffset: 24 * 64,
        onEmptyTimeTap: times.add,
      );
      final scroll = tester
          .widget<SingleChildScrollView>(
            find.byKey(const ValueKey('calendar-time-scroll')),
          )
          .controller!;
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump();
      final lastHour = tester
          .getTopLeft(find.byKey(const ValueKey('calendar-hour-23')))
          .dy;
      await tester.tapAt(Offset(200, lastHour + 63.5));
      await tester.pump();
      expect(times, [
        DateTime.utc(2026, 10, 22),
        DateTime.utc(2026, 10, 22, 23, 59),
      ]);
    });

    testWidgets('event taps and long presses do not report empty time', (
      tester,
    ) async {
      final event = CalendarEvent(
        id: 'event',
        title: 'Occupied',
        start: DateTime.utc(2026, 10, 22, 9),
        end: DateTime.utc(2026, 10, 22, 10),
      );
      final times = <DateTime>[];
      final tapped = <CalendarEvent>[];
      final longPressed = <CalendarEvent>[];
      await _mountTimeline(
        tester,
        items: [event],
        onEmptyTimeTap: times.add,
        onEventTap: tapped.add,
        onEventLongPress: longPressed.add,
      );
      await tester.tap(find.text('Occupied'));
      await tester.pump();
      await tester.longPress(find.text('Occupied'));
      await tester.pumpAndSettle();
      expect(tapped, [event]);
      expect(longPressed, [event]);
      expect(times, isEmpty);
    });

    testWidgets('headings, gutter, and month cells do not report empty time', (
      tester,
    ) async {
      final times = <DateTime>[];
      final days = <DateTime>[];
      await _mountTimeline(
        tester,
        onEmptyTimeTap: times.add,
        onDayTap: days.add,
      );
      await tester.tap(find.text('Thu 22'));
      await tester.tap(find.text('09:00'));
      await tester.pump();
      expect(days, [DateTime.utc(2026, 10, 22)]);
      expect(times, isEmpty);
      await _mountTimeline(
        tester,
        view: CalendarViewType.month,
        onEmptyTimeTap: times.add,
        onDayTap: days.add,
      );
      await tester.tap(find.text('22'));
      await tester.pump();
      expect(days, hasLength(2));
      expect(times, isEmpty);
    });

    testWidgets('scrolling, paging, and multi-touch do not report empty time', (
      tester,
    ) async {
      final times = <DateTime>[];
      var nextPeriods = 0;
      await _mountTimeline(
        tester,
        view: CalendarViewType.threeDays,
        onEmptyTimeTap: times.add,
        onNextPeriod: () => nextPeriods++,
      );
      await tester.dragFrom(const Offset(400, 300), const Offset(0, -100));
      await tester.pumpAndSettle();
      await tester.dragFrom(const Offset(400, 300), const Offset(-150, 0));
      await tester.pumpAndSettle();
      expect(nextPeriods, 1);
      final first = await tester.startGesture(
        const Offset(300, 300),
        pointer: 1,
      );
      final second = await tester.startGesture(
        const Offset(500, 300),
        pointer: 2,
      );
      await tester.pump();
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      expect(times, isEmpty);
      final pinchFirst = await tester.startGesture(
        const Offset(300, 300),
        pointer: 3,
      );
      final pinchSecond = await tester.startGesture(
        const Offset(500, 300),
        pointer: 4,
      );
      await pinchFirst.moveBy(const Offset(-40, 0));
      await pinchSecond.moveBy(const Offset(40, 0));
      await tester.pump();
      await pinchFirst.up();
      await pinchSecond.up();
      await tester.pumpAndSettle();
      expect(times, isEmpty);
      await tester.tapAt(const Offset(400, 300));
      await tester.pump();
      expect(times, hasLength(1));
    });

    testWidgets('the callback remains optional', (tester) async {
      await _mountTimeline(tester);
      await tester.tapAt(const Offset(400, 300));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('UTC calendar helpers', () {
    test('normalizes event times to UTC', () {
      final event = CalendarEvent(
        id: 'event',
        title: 'Event',
        start: DateTime(2026, 10, 22, 9),
        end: DateTime(2026, 10, 22, 10),
      );

      expect(event.start!.isUtc, isTrue);
      expect(event.stop!.isUtc, isTrue);
    });

    test('starts week and month ranges on the configured weekday', () {
      final day = DateTime.utc(2026, 10, 22);

      expect(
        calendarRangeStart(day, CalendarViewType.fitWeek, true),
        DateTime.utc(2026, 10, 19),
      );
      expect(
        calendarRangeStart(day, CalendarViewType.month, false),
        DateTime.utc(2026, 9, 27),
      );
    });

    test('three-day windows move daily across month and year boundaries', () {
      for (final day in [
        DateTime.utc(2026, 10, 31),
        DateTime.utc(2026, 12, 31),
        DateTime.utc(2028, 2, 28),
      ]) {
        for (final monday in [true, false]) {
          for (final direction in [-1, 1]) {
            final next = calendarPageDate(
              day,
              CalendarViewType.threeDays,
              monday,
              direction,
            );
            expect(next, day.add(Duration(days: direction)));
            expect(next.isUtc, isTrue);
            expect(
              calendarRangeStart(next, CalendarViewType.threeDays, monday),
              next,
            );
            expect(calendarDayCount(CalendarViewType.threeDays), 3);
          }
        }
      }
    });

    test('other views retain their navigation step', () {
      final day = DateTime.utc(2026, 10, 22);
      for (final direction in [-1, 1]) {
        expect(
          calendarPageDate(day, CalendarViewType.month, true, direction),
          DateTime.utc(2026, 10 + direction),
        );
        for (final monday in [true, false]) {
          expect(
            calendarPageDate(day, CalendarViewType.fitWeek, monday, direction),
            calendarRangeStart(
              day,
              CalendarViewType.fitWeek,
              monday,
            ).add(Duration(days: 7 * direction)),
          );
          expect(
            calendarPageDate(day, CalendarViewType.day, monday, direction),
            day.add(Duration(days: direction)),
          );
        }
      }
    });
  });

  test('lays out overlapping events in separate columns', () {
    final day = DateTime.utc(2026, 10, 22);
    final events = [
      CalendarEvent(
        id: 'first',
        title: 'First',
        start: day.add(const Duration(hours: 9)),
        end: day.add(const Duration(hours: 11)),
      ),
      CalendarEvent(
        id: 'second',
        title: 'Second',
        start: day.add(const Duration(hours: 10)),
        end: day.add(const Duration(hours: 12)),
      ),
    ];

    final placements = layoutCalendarDay(events, day, minimumMinutes: 20);

    expect(placements, hasLength(2));
    expect(placements.map((placement) => placement.columns), everyElement(2));
    expect(placements.map((placement) => placement.column).toSet(), {0, 1});
  });

  test('explicit display duration clips at midnight without changing actual labels', () {
    final start = DateTime.utc(2026, 10, 22, 23, 55);
    final stop = start.add(const Duration(hours: 4));
    final event = CalendarEvent(
      id: 'short-display',
      title: 'Event',
      start: start,
      end: stop,
      displayDuration: const Duration(minutes: 10),
    );
    final first = layoutCalendarDay([event], start, minimumMinutes: 30).single;
    final second = layoutCalendarDay(
      [event],
      DateTime.utc(2026, 10, 23),
      minimumMinutes: 30,
    ).single;
    expect(first.startMinute, 1435);
    expect(first.endMinute, 1440);
    expect(second.startMinute, 0);
    expect(second.endMinute, 5);
    expect(event.stop, stop);
    expect(event.timeLabel, contains('4h 0m'));
    expect(event.occursOn(DateTime.utc(2026, 10, 24)), isFalse);
  });

  testWidgets('uses app-provided event color and descriptions', (tester) async {
    final event = CalendarEvent(
      id: 'event',
      title: 'Custom event',
      start: DateTime.utc(2026, 10, 22, 9),
      end: DateTime.utc(2026, 10, 22, 10),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CalendarGrid<CalendarEvent>(
            focusedDay: DateTime.utc(2026, 10, 22),
            view: CalendarViewType.day,
            monday: true,
            items: [event],
            hourHeight: 64,
            onHourHeightChanged: (_) {},
            eventColorBuilder: (_, _) => Colors.purple,
            eventLeadingBuilder: (_, _) => const Icon(Icons.star),
            eventTooltipBuilder: (_) => 'Custom event details',
            onDayTap: (_) {},
            onEventTap: (_) {},
            onEventLongPress: (_) {},
            onPreviousPeriod: () {},
            onNextPeriod: () {},
          ),
        ),
      ),
    );

    expect(find.text('Custom event'), findsOneWidget);
    expect(find.byIcon(Icons.star), findsOneWidget);
    expect(find.byTooltip('Custom event details'), findsOneWidget);
    final tile = tester.widget<Material>(
      find
          .ancestor(
            of: find.text('Custom event'),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(tile.color, Colors.purple.withValues(alpha: 0.14));
    expect(tester.takeException(), isNull);
  });
}

/// Like [_mountTimeline] for a day view, but leaves animations running.
Future<void> _mountTimelineNoSettle(
  WidgetTester tester,
  List<CalendarEvent> items,
  String? highlightedEventId,
) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: CalendarGrid<CalendarEvent>(
        focusedDay: DateTime.utc(2026, 10, 22),
        view: CalendarViewType.day,
        monday: true,
        items: items,
        hourHeight: 64,
        initialVerticalOffset: 8 * 64,
        highlightedEventId: highlightedEventId,
        onHourHeightChanged: (_) {},
        eventColorBuilder: (_, _) => Colors.purple,
        onDayTap: (_) {},
        onEventTap: (_) {},
        onEventLongPress: (_) {},
        onPreviousPeriod: () {},
        onNextPeriod: () {},
      ),
    ),
  ),
);
