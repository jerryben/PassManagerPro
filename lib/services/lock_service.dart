import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Manages auto-lock on inactivity.
///
/// Usage
/// ─────
///  1. Call [LockService().initialize()] once at app start.
///  2. Wrap the unlocked UI with [InactivityDetector].
///  3. Call [LockService().registerLockCallback(fn)] so the service
///     can trigger navigation back to the lock screen.
///  4. Call [LockService().onActivity()] anywhere you want to
///     manually reset the timer (optional — InactivityDetector handles it).
///  5. Call [LockService().lock()] on manual lock or app background.
class LockService {
  static final LockService _instance = LockService._internal();
  factory LockService() => _instance;
  LockService._internal();

  static const _kTimeoutKey   = 'auto_lock_timeout_seconds';
  static const _secure        = FlutterSecureStorage();

  // Available timeout options shown in Settings
  static const List<({String label, int seconds})> timeoutOptions = [
    (label: '30 seconds',  seconds: 30),
    (label: '1 minute',    seconds: 60),
    (label: '2 minutes',   seconds: 120),
    (label: '5 minutes',   seconds: 300),
    (label: '10 minutes',  seconds: 600),
    (label: '15 minutes',  seconds: 900),
    (label: 'Never',       seconds: 0),
  ];

  static const int _defaultSeconds = 300; // 5 minutes

  int      _timeoutSeconds = _defaultSeconds;
  Timer?   _timer;
  VoidCallback? _onLock;   // set by the app shell

  bool get isNeverLock => _timeoutSeconds == 0;

  // ── Initialise ────────────────────────────────────────────────

  Future<void> initialize() async {
    final stored = await _secure.read(key: _kTimeoutKey);
    _timeoutSeconds = stored != null
        ? int.tryParse(stored) ?? _defaultSeconds
        : _defaultSeconds;
  }

  // ── Lock callback ─────────────────────────────────────────────

  /// Register the function to call when the timer fires.
  /// Typically navigates to MasterPasswordScreen and resets encryption state.
  void registerLockCallback(VoidCallback fn) {
    _onLock = fn;
  }

  void unregisterLockCallback() => _onLock = null;

  // ── Timer management ──────────────────────────────────────────

  /// Call on every user interaction to reset the inactivity timer.
  void onActivity() {
    if (isNeverLock) return;
    _timer?.cancel();
    _timer = Timer(Duration(seconds: _timeoutSeconds), _triggerLock);
  }

  /// Start the timer (call after successful unlock).
  void startTimer() => onActivity();

  /// Stop the timer (call when app is already locked).
  void stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// Immediately lock the app (manual lock button or app backgrounded).
  void lock() {
    stopTimer();
    _triggerLock();
  }

  void _triggerLock() {
    _onLock?.call();
  }

  // ── App lifecycle ─────────────────────────────────────────────

  /// Call when app goes to background — starts an aggressive short timer.
  void onBackground() {
    if (isNeverLock) return;
    // Lock after 30 s in background regardless of main timeout
    _timer?.cancel();
    _timer = Timer(
      Duration(seconds: _timeoutSeconds < 30 ? _timeoutSeconds : 30),
      _triggerLock,
    );
  }

  /// Call when app returns to foreground.
  void onForeground() => onActivity();

  // ── Settings ──────────────────────────────────────────────────

  int get timeoutSeconds => _timeoutSeconds;

  String get timeoutLabel {
    return timeoutOptions
        .firstWhere(
          (o) => o.seconds == _timeoutSeconds,
          orElse: () => (label: '5 minutes', seconds: 300),
        )
        .label;
  }

  Future<void> setTimeoutSeconds(int seconds) async {
    _timeoutSeconds = seconds;
    await _secure.write(key: _kTimeoutKey, value: seconds.toString());
    if (!isNeverLock) onActivity(); // restart timer with new value
  }
}


// ── InactivityDetector widget ─────────────────────────────────────────────────

/// Wraps any widget tree and resets the [LockService] inactivity timer
/// on every pointer (touch / mouse) event.
///
/// Place this around the home screen content — NOT the lock screen itself.
class InactivityDetector extends StatelessWidget {
  final Widget child;
  const InactivityDetector({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown:   (_) => LockService().onActivity(),
      onPointerMove:   (_) => LockService().onActivity(),
      onPointerSignal: (_) => LockService().onActivity(), // mouse scroll
      child: child,
    );
  }
}
