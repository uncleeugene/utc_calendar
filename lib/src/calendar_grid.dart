import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'calendar_event.dart';
import 'calendar_utils.dart';

class CalendarGrid<T extends CalendarEvent> extends StatefulWidget {
  const CalendarGrid({
    super.key,
    required this.focusedDay,
    required this.view,
    required this.monday,
    required this.items,
    required this.hourHeight,
    required this.onHourHeightChanged,
    required this.eventColorBuilder,
    required this.onDayTap,
    required this.onEventTap,
    required this.onEventLongPress,
    required this.onPreviousPeriod,
    required this.onNextPeriod,
    this.eventLeadingBuilder,
    this.eventTooltipBuilder,
    this.scheduleItemBuilder,
    this.onEmptyTimeTap,
    this.draft,
    this.highlightedEventId,
    this.onEventMoved,
    this.canMoveEvent,
    this.moveStep = const Duration(minutes: 15),
    this.showHiddenEventHints = false,
    this.onPeriodDrag,
    this.onPeriodDragEnd,
    this.initialVerticalOffset,
    this.initialHorizontalOffset = 0,
    this.visibleGrid = true,
    this.periodOffset = 0,
    this.showTimeColumn = true,
    this.previewDayIndex,
    this.previewDayCount = 1,
  });

  final DateTime focusedDay;
  final CalendarViewType view;
  final bool monday;
  final List<T> items;
  final double hourHeight;
  final ValueChanged<double> onHourHeightChanged;
  final Color Function(BuildContext context, T event) eventColorBuilder;
  final Widget? Function(BuildContext context, T event)? eventLeadingBuilder;
  final String Function(T event)? eventTooltipBuilder;

  /// Replaces the default schedule row, including its event interactions.
  final Widget Function(BuildContext context, T event)? scheduleItemBuilder;
  final ValueChanged<DateTime> onDayTap;

  /// Called when empty space in an hourly day column is tapped.
  ///
  /// Reports the UTC date and time at whole-minute precision, without snapping
  /// to a time slot. Event tiles, day headings, month cells, and schedule lists
  /// do not invoke it.
  final ValueChanged<DateTime>? onEmptyTimeTap;

  /// A provisional slot to outline in the hourly views, in UTC: for example
  /// the hour being offered after [onEmptyTimeTap], while the user chooses
  /// what to add there. Drawn under event tiles and never tappable; parts
  /// outside the shown days are left out.
  final DateTimeRange? draft;

  /// The [CalendarEvent.id] to draw attention to, e.g. the entry the user
  /// just came back from. Its tile brightens in its own color and fades back
  /// to normal when it becomes highlighted; clear it and set it again to
  /// repeat.
  final String? highlightedEventId;

  /// Lets the user move events by long-pressing and dragging them. In the
  /// hourly views the tile follows the finger in [moveStep] steps, across
  /// days, and pages to the previous or next period when held against the
  /// left or right edge; in month view it moves to another day, keeping its
  /// time. Called on release with the new start, if it changed. Without it,
  /// a long-press calls [onEventLongPress].
  final void Function(T event, DateTime start)? onEventMoved;

  /// Whether [event] may be moved. A long-press on an event that can't be
  /// moved calls [onEventLongPress] instead, e.g. to say why.
  final bool Function(T event)? canMoveEvent;

  /// The grid moved events snap to.
  final Duration moveStep;

  /// Whether the hourly views shade the top or bottom edge of a day column,
  /// in an event's color, when that event is scrolled out of sight.
  final bool showHiddenEventHints;
  final ValueChanged<T> onEventTap;
  final ValueChanged<T> onEventLongPress;
  final VoidCallback? onPreviousPeriod;
  final VoidCallback? onNextPeriod;
  final void Function(double offset, double vertical, double horizontal)?
  onPeriodDrag;

  /// Reports cancellation and horizontal release velocity in pixels per second.
  final void Function(bool cancelled, double velocity)? onPeriodDragEnd;
  final double? initialVerticalOffset;
  final double initialHorizontalOffset;
  final bool visibleGrid;

  /// Horizontal translation of hourly day columns, excluding the time gutter.
  final double periodOffset;
  final bool showTimeColumn;

  /// First entering day to paint when previewing overlapping date windows.
  final int? previewDayIndex;

  /// Number of entering days to paint, starting at [previewDayIndex].
  final int previewDayCount;

  bool _showsDay(int index) =>
      previewDayIndex == null ||
      (index >= previewDayIndex! && index < previewDayIndex! + previewDayCount);
  @override
  State<CalendarGrid<T>> createState() => _CalendarGridState<T>();
}

