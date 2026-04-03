import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/encryption_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';

class MasterPasswordScreen extends StatefulWidget {
  const MasterPasswordScreen({super.key});

  @override
  State<MasterPasswordScreen> createState() => _MasterPasswordScreenState();
}

class _MasterPasswordScreenState extends State<MasterPasswordScreen> {
  final _pwCtrl      = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _secure      = const FlutterSecureStorage();
  final _enc         = EncryptionService();
  final _storage     = StorageService();

  static const _kSalt     = 'master_salt';
  static const _kVerifier = 'master_verifier';

  bool _isSetup  = false; // true = first-run (create), false = unlock
  bool _loading  = true;
  bool _busy     = false;
  bool _showPw   = false;
  bool _showConf = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _detect();
  }

  Future<void> _detect() async {
    final salt = await _secure.read(key: _kSalt);
    setState(() {
      _isSetup = (salt == null);
      _loading = false;
    });
  }

  String _makeSalt() {
    final r = Random.secure();
    return List.generate(32, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> _submit() async {
    final pw = _pwCtrl.text;
    if (pw.isEmpty) { _err('Enter your master password'); return; }

    setState(() { _error = null; _busy = true; });

    if (_isSetup) {
      // ── First-run: create vault ──────────────────────────────
      if (pw.length < 8) { _err('Minimum 8 characters'); return; }
      if (_confirmCtrl.text != pw) { _err('Passwords do not match'); return; }

      final salt = _makeSalt();
      _enc.initialize(pw, salt);
      final verifier = _enc.createVerifier();

      await _secure.write(key: _kSalt,     value: salt);
      await _secure.write(key: _kVerifier, value: verifier);
    } else {
      // ── Subsequent runs: verify & unlock ─────────────────────
      final salt     = await _secure.read(key: _kSalt);
      final verifier = await _secure.read(key: _kVerifier);
      _enc.initialize(pw, salt!);
      if (verifier != null && !_enc.verifyPassword(verifier)) {
        _enc.reset();
        _err('Incorrect master password');
        return;
      }
    }

    await _storage.init();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  void _err(String msg) => setState(() { _error = msg; _busy = false; });

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Logo ──────────────────────────────────────────
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.primary.withOpacity(0.4), width: 2),
                  ),
                  child: const Icon(Icons.lock, color: AppTheme.primary, size: 40),
                ),
                const SizedBox(height: 28),

                Text(
                  _isSetup ? 'Create Your Vault' : 'Unlock Your Vault',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isSetup
                      ? 'Choose a strong master password.\nIt cannot be recovered if lost.'
                      : 'Enter your master password to continue.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 36),

                // ── Password field ────────────────────────────────
                TextField(
                  controller: _pwCtrl,
                  obscureText: !_showPw,
                  onSubmitted: _isSetup ? null : (_) => _submit(),
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Master Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_showPw ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _showPw = !_showPw),
                    ),
                  ),
                ),

                if (_isSetup) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _confirmCtrl,
                    obscureText: !_showConf,
                    onSubmitted: (_) => _submit(),
                    style: const TextStyle(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'Confirm Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_showConf ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _showConf = !_showConf),
                      ),
                    ),
                  ),
                ],

                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Icon(Icons.error_outline, color: AppTheme.error, size: 16),
                      const SizedBox(width: 6),
                      Text(_error!, style: const TextStyle(color: AppTheme.error)),
                    ],
                  ),
                ],

                const SizedBox(height: 28),
                ElevatedButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(_isSetup ? 'Create Vault' : 'Unlock'),
                ),

                const SizedBox(height: 24),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.shield_outlined, color: AppTheme.textSecondary, size: 14),
                    SizedBox(width: 6),
                    Text(
                      'AES-256 encrypted · master password never stored',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pwCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }
}
