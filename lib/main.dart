import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';
import 'theme/app_theme.dart';
import 'screens/master_password_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux) {
    // SQLite desktop support
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    // Window manager – sets title and icon in the OS taskbar / titlebar
    await windowManager.ensureInitialized();
    await windowManager.setTitle('Password Manager Pro');
    await windowManager.setMinimumSize(const Size(480, 600));

    // Set window icon (Linux taskbar / Windows taskbar)
    try {
      await windowManager.setIcon('assets/app_icon.png');
    } catch (_) {
      // Not critical if icon fails on some platforms
    }
  }

  runApp(const PasswordManagerApp());
}

class PasswordManagerApp extends StatelessWidget {
  const PasswordManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Password Manager Pro',
      theme: AppTheme.dark,
      home: const MasterPasswordScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
