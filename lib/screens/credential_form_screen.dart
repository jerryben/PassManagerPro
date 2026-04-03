import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/credential.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

class CredentialFormScreen extends StatefulWidget {
  final Credential? credential;

  const CredentialFormScreen({super.key, this.credential});

  @override
  State<CredentialFormScreen> createState() => _CredentialFormScreenState();
}

class _CredentialFormScreenState extends State<CredentialFormScreen> {
  final _storage = StorageService();

  final _websiteCtrl  = TextEditingController();
  final _urlCtrl      = TextEditingController();
  final _emailCtrl    = TextEditingController();
  final _pwCtrl       = TextEditingController();
  final _apiKeyCtrl   = TextEditingController();

  bool   _showPw     = false;
  bool   _showApi    = false;
  bool   _busy       = false;
  String _strength   = '';
  Color  _strengthClr = Colors.transparent;

  bool get _editing => widget.credential != null;

  // ── Lifecycle ─────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    if (_editing) {
      final c = widget.credential!;
      _websiteCtrl.text = c.website;
      _urlCtrl.text     = c.url    ?? '';
      _emailCtrl.text   = c.email  ?? '';
      _pwCtrl.text      = c.password;
      _apiKeyCtrl.text  = c.apiKey ?? '';
      _evalStrength(c.password);
    }
    _pwCtrl.addListener(() => _evalStrength(_pwCtrl.text));
  }

  @override
  void dispose() {
    _websiteCtrl.dispose();
    _urlCtrl.dispose();
    _emailCtrl.dispose();
    _pwCtrl.dispose();
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  // ── Password strength ─────────────────────────────────────────

  void _evalStrength(String pw) {
    if (pw.isEmpty) {
      setState(() { _strength = ''; _strengthClr = Colors.transparent; });
      return;
    }
    int score = 0;
    if (pw.length >= 8)  score++;
    if (pw.length >= 14) score++;
    if (RegExp(r'[A-Z]').hasMatch(pw)) score++;
    if (RegExp(r'[a-z]').hasMatch(pw)) score++;
    if (RegExp(r'[0-9]').hasMatch(pw)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(pw)) score++;

    if (score <= 2) {
      setState(() { _strength = 'Weak';   _strengthClr = AppTheme.error; });
    } else if (score <= 4) {
      setState(() { _strength = 'Medium'; _strengthClr = AppTheme.warning; });
    } else {
      setState(() { _strength = 'Strong'; _strengthClr = AppTheme.success; });
    }
  }

  // ── Password generator ────────────────────────────────────────

  void _generate() {
    const chars =
        'abcdefghijklmnopqrstuvwxyz'
        'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
        '0123456789'
        r'!@#$%^&*()_+-=[]{}|;:,.<>?';
    final rng = Random.secure();
    final len = 14 + rng.nextInt(5); // 14–18
    final pw  = List.generate(len, (_) => chars[rng.nextInt(chars.length)]).join();
    _pwCtrl.text = pw;
    Clipboard.setData(ClipboardData(text: pw));
    _snack('Password generated & copied to clipboard', AppTheme.success);
  }

  // ── Save / Delete ─────────────────────────────────────────────

  Future<void> _save() async {
    final website = _websiteCtrl.text.trim();
    final pw      = _pwCtrl.text;

    if (website.isEmpty) { _snack('Website name is required', AppTheme.error); return; }
    if (pw.isEmpty)      { _snack('Password is required',     AppTheme.error); return; }

    setState(() => _busy = true);

    final credential = _editing
        ? widget.credential!.copyWith(
            website:  website,
            password: pw,
            url:      _nullIfEmpty(_urlCtrl.text),
            email:    _nullIfEmpty(_emailCtrl.text),
            apiKey:   _nullIfEmpty(_apiKeyCtrl.text),
          )
        : Credential(
            website:  website,
            password: pw,
            url:      _nullIfEmpty(_urlCtrl.text),
            email:    _nullIfEmpty(_emailCtrl.text),
            apiKey:   _nullIfEmpty(_apiKeyCtrl.text),
          );

    await _storage.save(credential);
    setState(() => _busy = false);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final ok = await _confirm(
      'Delete Credential',
      'Delete "${widget.credential!.website}"? This cannot be undone.',
    );
    if (!ok) return;
    await _storage.softDelete(widget.credential!.id);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  // ── Helpers ───────────────────────────────────────────────────

  String? _nullIfEmpty(String s) => s.trim().isEmpty ? null : s.trim();

  void _snack(String msg, Color bg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Future<bool> _confirm(String title, String body) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppTheme.surface,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: AppTheme.border)),
            title: Text(title,
                style: const TextStyle(color: AppTheme.textPrimary)),
            content: Text(body,
                style: const TextStyle(color: AppTheme.textSecondary)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.error),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Delete')),
            ],
          ),
        ) ??
        false;
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(_editing ? 'Edit Credential' : 'New Credential'),
        actions: [
          if (_editing)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppTheme.error),
              tooltip: 'Delete',
              onPressed: _delete,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _field('🌐  Website', _websiteCtrl, required: true,
                    hint: 'GitHub', keyboard: TextInputType.text),
                const SizedBox(height: 16),
                _field('🔗  URL', _urlCtrl,
                    hint: 'https://github.com',
                    keyboard: TextInputType.url),
                const SizedBox(height: 16),
                _field('📧  Email / Username', _emailCtrl,
                    hint: 'you@example.com',
                    keyboard: TextInputType.emailAddress),
                const SizedBox(height: 16),
                _passwordSection(),
                const SizedBox(height: 16),
                _apiKeySection(),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _busy ? null : _save,
                  child: _busy
                      ? const SizedBox(
                          height: 20, width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(_editing ? 'Update Credential' : 'Save Credential'),
                ),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Form helpers ──────────────────────────────────────────────

  Widget _label(String text) {
    return Text(text,
        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12));
  }

  Widget _field(
    String label,
    TextEditingController ctrl, {
    bool required  = false,
    String? hint,
    TextInputType keyboard = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label + (required ? ' *' : '')),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          keyboardType: keyboard,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(hintText: hint),
        ),
      ],
    );
  }

  Widget _passwordSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('🔑  Password *'),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _pwCtrl,
                obscureText: !_showPw,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showPw ? Icons.visibility_off : Icons.visibility,
                      color: AppTheme.textSecondary, size: 20,
                    ),
                    onPressed: () => setState(() => _showPw = !_showPw),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              onPressed: _generate,
              icon: const Icon(Icons.auto_awesome, size: 16),
              label: const Text('Generate'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.surfaceAlt,
                foregroundColor: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
        if (_strength.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: _strengthClr.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _strength,
                  style: TextStyle(
                      color: _strengthClr,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _strength == 'Weak'
                        ? 0.33
                        : _strength == 'Medium'
                            ? 0.66
                            : 1.0,
                    backgroundColor: AppTheme.surfaceAlt,
                    color: _strengthClr,
                    minHeight: 4,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _apiKeySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('🔐  API Key (optional)'),
        const SizedBox(height: 6),
        TextField(
          controller: _apiKeyCtrl,
          obscureText: !_showApi,
          style: const TextStyle(
              color: AppTheme.textPrimary, fontFamily: 'monospace', fontSize: 13),
          decoration: InputDecoration(
            hintText: 'sk-…',
            suffixIcon: IconButton(
              icon: Icon(
                _showApi ? Icons.visibility_off : Icons.visibility,
                color: AppTheme.textSecondary, size: 20,
              ),
              onPressed: () => setState(() => _showApi = !_showApi),
            ),
          ),
        ),
      ],
    );
  }
}
