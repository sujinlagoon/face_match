// shift_window_calculator.dart
//
// Pure-logic shift window calculator for face_match offline services.
// Computes active punch windows based on ShiftModel buffers & policies.
// No Flutter / GetX / SQLite dependencies — fully unit-testable.

import '../../../data/models/shift_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Value objects
// ─────────────────────────────────────────────────────────────────────────────

/// Inclusive [start], exclusive [end] window for a shift session.
///
/// - [overnight] : true when outTime <= inTime (shift crosses midnight).
/// - [source]    : human-readable label for debug logging.
class ShiftWindow {
  final DateTime start;
  final DateTime end;
  final bool overnight;
  final String source;
  final DateTime? shiftIn;
  final DateTime? shiftOut;
  final Duration preBuffer;
  final Duration postBuffer;
  final bool allowPreShiftCheckIn;
  final bool allowPostShiftCheckOut;

  const ShiftWindow({
    required this.start,
    required this.end,
    required this.overnight,
    required this.source,
    this.shiftIn,
    this.shiftOut,
    this.preBuffer = const Duration(hours: 1),
    this.postBuffer = const Duration(hours: 8),
    this.allowPreShiftCheckIn = true,
    this.allowPostShiftCheckOut = true,
  });

  /// Returns true when [dt] falls inside [start, end).
  bool contains(DateTime dt) => !dt.isBefore(start) && dt.isBefore(end);

  /// Returns true if [dt] occurs before shift scheduled start.
  bool isBeforeShiftIn(DateTime dt) =>
      shiftIn != null && dt.isBefore(shiftIn!);

  /// Returns true if [dt] occurs after shift scheduled end.
  bool isAfterShiftOut(DateTime dt) =>
      shiftOut != null && dt.isAfter(shiftOut!);

  @override
  String toString() =>
      'ShiftWindow[$source](${start.toIso8601String()} '
      '- ${end.toIso8601String()}, overnight=$overnight, preBuffer=${preBuffer.inMinutes}m, postBuffer=${postBuffer.inMinutes}m)';
}

/// Parsed hour/minute/second triple from a shift time string.
class ShiftClock {
  final int hour;
  final int minute;
  final int second;
  const ShiftClock(this.hour, this.minute, this.second);
  int get totalMinutes => hour * 60 + minute;
}

// ─────────────────────────────────────────────────────────────────────────────
// ShiftWindowCalculator
// ─────────────────────────────────────────────────────────────────────────────

/// Computes the active punch window for a given [ShiftModel] and reference time.
///
/// ### Window definition
///   window.start = shiftIn  - preShiftBuffer   (early-arrival buffer if allowPreShiftCheckIn)
///   window.end   = shiftOut + postShiftBuffer  (overtime buffer if allowPostShiftCheckOut)
///
/// ### Policies
///   - [allowPreShiftCheckIn]  : When false, window starts strictly at [shiftIn].
///   - [allowPostShiftCheckOut] : When false, window ends strictly at [shiftOut].
///   - Default buffers: 1 hour pre-shift buffer, 8 hours post-shift buffer.
///
/// ### Overnight shifts
/// When outTime <= inTime the shift crosses midnight. Two candidates are
/// evaluated — one anchored on today, one on yesterday — and the one whose
/// window contains [at] is preferred. Falls back to today's window.
///
/// ### Fallback
/// When [shift] is null or its times cannot be parsed, returns a full
/// calendar-day window (today 00:00 → tomorrow 00:00).
class ShiftWindowCalculator {
  ShiftWindowCalculator._();

  static const Duration kDefaultPreShiftBuffer  = Duration(hours: 1);
  static const Duration kDefaultPostShiftBuffer = Duration(hours: 8);

  // ──────────────────────────────────────────────────────────────────────────
  // Primary API
  // ──────────────────────────────────────────────────────────────────────────

