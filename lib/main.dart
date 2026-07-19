import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';
import 'services/encryption_service.dart';
import 'services/lock_service.dart';
import 'theme/app_theme.dart';
import 'screens/master_password_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    await windowManager.ensureInitialized();
    await windowManager.setTitle('Password Manager Pro');
    await windowManager.setMinimumSize(const Size(480, 600));
    try {
      await windowManager.setIcon('assets/app_icon.png');
    } catch (_) {}
  }

  // Load saved auto-lock timeout before app starts
  await LockService().initialize();

  runApp(const PasswordManagerApp());
}

class PasswordManagerApp extends StatefulWidget {
  const PasswordManagerApp({super.key});

  @override
  State<PasswordManagerApp> createState() => _PasswordManagerAppState();
}

class _PasswordManagerAppState extends State<PasswordManagerApp>
    with WidgetsBindingObserver {

  // Global navigator key so LockService can navigate without a BuildContext
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Register the lock callback — called when inactivity timer fires
    LockService().registerLockCallback(_lockApp);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    LockService().unregisterLockCallback();
    super.dispose();
  }

  // ── App lifecycle (background / foreground) ───────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        LockService().onBackground();
        break;
      case AppLifecycleState.resumed:
        LockService().onForeground();
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  // ── Lock ──────────────────────────────────────────────────────

  void _lockApp() {
    // Reset encryption state so master password must be re-entered
    EncryptionService().reset();

    // Navigate to lock screen, removing all routes so back button
    // cannot return to the unlocked vault
    _navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MasterPasswordScreen()),
      (route) => false,
    );
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Password Manager Pro',
      theme: AppTheme.dark,
      navigatorKey: _navigatorKey,
      home: const MasterPasswordScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
