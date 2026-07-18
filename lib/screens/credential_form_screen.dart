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

  final _websiteCtrl = TextEditingController();
  final _urlCtrl     = TextEditingController();
  final _emailCtrl   = TextEditingController();
  final _pwCtrl      = TextEditingController();
  final _notesCtrl   = TextEditingController();

  // Multiple API keys — list of controllers
  final List<TextEditingController> _apiKeyCtrls = [];

  bool   _showPw   = false;
  bool   _busy     = false;
  String _strength = '';
  Color  _strengthClr = Colors.transparent;

  bool get _editing => widget.credential != null;

  // ── Lifecycle ──────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    if (_editing) {
      final c = widget.credential!;
      _websiteCtrl.text = c.website;
      _urlCtrl.text     = c.url     ?? '';
      _emailCtrl.text   = c.email   ?? '';
      _pwCtrl.text      = c.password ?? '';
      _notesCtrl.text   = c.notes   ?? '';
      // Populate API key controllers from saved keys
      for (final k in c.apiKeys) {
        _apiKeyCtrls.add(TextEditingController(text: k));
      }
      if (_pwCtrl.text.isNotEmpty) _evalStrength(_pwCtrl.text);
    }
    // Always start with at least one (empty) API key row
    if (_apiKeyCtrls.isEmpty) _apiKeyCtrls.add(TextEditingController());
    _pwCtrl.addListener(() => _evalStrength(_pwCtrl.text));
  }

  @override
  void dispose() {
    _websiteCtrl.dispose();
    _urlCtrl.dispose();
    _emailCtrl.dispose();
    _pwCtrl.dispose();
    _notesCtrl.dispose();
    for (final c in _apiKeyCtrls) c.dispose();
    super.dispose();
  }

  // ── Password strength ──────────────────────────────────────────

  void _evalStrength(String pw) {
    if (pw.isEmpty) {
      setState(() { _strength = ''; _strengthClr = Colors.transparent; });
      return;
    }
    int score = 0;
    if (pw.length >= 8)                            score++;
    if (pw.length >= 14)                           score++;
    if (RegExp(r'[A-Z]').hasMatch(pw))             score++;
    if (RegExp(r'[a-z]').hasMatch(pw))             score++;
    if (RegExp(r'[0-9]').hasMatch(pw))             score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(pw))      score++;

    if (score <= 2) {
      setState(() { _strength = 'Weak';   _strengthClr = AppTheme.error; });
    } else if (score <= 4) {
      setState(() { _strength = 'Medium'; _strengthClr = AppTheme.warning; });
    } else {
      setState(() { _strength = 'Strong'; _strengthClr = AppTheme.success; });
    }
  }

  // ── Password generator ─────────────────────────────────────────

  void _generate() {
    const chars =
        'abcdefghijklmnopqrstuvwxyz'
        'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
        '0123456789'
        r'!@#$%^&*()_+-=[]{}|;:,.<>?';
    final rng = Random.secure();
    final len = 14 + rng.nextInt(5);
    final pw  = List.generate(len, (_) => chars[rng.nextInt(chars.length)]).join();
    _pwCtrl.text = pw;
    Clipboard.setData(ClipboardData(text: pw));
    _snack('Password generated & copied to clipboard', AppTheme.success);
  }

  // ── API key helpers ────────────────────────────────────────────

  void _addApiKeyRow() {
    setState(() => _apiKeyCtrls.add(TextEditingController()));
  }

  void _removeApiKeyRow(int index) {
    setState(() {
      _apiKeyCtrls[index].dispose();
      _apiKeyCtrls.removeAt(index);
    });
  }

  List<String> _collectApiKeys() => _apiKeyCtrls
      .map((c) => c.text.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  // ── Save / Delete ──────────────────────────────────────────────

  Future<void> _save() async {
    final website = _websiteCtrl.text.trim();
    if (website.isEmpty) { _snack('Website name is required', AppTheme.error); return; }

    setState(() => _busy = true);

    final pw     = _pwCtrl.text.isEmpty ? null : _pwCtrl.text;
    final keys   = _collectApiKeys();
    final notes  = _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();

    final credential = _editing
        ? widget.credential!.copyWith(
            website:  website,
            password: pw,
            url:      _nullIfEmpty(_urlCtrl.text),
            email:    _nullIfEmpty(_emailCtrl.text),
            apiKeys:  keys,
            notes:    notes,
          )
        : Credential(
            website:  website,
            password: pw,
            url:      _nullIfEmpty(_urlCtrl.text),
            email:    _nullIfEmpty(_emailCtrl.text),
            apiKeys:  keys,
            notes:    notes,
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

  // ── Helpers ────────────────────────────────────────────────────

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
            title:   Text(title, style: const TextStyle(color: AppTheme.textPrimary)),
            content: Text(body,  style: const TextStyle(color: AppTheme.textSecondary)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Delete')),
            ],
          ),
        ) ??
        false;
  }

  // ── Build ──────────────────────────────────────────────────────

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
                // ── Website ──────────────────────────────────────
                _field('🌐  Website *', _websiteCtrl,
                    hint: 'GitHub, Gmail, AWS…'),
                const SizedBox(height: 16),

                // ── URL ──────────────────────────────────────────
                _field('🔗  URL', _urlCtrl,
                    hint: 'https://github.com',
                    keyboard: TextInputType.url),
                const SizedBox(height: 16),

                // ── Email ────────────────────────────────────────
                _field('📧  Email / Username', _emailCtrl,
                    hint: 'you@example.com',
                    keyboard: TextInputType.emailAddress),
                const SizedBox(height: 16),

                // ── Password (optional) ───────────────────────────
                _passwordSection(),
                const SizedBox(height: 16),

                // ── Notes ────────────────────────────────────────
                _field('📝  Notes', _notesCtrl,
                    hint: 'Recovery email, account type, plan…'),
                const SizedBox(height: 16),

                // ── API Keys ──────────────────────────────────────
                _apiKeysSection(),
                const SizedBox(height: 32),

                // ── Save ─────────────────────────────────────────
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

  // ── Form section helpers ───────────────────────────────────────

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
      );

  Widget _field(
    String label,
    TextEditingController ctrl, {
    String? hint,
    TextInputType keyboard = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
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
        Row(
          children: [
            _label('🔑  Password'),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.textSecondary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('optional',
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 10,
                      fontStyle: FontStyle.italic)),
            ),
          ],
        ),
        const SizedBox(height: 2),
        const Text(
          'Leave blank for SSO / social logins (Google, GitHub, etc.)',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _pwCtrl,
                obscureText: !_showPw,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Leave empty for SSO logins',
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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: _strengthClr.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(_strength,
                    style: TextStyle(
                        color: _strengthClr,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
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

  Widget _apiKeysSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _label('🔐  API Keys'),
            TextButton.icon(
              onPressed: _addApiKeyRow,
              icon: const Icon(Icons.add, size: 16, color: AppTheme.primary),
              label: const Text('Add Key',
                  style: TextStyle(color: AppTheme.primary, fontSize: 12)),
              style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
            ),
          ],
        ),
        const Text(
          'Add one or more API keys for this service.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
        ),
        const SizedBox(height: 8),

        // API key rows
        ...List.generate(_apiKeyCtrls.length, (i) => _apiKeyRow(i)),
      ],
    );
  }

  Widget _apiKeyRow(int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          // Key label badge
          Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Text('${index + 1}',
                  style: const TextStyle(
                      color: AppTheme.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
            ),
          ),
          // Text field
          Expanded(
            child: _ApiKeyField(controller: _apiKeyCtrls[index]),
          ),
          // Remove button (keep at least one row)
          if (_apiKeyCtrls.length > 1)
            IconButton(
              icon: const Icon(Icons.remove_circle_outline,
                  color: AppTheme.error, size: 20),
              tooltip: 'Remove',
              onPressed: () => _removeApiKeyRow(index),
            )
          else
            const SizedBox(width: 40),
        ],
      ),
    );
  }
}

// ── API Key field (show/hide + copy) ──────────────────────────────────────────

class _ApiKeyField extends StatefulWidget {
  final TextEditingController controller;
  const _ApiKeyField({required this.controller});

  @override
  State<_ApiKeyField> createState() => _ApiKeyFieldState();
}

class _ApiKeyFieldState extends State<_ApiKeyField> {
  bool _show   = false;
  bool _copied = false;

  Future<void> _copy() async {
    final v = widget.controller.text.trim();
    if (v.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: v));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: !_show,
      style: const TextStyle(
          color: AppTheme.textPrimary, fontFamily: 'monospace', fontSize: 13),
      decoration: InputDecoration(
        hintText: 'sk-… / AKIA… / Bearer …',
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(_show ? Icons.visibility_off : Icons.visibility,
                  color: AppTheme.textSecondary, size: 18),
              onPressed: () => setState(() => _show = !_show),
            ),
            TextButton(
              onPressed: _copy,
              style: TextButton.styleFrom(
                foregroundColor:
                    _copied ? AppTheme.success : AppTheme.textSecondary,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(_copied ? '✓' : 'Copy',
                  style: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }
}