  /// Returns the active [ShiftWindow] for [at] (defaults to now).
  static ShiftWindow resolveActiveWindow({
    ShiftModel? shift,
    DateTime? at,
  }) {
    final DateTime now = at ?? DateTime.now();
    final DateTime day = _dayOnly(now);

    final ShiftClock? inClock  = _parseClock(shift?.inTime);
    final ShiftClock? outClock = _parseClock(shift?.outTime);

    // Fallback: full calendar day
    if (inClock == null || outClock == null) {
      return ShiftWindow(
        start: day,
        end: day.add(const Duration(days: 1)),
        overnight: false,
        source: 'calendar_day',
      );
    }

    final bool overnight = outClock.totalMinutes <= inClock.totalMinutes;

    // Evaluate policies from ShiftModel (defaults: allow=true, pre=1h, post=8h)
    final bool allowPre = shift?.allowPreShiftCheckIn ?? true;
    final Duration preBuffer = allowPre
        ? (shift?.preShiftBuffer ?? kDefaultPreShiftBuffer)
        : Duration.zero;

    final bool allowPost = shift?.allowPostShiftCheckOut ?? true;
    final Duration postBuffer = allowPost
        ? (shift?.postShiftBuffer ?? kDefaultPostShiftBuffer)
        : Duration.zero;

    final ShiftWindow todayWindow = _buildWindow(
      baseDay: day,
      inClock: inClock,
      outClock: outClock,
      overnight: overnight,
      preBuffer: preBuffer,
      postBuffer: postBuffer,
      allowPreShiftCheckIn: allowPre,
      allowPostShiftCheckOut: allowPost,
    );
    final ShiftWindow yesterdayWindow = _buildWindow(
      baseDay: day.subtract(const Duration(days: 1)),
      inClock: inClock,
      outClock: outClock,
      overnight: overnight,
      preBuffer: preBuffer,
      postBuffer: postBuffer,
      allowPreShiftCheckIn: allowPre,
      allowPostShiftCheckOut: allowPost,
    );

    if (todayWindow.contains(now)) return todayWindow;
    if (yesterdayWindow.contains(now)) return yesterdayWindow;
    return todayWindow;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Convenience helpers (used by OfflineServices)
  // ──────────────────────────────────────────────────────────────────────────

  /// Quick boolean: is [dt] inside the active window?
  static bool isInActiveWindow({
    required DateTime dt,
    ShiftModel? shift,
    DateTime? at,
  }) =>
      resolveActiveWindow(shift: shift, at: at).contains(dt);

  /// Is [dt] inside [window]?
  static bool isInWindow(DateTime dt, ShiftWindow window) =>
      window.contains(dt);

  /// Calendar date (midnight) of the shift day — used as attendance punchDate key.
  static DateTime shiftDay(ShiftWindow window) =>
      window.shiftIn != null ? _dayOnly(window.shiftIn!) : _dayOnly(window.start);

  /// Public clock parser — exposed for testing and OfflineServices.
  static ShiftClock? parseClock(String? raw) => _parseClock(raw);

  // ──────────────────────────────────────────────────────────────────────────
  // Internals
  // ──────────────────────────────────────────────────────────────────────────

  static ShiftWindow _buildWindow({
    required DateTime baseDay,
    required ShiftClock inClock,
    required ShiftClock outClock,
    required bool overnight,
    required Duration preBuffer,
    required Duration postBuffer,
    required bool allowPreShiftCheckIn,
    required bool allowPostShiftCheckOut,
  }) {
    final DateTime shiftIn  = _atClock(baseDay, inClock);
    final DateTime shiftOut = overnight
        ? _atClock(baseDay.add(const Duration(days: 1)), outClock)
        : _atClock(baseDay, outClock);

    final bool isToday = _dayOnly(baseDay) == _dayOnly(DateTime.now());
    final String src = overnight
        ? (isToday ? 'night_shift' : 'night_shift_prev')
        : (isToday ? 'day_shift'   : 'day_shift_prev');

    return ShiftWindow(
      start: shiftIn.subtract(preBuffer),
      end:   shiftOut.add(postBuffer),
      overnight: overnight,
      source: src,
      shiftIn: shiftIn,
      shiftOut: shiftOut,
      preBuffer: preBuffer,
      postBuffer: postBuffer,
      allowPreShiftCheckIn: allowPreShiftCheckIn,
      allowPostShiftCheckOut: allowPostShiftCheckOut,
    );
  }

  static DateTime _dayOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  static DateTime _atClock(DateTime day, ShiftClock c) =>
      DateTime(day.year, day.month, day.day, c.hour, c.minute, c.second);

  /// Accepts ISO datetime strings or "HH:mm[:ss]" strings.
  static ShiftClock? _parseClock(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final dt = DateTime.parse(raw);
      return ShiftClock(dt.hour, dt.minute, dt.second);
    } catch (_) {}
    try {
      final parts = raw.split(':');
      if (parts.length < 2) return null;
      final h = int.parse(parts[0].trim());
      final m = int.parse(parts[1].trim());
      final s = parts.length > 2 ? int.parse(parts[2].split('.').first.trim()) : 0;
      return ShiftClock(h, m, s);
    } catch (_) {}
    return null;
  }
}
