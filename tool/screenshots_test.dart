// Renders the screenshots in screenshots/, shown on pub.dev and in the
// README. Run: flutter test tool/screenshots_test.dart
//
// Not part of the published package (see .pubignore); the images are.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:utc_calendar/utc_calendar.dart';

class _Event extends CalendarEvent {
  _Event(String title, DateTime start, Duration length, this.color)
    : super(
        id: '$title ${start.toIso8601String()}',
        title: title,
        start: start,
        end: start.add(length),
      );

  final Color color;
}

DateTime _at(int day, int hour, [int minute = 0]) =>
    DateTime.utc(2026, 10, day, hour, minute);

const _h = Duration(hours: 1);
const _m = Duration(minutes: 1);

/// A made-up week (Monday 19 October 2026) and a few more days for the
/// month view.
final _events = [
  _Event('Standup', _at(19, 8), _m * 30, Colors.indigo),
  _Event('Design review', _at(19, 13), _h * 2, Colors.teal),
  _Event('Flight lesson', _at(20, 9, 30), _m * 90, Colors.orange),
  _Event('Call with Anna', _at(20, 10), _m * 45, Colors.pink),
  _Event('Gym', _at(20, 16), _m * 90, Colors.green),
  _Event('Planning', _at(21, 8), _m * 90, Colors.indigo),
  _Event('Interview', _at(21, 9), _h, Colors.purple),
  _Event('Lunch', _at(21, 12), _h, Colors.amber),
  _Event('Workshop', _at(21, 14), _m * 150, Colors.teal),
  _Event('Yoga', _at(21, 17, 30), _h, Colors.green),
  _Event('Team dinner', _at(21, 19), _h * 2, Colors.pink),
  _Event('Standup', _at(22, 8), _m * 30, Colors.indigo),
  _Event('Dentist', _at(22, 11), _h, Colors.orange),
  _Event('Night flight', _at(22, 22, 30), _m * 150, Colors.blue),
  _Event('Release', _at(23, 9), _h, Colors.teal),
  _Event('Trip to the coast', _at(23, 15), _h * 3, Colors.cyan),
  _Event('Hike', _at(24, 10), _h * 2, Colors.green),
  _Event('Dinner', _at(25, 18), _h, Colors.pink),
  _Event('Board meeting', _at(2, 10), _h * 2, Colors.purple),
  _Event('Maintenance', _at(5, 8), _h * 4, Colors.orange),
  _Event('Workshop', _at(8, 14), _h * 2, Colors.teal),
  _Event('Flight lesson', _at(12, 9), _m * 90, Colors.orange),
  _Event('Standup', _at(14, 8), _m * 30, Colors.indigo),
  _Event('Concert', _at(16, 19), _h * 2, Colors.pink),
  _Event('Inspection', _at(27, 9), _h * 3, Colors.blueGrey),
  _Event('Standup', _at(29, 8), _m * 30, Colors.indigo),
  _Event('Weekend trip', _at(30, 16), _h * 4, Colors.cyan),
];

Future<void> _loadFonts() async {
  // Tests run in flutter/bin/cache/artifacts/engine/<platform>/flutter_tester.
  final artifacts = File(Platform.resolvedExecutable).parent.parent.parent.path;
  final fonts = '$artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(
        Future.value(ByteData.sublistView(File(f).readAsBytesSync())),
      );
    }
    await loader.load();
  }

  await load('Roboto', [
    for (final w in ['Light', 'Regular', 'Medium', 'Bold'])
      '$fonts/Roboto-$w.ttf',
  ]);
  await load('MaterialIcons', ['$fonts/MaterialIcons-Regular.otf']);
}

void main() {
  const size = Size(390, 780);
  const ratio = 3.0;
  final boundary = GlobalKey();

  setUpAll(_loadFonts);

  Future<void> shot(
    WidgetTester tester,
    String file, {
    required String title,
    required CalendarViewType view,
    required DateTime focusedDay,
    Brightness brightness = Brightness.light,
    DateTimeRange? draft,
  }) async {
    tester.view.physicalSize = size * ratio;
    tester.view.devicePixelRatio = ratio;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorSchemeSeed: Colors.indigo,
            brightness: brightness,
            fontFamily: 'Roboto',
          ),
          home: Scaffold(
            appBar: AppBar(
              title: Text(title),
              actions: const [
                Icon(Icons.chevron_left),
                SizedBox(width: 16),
                Icon(Icons.chevron_right),
                SizedBox(width: 12),
              ],
            ),
            body: CalendarGrid<_Event>(
              focusedDay: focusedDay,
              view: view,
              monday: true,
              items: _events,
              hourHeight: 56,
              // Starts at 07:30, where the day gets busy.
              initialVerticalOffset: 56 * 7.5,
              onHourHeightChanged: (_) {},
              eventColorBuilder: (context, event) => event.color,
              draft: draft,
              onDayTap: (_) {},
              onEventTap: (_) {},
              onEventLongPress: (_) {},
              onPreviousPeriod: () {},
              onNextPeriod: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: ratio);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File('screenshots/$file')
        ..createSync(recursive: true)
        ..writeAsBytesSync(png!.buffer.asUint8List());
    });
  }

  testWidgets('week', (tester) async {
    await shot(
      tester,
      '1_week.png',
      title: 'Oct 19 – 25, 2026 · UTC',
      view: CalendarViewType.fitWeek,
      focusedDay: _at(21, 0),
    );
  });

  testWidgets('three days, with a draft slot', (tester) async {
    await shot(
      tester,
      '2_three_days.png',
      title: 'Oct 21 – 23 · UTC',
      view: CalendarViewType.threeDays,
      focusedDay: _at(21, 0),
      draft: DateTimeRange(start: _at(22, 14), end: _at(22, 15)),
    );
  });

  testWidgets('month', (tester) async {
    await shot(
      tester,
      '3_month.png',
      title: 'October 2026 · UTC',
      view: CalendarViewType.month,
      focusedDay: _at(21, 0),
    );
  });

  testWidgets('schedule, dark', (tester) async {
    await shot(
      tester,
      '4_schedule_dark.png',
      title: 'Wednesday, Oct 21 · UTC',
      view: CalendarViewType.schedule,
      focusedDay: _at(21, 0),
      brightness: Brightness.dark,
    );
  });
}