class _CalendarGridState<T extends CalendarEvent>
    extends State<CalendarGrid<T>> {
  // Start where the grid should show, so its first frame already does: a
  // grid created mid-swipe would otherwise paint one frame at the top of the
  // day before jumping, flashing tiles from other hours.
  late final _vertical = ScrollController(
    initialScrollOffset: !widget.view.isHourly
        ? 0
        : widget.initialVerticalOffset ?? _eventsOffset(),
  );
  late final _horizontal = ScrollController(
    initialScrollOffset:
        widget.view.isHourly && widget.initialVerticalOffset != null
        ? widget.initialHorizontalOffset
        : 0,
  );
  Timer? _clock;
  final _pointers = <int, Offset>{};
  bool _multiTouch = false;
  double? _pinchDistance;
  double _pinchHourHeight = 0;
  double _pinchHour = 0;
  ({double hour, double y})? _zoomAnchor;
  final _swipePointers = <int>{};
  Offset? _swipeStart;
  double _swipeScrollOffset = 0;
  double _swipeScrollExtent = 0;
  bool _draggingPeriod = false;
  bool _horizontalSwipe = false;
  bool _preserveScrollAfterPaging = false;
  VelocityTracker? _swipeVelocity;

  /// Hourly views: the day columns, for turning a finger position into a time.
  final _columnsKey = GlobalKey();
  _EventMove<T>? _move;
  Offset? _movePointer;
  Timer? _moveTimer;

  /// Ticks of [_moveTimer] spent against the left or right edge, and since
  /// that last paged.
  int _edgeTicks = 0;
  int _ticksSincePage = 0;
  bool _monthMoving = false;

  bool get _pinching => _pinchDistance != null;

  void _swipeDown(PointerDownEvent event) {
    _swipePointers.add(event.pointer);
    if (_swipePointers.length != 1) {
      _swipeStart = null;
      setState(() => _horizontalSwipe = false);
      _finishPeriodDrag(cancelled: true);
      return;
    }
    _swipeStart = event.position;
    _swipeVelocity = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.position);
    final position = widget.view.isHourly && _horizontal.hasClients
        ? _horizontal.position
        : null;
    _swipeScrollOffset = position == null
        ? 0
        : position.pixels.clamp(0, position.maxScrollExtent);
    _swipeScrollExtent = position?.maxScrollExtent ?? 0;
  }

  double _periodDragOffset(Offset delta) {
    if (!_horizontalSwipe &&
        !_draggingPeriod &&
        (delta.dx.abs() < 18 || delta.dx.abs() <= delta.dy.abs() * 1.5)) {
      return 0;
    }
    final offset = delta.dx > 0
        ? math.max(0.0, delta.dx - _swipeScrollOffset)
        : math.min(0.0, delta.dx + _swipeScrollExtent - _swipeScrollOffset);
    if (offset > 0 && widget.onPreviousPeriod == null ||
        offset < 0 && widget.onNextPeriod == null) {
      return 0;
    }
    return offset;
  }

  void _swipeMove(PointerMoveEvent event) {
    if (_move != null) {
      _movePointer = event.position;
      _updateMove();
      return;
    }
    if (_monthMoving) return;
    final start = _swipeStart;
    if (start == null) return;
    final delta = event.position - start;
    if (!_horizontalSwipe &&
        delta.dx.abs() >= 18 &&
        delta.dx.abs() > delta.dy.abs() * 1.5) {
      if (_vertical.hasClients) _vertical.jumpTo(_vertical.offset);
      setState(() => _horizontalSwipe = true);
    }
    if (widget.onPeriodDrag == null) return;
    _swipeVelocity?.addPosition(event.timeStamp, event.position);
    final offset = _periodDragOffset(event.position - start);
    if (offset == 0 && !_draggingPeriod) return;
    if (!_draggingPeriod) {
      if (_vertical.hasClients) _vertical.jumpTo(_vertical.offset);
      setState(() => _draggingPeriod = true);
    }
    widget.onPeriodDrag!(
      offset,
      _vertical.hasClients ? _vertical.offset : 0,
      _horizontal.hasClients
          ? _horizontal.offset.clamp(0, _horizontal.position.maxScrollExtent)
          : 0,
    );
  }

  void _finishPeriodDrag({required bool cancelled, double velocity = 0}) {
    if (!_draggingPeriod) return;
    setState(() => _draggingPeriod = false);
    widget.onPeriodDragEnd?.call(cancelled, cancelled ? 0 : velocity);
    _swipeVelocity = null;
  }

  void _swipeEnd(PointerUpEvent event) {
    if (_move != null || _monthMoving) {
      _swipePointers.remove(event.pointer);
      _swipeStart = null;
      if (_move != null) _endMove();
      return;
    }
    final start = _swipeStart;
    _swipePointers.remove(event.pointer);
    _swipeStart = null;
    setState(() => _horizontalSwipe = false);
    if (_draggingPeriod) {
      if (start != null) {
        widget.onPeriodDrag?.call(
          _periodDragOffset(event.position - start),
          _vertical.hasClients ? _vertical.offset : 0,
          _horizontal.hasClients ? _horizontal.offset : 0,
        );
      }
      _swipeVelocity?.addPosition(event.timeStamp, event.position);
      _finishPeriodDrag(
        cancelled: false,
        velocity: _swipeVelocity?.getVelocity().pixelsPerSecond.dx ?? 0,
      );
      return;
    }
    if (start == null) return;
    final delta = event.position - start;
    if (delta.dx.abs() <= delta.dy.abs() * 1.5) return;
    // Only the drag beyond the available column scroll counts toward paging.
    final overscroll = delta.dx > 0
        ? delta.dx - _swipeScrollOffset
        : -delta.dx - (_swipeScrollExtent - _swipeScrollOffset);
    if (overscroll < 64) return;
    final callback = delta.dx > 0
        ? widget.onPreviousPeriod
        : widget.onNextPeriod;
    if (callback == null) return;
    if (widget.view.isHourly && _horizontal.hasClients) {
      _horizontal.jumpTo(
        _horizontal.offset.clamp(0, _horizontal.position.maxScrollExtent),
      );
    }
    callback();
  }

  void _swipeCancel(PointerCancelEvent event) {
    if (_move != null) _stopMove();
    _swipePointers.remove(event.pointer);
    _swipeStart = null;
    setState(() => _horizontalSwipe = false);
    _finishPeriodDrag(cancelled: true);
  }

  DateTime get _start =>
      calendarRangeStart(widget.focusedDay, widget.view, widget.monday);
  DateTime get _focusedDay {
    final utc = widget.focusedDay.toUtc();
    return DateTime.utc(utc.year, utc.month, utc.day);
  }

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    if (widget.view.isHourly && widget.initialVerticalOffset != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_vertical.hasClients) {
          _vertical.jumpTo(
            widget.initialVerticalOffset!.clamp(
              0,
              _vertical.position.maxScrollExtent,
            ),
          );
        }
        if (_horizontal.hasClients) {
          _horizontal.jumpTo(
            widget.initialHorizontalOffset.clamp(
              0,
              _horizontal.position.maxScrollExtent,
            ),
          );
        }
      });
    } else {
      _scrollToEvents();
    }
  }

  @override
  void didUpdateWidget(covariant CalendarGrid<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view != widget.view ||
        oldWidget.focusedDay != widget.focusedDay) {
      _preserveScrollAfterPaging =
          widget.view.isHourly &&
          oldWidget.view == widget.view &&
          widget.onPeriodDrag != null;
      if (!widget.view.isHourly ||
          oldWidget.view != widget.view ||
          widget.onPeriodDrag == null) {
        _scrollToEvents();
      }
    } else if (widget.view.isHourly &&
        oldWidget.hourHeight != widget.hourHeight &&
        _vertical.hasClients) {
      final anchor = _zoomAnchor;
      _zoomAnchor = null;
      final offset = anchor != null
          ? anchor.hour * widget.hourHeight - anchor.y
          : _vertical.offset * widget.hourHeight / oldWidget.hourHeight;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _vertical.hasClients) {
          _vertical.jumpTo(offset.clamp(0, _vertical.position.maxScrollExtent));
        }
      });
    } else if (oldWidget.items.isEmpty &&
        widget.items.isNotEmpty &&
        !_preserveScrollAfterPaging &&
        widget.initialVerticalOffset == null) {
      _scrollToEvents();
    }
  }

  void _pointerDown(PointerDownEvent event) {
    if (_pointers.isEmpty) _multiTouch = false;
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length > 1) _multiTouch = true;
    if (_pointers.length != 2 || !_vertical.hasClients) return;
    final points = _pointers.values.toList();
    final distance = (points[0] - points[1]).distance;
    if (distance < 1) return;
    _vertical.jumpTo(_vertical.offset);
    if (_horizontal.hasClients) _horizontal.jumpTo(_horizontal.offset);
    setState(() {
      _pinchDistance = distance;
      _pinchHourHeight = widget.hourHeight;
      final focalY = (points[0].dy + points[1].dy) / 2;
      _pinchHour = (_vertical.offset + focalY) / widget.hourHeight;
    });
  }

  void _pointerMove(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.localPosition;
    if (!_pinching || _pointers.length != 2) return;
    final points = _pointers.values.toList();
    final height =
        (_pinchHourHeight * (points[0] - points[1]).distance / _pinchDistance!)
            .clamp(40.0, 120.0);
    _zoomAnchor = (hour: _pinchHour, y: (points[0].dy + points[1].dy) / 2);
    widget.onHourHeightChanged(height);
  }

  void _pointerEnd(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_pinching && _pointers.length < 2) {
      setState(() => _pinchDistance = null);
    }
  }

  /// The part of [CalendarGrid.draft] on [day], in minutes from midnight.
  (double, double)? _draftMinutes(DateTime day) {
    final draft = widget.draft;
    if (draft == null) return null;
    return _minutesOn(draft.start, draft.end, day);
  }

  /// The part of [from]–[to] on [day], in minutes from midnight.
  static (double, double)? _minutesOn(
    DateTime from,
    DateTime to,
    DateTime day,
  ) {
    final start = from.toUtc().difference(day).inSeconds / 60;
    final end = to.toUtc().difference(day).inSeconds / 60;
    if (end <= 0 || start >= 1440 || end <= start) return null;
    return (start.clamp(0.0, 1440.0), end.clamp(0.0, 1440.0));
  }

  bool _canMove(T item) =>
      widget.onEventMoved != null &&
      item.start != null &&
      (widget.canMoveEvent?.call(item) ?? true);

  /// The time under [global] in the hourly views, or null outside them.
  DateTime? _timeAt(Offset global) {
    final box = _columnsKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final local = box.globalToLocal(global);
    final count = calendarDayCount(widget.view);
    final index = (local.dx / (box.size.width / count)).floor().clamp(
      0,
      count - 1,
    );
    final minutes = (local.dy * 60 / widget.hourHeight).clamp(0.0, 1440.0);
    return _start.add(
      Duration(days: index, microseconds: (minutes * 60e6).round()),
    );
  }

  DateTime _snap(DateTime time) {
    final step = widget.moveStep.inMicroseconds;
    return DateTime.fromMicrosecondsSinceEpoch(
      (time.microsecondsSinceEpoch / step).round() * step,
      isUtc: true,
    );
  }

  void _beginMove(T item, Offset global) {
    final at = _timeAt(global);
    if (at == null || _move != null) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _move = _EventMove(item, at.difference(item.start!), item.start!);
      _movePointer = global;
      _edgeTicks = 0;
      _ticksSincePage = 0;
    });
    _moveTimer = Timer.periodic(
      const Duration(milliseconds: 32),
      (_) => _moveTick(),
    );
  }

  void _updateMove() {
    final move = _move;
    final pointer = _movePointer;
    if (move == null || pointer == null) return;
    final at = _timeAt(pointer);
    if (at == null) return;
    final start = _snap(at.subtract(move.grab));
    if (start != move.start) {
      HapticFeedback.selectionClick();
      setState(() => move.start = start);
    }
  }

  /// Scrolls when the finger is near the top or bottom, and pages to the
  /// previous or next period after it rests against the left or right edge.
  void _moveTick() {
    final pointer = _movePointer;
    if (_move == null || pointer == null || !_vertical.hasClients) return;
    final viewport =
        _vertical.position.context.storageContext.findRenderObject()
            as RenderBox?;
    if (viewport == null || !viewport.hasSize) return;
    final rect = viewport.localToGlobal(Offset.zero) & viewport.size;
    const zone = 48.0;
    final over = pointer.dy < rect.top + zone
        ? pointer.dy - (rect.top + zone)
        : pointer.dy > rect.bottom - zone
        ? pointer.dy - (rect.bottom - zone)
        : 0.0;
    if (over != 0) {
      final position = _vertical.position;
      final target = (position.pixels + over * 0.4).clamp(
        0.0,
        position.maxScrollExtent,
      );
      if (target != position.pixels) _vertical.jumpTo(target);
    }
    final side = pointer.dx < rect.left + 56 + 24
        ? -1
        : pointer.dx > rect.right - 24
        ? 1
        : 0;
    _ticksSincePage++;
    if (side == 0) {
      _edgeTicks = 0;
    } else if (++_edgeTicks >= 18 && _ticksSincePage >= 28) {
      final page = side < 0 ? widget.onPreviousPeriod : widget.onNextPeriod;
      if (page != null) {
        _ticksSincePage = 0;
        HapticFeedback.selectionClick();
        page();
      }
    }
    _updateMove();
  }

  void _endMove() {
    final move = _move;
    _stopMove();
    if (move != null && move.start != move.item.start) {
      widget.onEventMoved?.call(move.item, move.start);
    }
  }

  void _stopMove() {
    _moveTimer?.cancel();
    _moveTimer = null;
    if (_move != null && mounted) {
      setState(() {
        _move = null;
        _movePointer = null;
      });
    }
  }

  /// Month view: [day] accepts dragged events, moving them there at the same
  /// time of day.
  Widget _dayDropTarget(DateTime day, Widget Function(bool hovering) builder) {
    if (widget.onEventMoved == null) return builder(false);
    return DragTarget<T>(
      onAcceptWithDetails: (details) {
        final item = details.data;
        final start = item.start!;
        final moved = DateTime.utc(
          day.year,
          day.month,
          day.day,
          start.hour,
          start.minute,
          start.second,
        );
        if (moved != start) widget.onEventMoved!(item, moved);
      },
      builder: (context, candidates, _) => builder(candidates.isNotEmpty),
    );
  }

  /// The moving copy of an event, labelled with where it will land.
  Widget _moveGhost(_EventMove<T> move) {
    final colors = Theme.of(context).colorScheme;
    final color = widget.eventColorBuilder(context, move.item);
    final locale = Localizations.localeOf(context).toString();
    final time = DateFormat.Hm(locale);
    final from = move.item.start!;
    final to = move.item.stop;
    final shift = move.start.difference(from);
    final end = to != null && to.isAfter(from)
        ? '–${time.format(to.add(shift))}'
        : '';
    return IgnorePointer(
      child: Material(
        key: const ValueKey('calendar-move-ghost'),
        elevation: 6,
        color: Color.alphaBlend(color.withValues(alpha: 0.3), colors.surface),
        shape: RoundedRectangleBorder(
          side: BorderSide(color: color, width: 2),
          borderRadius: BorderRadius.circular(5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${DateFormat.MMMEd(locale).format(move.start)} · '
                '${time.format(move.start)}$end',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                move.item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _draftTile(ColorScheme colors) => IgnorePointer(
    child: DecoratedBox(
      key: const ValueKey('calendar-draft'),
      decoration: BoxDecoration(
        color: colors.onSurface.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: colors.onSurfaceVariant.withValues(alpha: 0.6),
          width: 1.5,
        ),
      ),
    ),
  );

  void _tapEmptyTime(DateTime day, TapUpDetails details) {
    if (_multiTouch) return;
    final minute = (details.localPosition.dy * 60 / widget.hourHeight)
        .floor()
        .clamp(0, 1439);
    widget.onEmptyTimeTap!(day.add(Duration(minutes: minute)));
  }

  Widget _pinchViewport(Widget child) => Semantics(
    label: 'Hourly calendar. Pinch to zoom.',
    value: '${widget.hourHeight.round()} pixels per hour',
    increasedValue:
        '${(widget.hourHeight + 10).clamp(40.0, 120.0).round()} pixels per hour',
    decreasedValue:
        '${(widget.hourHeight - 10).clamp(40.0, 120.0).round()} pixels per hour',
    onIncrease: () =>
        widget.onHourHeightChanged((widget.hourHeight + 10).clamp(40.0, 120.0)),
    onDecrease: () =>
        widget.onHourHeightChanged((widget.hourHeight - 10).clamp(40.0, 120.0)),
    child: Listener(
      key: const ValueKey('calendar-pinch-viewport'),
      behavior: HitTestBehavior.opaque,
      onPointerDown: _pointerDown,
      onPointerMove: _pointerMove,
      onPointerUp: _pointerEnd,
      onPointerCancel: _pointerEnd,
      child: child,
    ),
  );

  /// Half an hour before the earliest event shown, or 08:00 without events.
  double _eventsOffset() {
    final count = calendarDayCount(widget.view);
    final end = _start.add(Duration(days: count));
    var earliest = 24.0;
    for (final item in widget.items) {
      if (item.start == null ||
          !item.start!.isBefore(end) ||
          !item.displayEnd.isAfter(_start)) {
        continue;
      }
      final hour = item.start!.isBefore(_start)
          ? 0.0
          : item.start!.hour + item.start!.minute / 60;
      earliest = math.min(earliest, hour);
    }
    return (earliest == 24 ? 8.0 : math.max(0.0, earliest - 0.5)) *
        widget.hourHeight;
  }

  void _scrollToEvents() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_vertical.hasClients) return;
      if (!widget.view.isHourly) {
        _vertical.jumpTo(0);
        return;
      }
      _vertical.jumpTo(
        _eventsOffset().clamp(0, _vertical.position.maxScrollExtent),
      );
    });
  }

  @override
  void dispose() {
    _moveTimer?.cancel();
    _clock?.cancel();
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  static const _eventTitleStyle = TextStyle(
    fontSize: 12,
    height: 1.2,
    fontWeight: FontWeight.w600,
  );

  double _textHeight(TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: 'Ag', style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final height = painter.height.ceilToDouble();
    painter.dispose();
    return height;
  }

  double get _eventMinimumHeight =>
      math.max(24, _textHeight(_eventTitleStyle) + 8);

  Widget _eventTile(
    T item, {
    required bool compact,
    bool schedule = false,
    bool feedback = false,
  }) {
    final movable = !schedule && !feedback && _canMove(item);
    final colors = Theme.of(context).colorScheme;
    final color = widget.eventColorBuilder(context, item);
    final label =
        widget.eventTooltipBuilder?.call(item) ??
        '${item.title}\n${item.timeLabel}';
    final leading = widget.eventLeadingBuilder?.call(context, item);
    final tile = _ReturnHighlight(
      key: ValueKey('calendar-highlight-${item.id}'),
      active: item.id == widget.highlightedEventId,
      color: color,
      child: Tooltip(
        // A long-press moves a movable event instead of showing this.
        triggerMode: movable ? TooltipTriggerMode.manual : null,
        message: label,
        child: Semantics(
          label: label,
          button: true,
          child: Material(
            color: color.withValues(alpha: 0.14),
            shape: RoundedRectangleBorder(
              side: BorderSide(color: color.withValues(alpha: 0.5)),
              borderRadius: BorderRadius.circular(5),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => widget.onEventTap(item),
              onLongPress: movable ? null : () => widget.onEventLongPress(item),
              child: schedule
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          if (leading != null)
                            Flexible(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: leading,
                              ),
                            ),
                          Expanded(
                            flex: 4,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(color: color),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  item.timeLabel,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final lineHeight = _textHeight(_eventTitleStyle);
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          child: ClipRect(
                            child: OverflowBox(
                              alignment: Alignment.topLeft,
                              minHeight: 0,
                              maxHeight: double.infinity,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      if (leading != null)
                                        Flexible(
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: leading,
                                          ),
                                        ),
                                      Expanded(
                                        child: Text(
                                          item.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: _eventTitleStyle.copyWith(
                                            color: color,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (!compact &&
                                      constraints.maxHeight >=
                                          lineHeight * 2 + 8)
                                    Text(
                                      DateFormat.Hm(
                                        Localizations.localeOf(context)
                                            .toString(),
                                      ).format(item.start!),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: colors.onSurfaceVariant,
                                        fontSize: 11,
                                        height: 1.2,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ),
      ),
    );
    if (!movable) return tile;
    if (!compact) {
      return Opacity(
        opacity: _move?.item.id == item.id ? 0.35 : 1,
        child: GestureDetector(
          onLongPressStart: (details) =>
              _beginMove(item, details.globalPosition),
          child: tile,
        ),
      );
    }
    // Month view: drop on another day, keeping the time.
    return LayoutBuilder(
      builder: (context, constraints) => LongPressDraggable<T>(
        data: item,
        hapticFeedbackOnStart: true,
        onDragStarted: () => setState(() => _monthMoving = true),
        onDragEnd: (_) {
          if (mounted) setState(() => _monthMoving = false);
        },
        feedback: SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: Material(
            type: MaterialType.transparency,
            elevation: 6,
            child: _eventTile(item, compact: true, feedback: true),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.35, child: tile),
        child: tile,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Listener(
    key: const ValueKey('calendar-period-viewport'),
    behavior: HitTestBehavior.opaque,
    onPointerDown: _swipeDown,
    onPointerMove: _swipeMove,
    onPointerUp: _swipeEnd,
    onPointerCancel: _swipeCancel,
    child: switch (widget.view) {
      CalendarViewType.month => _month(),
      CalendarViewType.schedule => _schedule(),
      _ => _timeline(),
    },
  );

  Widget _schedule() {
    final events =
        widget.items.where((item) => item.occursOn(_focusedDay)).toList()
          ..sort((a, b) {
            final byTime = a.start!.compareTo(b.start!);
            return byTime == 0 ? a.id.compareTo(b.id) : byTime;
          });
    return Column(
      children: [
        _dayHeading(_focusedDay),
        const Divider(height: 1),
        Expanded(
          child: Scrollbar(
            controller: _vertical,
            child: ListView.separated(
              key: const ValueKey('calendar-schedule-list'),
              controller: _vertical,
              physics: _horizontalSwipe
                  ? const NeverScrollableScrollPhysics()
                  : const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(8),
              itemCount: events.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) => KeyedSubtree(
                key: ValueKey('calendar-schedule-${events[index].id}'),
                child:
                    widget.scheduleItemBuilder?.call(context, events[index]) ??
                    _eventTile(events[index], compact: false, schedule: true),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _dayHeading(DateTime day, {bool month = false, bool narrow = false}) {
    final colors = Theme.of(context).colorScheme;
    final today = sameUtcDay(day, DateTime.now().toUtc());
    return TextButton(
      style: TextButton.styleFrom(
        minimumSize: Size.zero,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        foregroundColor: today ? colors.onPrimary : colors.onSurface,
        backgroundColor: today ? colors.primary : null,
      ),
      onPressed: () => widget.onDayTap(day),
      child: Text(
        month
            ? '${day.day}'
            : narrow
            ? '${DateFormat.E(Localizations.localeOf(context).toString()).format(day)}\n${day.day}'
            : DateFormat(
                'E d',
                Localizations.localeOf(context).toString(),
              ).format(day),
        textAlign: TextAlign.center,
        maxLines: narrow ? 2 : 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _month() {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final headingHeight = math.max(
          48.0,
          _textHeight(Theme.of(context).textTheme.labelLarge!) + 16,
        );
        final tileHeight = _eventMinimumHeight + 2;
        final weekdayHeight =
            _textHeight(Theme.of(context).textTheme.labelMedium!) + 16;
        final height = math.max(
          constraints.maxHeight,
          (headingHeight + tileHeight + 2) * 6 + weekdayHeight,
        );
        return SingleChildScrollView(
          child: SizedBox(
            height: height,
            child: Column(
              children: [
                Row(
                  children: List.generate(
                    7,
                    (index) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          DateFormat.E(
                            Localizations.localeOf(context).toString(),
                          ).format(_start.add(Duration(days: index))),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ),
                    ),
                  ),
                ),
                for (var row = 0; row < 6; row++)
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: List.generate(7, (column) {
                        final day = _start.add(
                          Duration(days: row * 7 + column),
                        );
                        final events =
                            widget.items
                                .where((item) => item.occursOn(day))
                                .toList()
                              ..sort((a, b) => a.start!.compareTo(b.start!));
                        return Expanded(
                          child: _dayDropTarget(
                            day,
                            (hovering) => Container(
                              decoration: BoxDecoration(
                                color: hovering
                                    ? colors.primary.withValues(alpha: 0.12)
                                    : day.month == _focusedDay.month
                                    ? null
                                    : colors.surfaceContainerLow,
                                border: Border(
                                  top: BorderSide(color: colors.outlineVariant),
                                  right: BorderSide(
                                    color: colors.outlineVariant,
                                  ),
                                ),
                              ),
                              child: LayoutBuilder(
                                builder: (context, cell) {
                                  final slots = math.max(
                                    0,
                                    ((cell.maxHeight - headingHeight) /
                                            tileHeight)
                                        .floor(),
                                  );
                                  final visible = events.length > slots
                                      ? math.max(0, slots - 1)
                                      : events.length;
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      SizedBox(
                                        height: headingHeight,
                                        child: Align(
                                          alignment: Alignment.center,
                                          child: _dayHeading(day, month: true),
                                        ),
                                      ),
                                      for (final item in events.take(visible))
                                        SizedBox(
                                          height: tileHeight,
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 2,
                                              vertical: 1,
                                            ),
                                            child: _eventTile(
                                              item,
                                              compact: true,
                                            ),
                                          ),
                                        ),
                                      if (events.length > visible)
                                        SizedBox(
                                          height: tileHeight,
                                          child: InkWell(
                                            onTap: () => widget.onDayTap(day),
                                            child: Center(
                                              child: Text(
                                                '+${events.length - visible} more',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelSmall,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _timeline() {
    final colors = Theme.of(context).colorScheme;
    final count = calendarDayCount(widget.view);
    final days = List.generate(count, (i) => _start.add(Duration(days: i)));
    final height = widget.hourHeight * 24;
    final now = DateTime.now().toUtc();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = widget.view == CalendarViewType.fitWeek
            ? constraints.maxWidth
            : math.max(constraints.maxWidth, 56 + count * 112.0);
        final dayWidth = (width - 56) / count;
        return Scrollbar(
          controller: _horizontal,
          thumbVisibility: width > constraints.maxWidth,
          notificationPredicate: (notification) =>
              notification.metrics.axis == Axis.horizontal,
          child: SingleChildScrollView(
            controller: _horizontal,
            physics: _pinching
                ? const NeverScrollableScrollPhysics()
                : const ClampingScrollPhysics(),
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              height: constraints.maxHeight,
              child: Column(
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 56,
                        child: widget.showTimeColumn
                            ? const Center(child: Text('UTC'))
                            : null,
                      ),
                      SizedBox(
                        width: width - 56,
                        child: ClipRect(
                          child: Transform.translate(
                            offset: Offset(widget.periodOffset, 0),
                            child: Row(
                              children: [
                                for (var index = 0; index < count; index++)
                                  SizedBox(
                                    width: dayWidth,
                                    child: widget._showsDay(index)
                                        ? _dayHeading(
                                            days[index],
                                            narrow:
                                                widget.view ==
                                                    CalendarViewType.fitWeek &&
                                                dayWidth < 72,
                                          )
                                        : null,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: _withHiddenHints(
                      days,
                      dayWidth,
                      _pinchViewport(
                        Scrollbar(
                          controller: _vertical,
                          child: SingleChildScrollView(
                            key: const ValueKey('calendar-time-scroll'),
                            controller: _vertical,
                            physics: _pinching || _horizontalSwipe
                                ? const NeverScrollableScrollPhysics()
                                : null,
                            child: SizedBox(
                              height: height,
                              child: Stack(
                                clipBehavior: Clip.hardEdge,
                                children: [
                                  for (var hour = 0; hour < 24; hour++) ...[
                                    if (widget.showTimeColumn)
                                      Positioned(
                                        key: ValueKey('calendar-hour-$hour'),
                                        top: hour * widget.hourHeight,
                                        left: 4,
                                        width: 48,
                                        child: Text(
                                          '${hour.toString().padLeft(2, "0")}:00',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall,
                                        ),
                                      ),
                                    if (widget.showTimeColumn)
                                      Positioned(
                                        top: hour * widget.hourHeight,
                                        left: 56,
                                        right: 0,
                                        child: widget.visibleGrid
                                            ? Divider(
                                                height: 1,
                                                color: colors.outlineVariant,
                                              )
                                            : SizedBox.shrink(),
                                      ),
                                  ],
                                  Positioned(
                                    top: 0,
                                    bottom: 0,
                                    left: 56,
                                    right: 0,
                                    child: ClipRect(
                                      child: Transform.translate(
                                        offset: Offset(widget.periodOffset, 0),
                                        child: Stack(
                                          key: _columnsKey,
                                          clipBehavior: Clip.none,
                                          children: [
                                            for (
                                              var index = 0;
                                              index < count;
                                              index++
                                            )
                                              if (widget._showsDay(index))
                                                Positioned(
                                                  top: 0,
                                                  bottom: 0,
                                                  left: dayWidth * index,
                                                  width: dayWidth,
                                                  child: DecoratedBox(
                                                    decoration: BoxDecoration(
                                                      border: Border(
                                                        left: BorderSide(
                                                          color: colors
                                                              .outlineVariant,
                                                        ),
                                                      ),
                                                    ),
                                                    child: LayoutBuilder(
                                                      builder: (context, _) {
                                                        final minimumHeight =
                                                            _eventMinimumHeight;
                                                        final placements =
                                                            layoutCalendarDay(
                                                              widget.items,
                                                              days[index],
                                                              minimumMinutes:
                                                                  minimumHeight *
                                                                  60 /
                                                                  widget
                                                                      .hourHeight,
                                                            );
                                                        return Stack(
                                                          children: [
                                                            if (widget
                                                                    .onEmptyTimeTap !=
                                                                null)
                                                              Positioned.fill(
                                                                child: GestureDetector(
                                                                  behavior:
                                                                      HitTestBehavior
                                                                          .opaque,
                                                                  onTapUp:
                                                                      (
                                                                        details,
                                                                      ) => _tapEmptyTime(
                                                                        days[index],
                                                                        details,
                                                                      ),
                                                                ),
                                                              ),
                                                            if (_draftMinutes(
                                                                  days[index],
                                                                )
                                                                case (
                                                                  final from,
                                                                  final to,
                                                                ))
                                                              Positioned(
                                                                top:
                                                                    from /
                                                                    60 *
                                                                    widget
                                                                        .hourHeight,
                                                                height:
                                                                    (to -
                                                                        from) /
                                                                    60 *
                                                                    widget
                                                                        .hourHeight,
                                                                left: 2,
                                                                width: math.max(
                                                                  1,
                                                                  dayWidth - 4,
                                                                ),
                                                                child:
                                                                    _draftTile(
                                                                      colors,
                                                                    ),
                                                              ),
                                                            for (final placement
                                                                in placements)
                                                              Positioned(
                                                                key: ValueKey(
                                                                  '${placement.item.id}_${days[index].toIso8601String()}',
                                                                ),
                                                                top:
                                                                    placement
                                                                        .startMinute /
                                                                    60 *
                                                                    widget
                                                                        .hourHeight,
                                                                height:
                                                                    (placement
                                                                            .endMinute -
                                                                        placement
                                                                            .startMinute) /
                                                                    60 *
                                                                    widget
                                                                        .hourHeight,
                                                                left:
                                                                    dayWidth *
                                                                        placement
                                                                            .column /
                                                                        placement
                                                                            .columns +
                                                                    2,
                                                                width: math.max(
                                                                  1,
                                                                  dayWidth /
                                                                          placement
                                                                              .columns -
                                                                      4,
                                                                ),
                                                                child:
                                                                    _eventTile(
                                                                      placement
                                                                          .item,
                                                                      compact:
                                                                          false,
                                                                    ),
                                                              ),
                                                            if (_move
                                                                case final move?)
                                                              if (_minutesOn(
                                                                    move.start,
                                                                    move.start.add(
                                                                      move
                                                                          .item
                                                                          .displayEnd
                                                                          .difference(
                                                                            move.item.start!,
                                                                          ),
                                                                    ),
                                                                    days[index],
                                                                  )
                                                                  case (
                                                                    final from,
                                                                    final to,
                                                                  ))
                                                                Positioned(
                                                                  top:
                                                                      from /
                                                                      60 *
                                                                      widget
                                                                          .hourHeight,
                                                                  height: math.max(
                                                                    (to - from) /
                                                                        60 *
                                                                        widget.hourHeight,
                                                                    _eventMinimumHeight,
                                                                  ),
                                                                  left: 2,
                                                                  width: math.max(
                                                                    1,
                                                                    dayWidth -
                                                                        4,
                                                                  ),
                                                                  child:
                                                                      _moveGhost(
                                                                        move,
                                                                      ),
                                                                ),
                                                            if (sameUtcDay(
                                                              days[index],
                                                              now,
                                                            ))
                                                              Positioned(
                                                                top:
                                                                    (now.hour +
                                                                        now.minute /
                                                                            60) *
                                                                    widget
                                                                        .hourHeight,
                                                                left: 0,
                                                                right: 0,
                                                                child: IgnorePointer(
                                                                  child: Divider(
                                                                    height: 2,
                                                                    thickness:
                                                                        2,
                                                                    color: colors
                                                                        .error,
                                                                  ),
                                                                ),
                                                              ),
                                                          ],
                                                        );
                                                      },
                                                    ),
                                                  ),
                                                ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Lays a fade in an event's color over the top or bottom edge of a day
  /// column when that event is scrolled out of sight above or below.
  Widget _withHiddenHints(List<DateTime> days, double dayWidth, Widget child) =>
      !widget.showHiddenEventHints
      ? child
      : LayoutBuilder(
          builder: (context, constraints) {
            final viewport = constraints.maxHeight;
            final placements = [
              for (final day in days)
                layoutCalendarDay(
                  widget.items,
                  day,
                  minimumMinutes: _eventMinimumHeight * 60 / widget.hourHeight,
                ),
            ];
            return Stack(
              children: [
                Positioned.fill(child: child),
                Positioned(
                  top: 0,
                  bottom: 0,
                  left: 56,
                  right: 0,
                  child: IgnorePointer(
                    child: ClipRect(
                      child: Transform.translate(
                        offset: Offset(widget.periodOffset, 0),
                        child: ListenableBuilder(
                          listenable: _vertical,
                          builder: (context, _) => Stack(
                            children: [
                              for (var index = 0; index < days.length; index++)
                                if (widget._showsDay(index))
                                  ..._hiddenHints(
                                    days[index],
                                    placements[index],
                                    dayWidth * index,
                                    dayWidth,
                                    viewport,
                                  ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );

  List<Widget> _hiddenHints(
    DateTime day,
    List<CalendarEventPlacement<T>> placements,
    double left,
    double dayWidth,
    double viewport,
  ) {
    const extent = 18.0;
    // The controller is briefly shared while switching views.
    if (_vertical.positions.length != 1) return const [];
    final offset = _vertical.offset;
    final hour = widget.hourHeight;
    final above = <CalendarEventPlacement<T>>[];
    final below = <CalendarEventPlacement<T>>[];
    for (final placement in placements) {
      if (placement.endMinute / 60 * hour <= offset + 1) {
        above.add(placement);
      } else if (placement.startMinute / 60 * hour >= offset + viewport - 1) {
        below.add(placement);
      }
    }
    // The event nearest the edge is drawn last, so its color shows on top.
    above.sort((a, b) => a.endMinute.compareTo(b.endMinute));
    below.sort((a, b) => b.startMinute.compareTo(a.startMinute));
    Widget hint(CalendarEventPlacement<T> placement, {required bool top}) {
      final color = widget.eventColorBuilder(context, placement.item);
      return Positioned(
        key: ValueKey(
          'calendar-hidden-${top ? 'above' : 'below'}-${placement.item.id}'
          '_${day.toIso8601String()}',
        ),
        top: top ? 0 : null,
        bottom: top ? null : 0,
        height: extent,
        left: left + dayWidth * placement.column / placement.columns + 2,
        width: math.max(1, dayWidth / placement.columns - 4),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: top ? Alignment.topCenter : Alignment.bottomCenter,
              end: top ? Alignment.bottomCenter : Alignment.topCenter,
              colors: [
                color.withValues(alpha: 0.55),
                color.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      );
    }

    return [
      for (final placement in above) hint(placement, top: true),
      for (final placement in below) hint(placement, top: false),
    ];
  }
}

/// Brightens the tile with its own color when [active] turns on, then lets
/// it fade back to normal.
class _ReturnHighlight extends StatefulWidget {
  const _ReturnHighlight({
    super.key,
    required this.active,
    required this.color,
    required this.child,
  });

  final bool active;
  final Color color;
  final Widget child;

  @override
  State<_ReturnHighlight> createState() => _ReturnHighlightState();
}

class _ReturnHighlightState extends State<_ReturnHighlight>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  /// Bright while the page slides away, then a slow fade.
  late final _strength = TweenSequence<double>([
    TweenSequenceItem(tween: ConstantTween(1), weight: 3),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 1,
        end: 0,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 7,
    ),
  ]).animate(_controller);

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.forward();
  }

  @override
  void didUpdateWidget(covariant _ReturnHighlight oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _strength,
    child: widget.child,
    builder: (context, child) {
      final strength = _controller.isAnimating ? _strength.value : 0.0;
      if (strength == 0) return child!;
      return DecoratedBox(
        key: const ValueKey('calendar-highlight'),
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: 0.3 * strength),
          borderRadius: BorderRadius.circular(5),
        ),
        child: child,
      );
    },
  );
}

/// An event being dragged to a new time.
class _EventMove<T extends CalendarEvent> {
  _EventMove(this.item, this.grab, this.start);

  final T item;

  /// From the event's start to where the finger picked it up.
  final Duration grab;

  /// Where it would land, snapped to the move step.
  DateTime start;
}
