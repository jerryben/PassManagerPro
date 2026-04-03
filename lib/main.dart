import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'theme/app_theme.dart';
import 'screens/master_password_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // sqflite_common_ffi required for Windows & Linux desktop targets
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
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
