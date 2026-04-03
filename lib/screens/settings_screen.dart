import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../services/gist_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _gist    = GistService();
  final _storage = StorageService();

  final _patCtrl    = TextEditingController();
  final _gistIdCtrl = TextEditingController();

  bool   _showPat  = false;
  bool   _busy     = false;
  String _msg      = '';
  bool   _msgOk    = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _patCtrl.dispose();
    _gistIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final pat    = await _gist.getPat();
    final gistId = await _gist.getGistId();
    setState(() {
      _patCtrl.text    = pat    ?? '';
      _gistIdCtrl.text = gistId ?? '';
    });
  }

  // ── Actions ───────────────────────────────────────────────────

  Future<void> _saveSettings() async {
    await _gist.savePat(_patCtrl.text.trim());
    final id = _gistIdCtrl.text.trim();
    if (id.isNotEmpty) await _gist.saveGistId(id);
    _ok('Settings saved');
  }

  Future<void> _testAndPush() async {
    _run('Testing connection & pushing…', () async {
      final all = await _storage.getAllForSync();
      final r   = await _gist.push(all);
      // Refresh gist ID field if it was just created
      final gistId = await _gist.getGistId();
      setState(() => _gistIdCtrl.text = gistId ?? '');
      return r.success ? r.message : null;
    });
  }

  Future<void> _fullSync() async {
    _run('Syncing…', () async {
      final all  = await _storage.getAllForSync();
      await _gist.push(all);
      final pull = await _gist.pull();
      if (pull.success && pull.data != null) {
        await _storage.mergeFromRemote(pull.data!);
      }
      return pull.success ? 'Full sync complete' : pull.message;
    });
  }

  Future<void> _exportCsv() async {
    _run('Exporting CSV…', () async {
      final csv  = await _storage.exportCsv();
      final file = await _writeFile('passwords_export', 'csv', csv);
      return 'Exported to ${file.path}';
    });
  }

  Future<void> _exportBackup() async {
    _run('Creating backup…', () async {
      final json = await _storage.exportJson();
      final file = await _writeFile('passwords_backup', 'json', json);
      return 'Backup saved to ${file.path}';
    });
  }

  Future<File> _writeFile(String name, String ext, String content) async {
    final dir      = await getApplicationDocumentsDirectory();
    final ts       = DateTime.now().millisecondsSinceEpoch;
    final file     = File('${dir.path}/${name}_$ts.$ext');
    await file.writeAsString(content);
    return file;
  }

  // ── State helpers ─────────────────────────────────────────────

  Future<void> _run(String busyMsg, Future<String?> Function() fn) async {
    setState(() { _busy = true; _msg = busyMsg; _msgOk = true; });
    try {
      final result = await fn();
      _ok(result ?? 'Done');
    } catch (e) {
      _err('Error: $e');
    }
    setState(() => _busy = false);
  }

  void _ok(String msg)  { setState(() { _msg = msg;  _msgOk = true; }); _autoClear(); }
  void _err(String msg) { setState(() { _msg = msg;  _msgOk = false; }); _autoClear(); }

  void _autoClear() {
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) setState(() => _msg = '');
    });
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Settings')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _gistSection(),
                const SizedBox(height: 20),
                _dataSection(),
                const SizedBox(height: 20),
                _statusBanner(),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Sections ──────────────────────────────────────────────────

  Widget _gistSection() {
    return _card(
      title: '🔄  GitHub Gist Sync',
      children: [
        const Text(
          'Your credentials are AES-256 encrypted before leaving this device. '
          'Only an encrypted blob is stored in the Gist — GitHub cannot read your data.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 20),

        // PAT
        _label('Personal Access Token (PAT)'),
        const SizedBox(height: 6),
        TextField(
          controller: _patCtrl,
          obscureText: !_showPat,
          style: const TextStyle(
              color: AppTheme.textPrimary, fontFamily: 'monospace', fontSize: 13),
          decoration: InputDecoration(
            hintText: 'ghp_xxxxxxxxxxxxxxxxxxxx',
            suffixIcon: IconButton(
              icon: Icon(_showPat ? Icons.visibility_off : Icons.visibility,
                  color: AppTheme.textSecondary),
              onPressed: () => setState(() => _showPat = !_showPat),
            ),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          '→ github.com/settings/tokens  —  enable the "gist" scope only',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
        ),
        const SizedBox(height: 16),

        // Gist ID
        _label('Gist ID  (auto-filled after first push)'),
        const SizedBox(height: 6),
        TextField(
          controller: _gistIdCtrl,
          style: const TextStyle(
              color: AppTheme.textPrimary, fontFamily: 'monospace', fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Leave empty to auto-create on first push',
            suffixIcon: IconButton(
              icon: const Icon(Icons.copy, color: AppTheme.textSecondary, size: 18),
              tooltip: 'Copy Gist ID',
              onPressed: () {
                final id = _gistIdCtrl.text.trim();
                if (id.isEmpty) return;
                Clipboard.setData(ClipboardData(text: id));
                _ok('Gist ID copied — paste it on your other devices');
              },
            ),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Share only the Gist ID (not the PAT) with your other devices.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
        ),
        const SizedBox(height: 20),

        // Buttons
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: _busy ? null : _saveSettings,
                child: const Text('Save Settings'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _busy ? null : _testAndPush,
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.secondary),
                child: const Text('Test & Push'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _busy ? null : _fullSync,
          icon: _busy
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.sync),
          label: const Text('Full Sync (pull + push)'),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.surfaceAlt),
        ),
      ],
    );
  }

  Widget _dataSection() {
    return _card(
      title: '💾  Data Management',
      children: [
        _actionRow(
          icon: Icons.download,
          title: 'Export to CSV',
          subtitle: '⚠️  Unencrypted — store the file securely',
          color: AppTheme.warning,
          onTap: _busy ? null : _exportCsv,
        ),
        const SizedBox(height: 10),
        _actionRow(
          icon: Icons.save_alt,
          title: 'Local Backup (JSON)',
          subtitle: '⚠️  Unencrypted — store the file securely',
          color: AppTheme.secondary,
          onTap: _busy ? null : _exportBackup,
        ),
      ],
    );
  }

  Widget _statusBanner() {
    if (_msg.isEmpty) return const SizedBox.shrink();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: (_msgOk ? AppTheme.success : AppTheme.error).withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: (_msgOk ? AppTheme.success : AppTheme.error).withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(_msgOk ? Icons.check_circle_outline : Icons.error_outline,
              color: _msgOk ? AppTheme.success : AppTheme.error, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(_msg,
                style: TextStyle(
                    color: _msgOk ? AppTheme.success : AppTheme.error,
                    fontSize: 13)),
          ),
        ],
      ),
    );
  }

  // ── Widget helpers ────────────────────────────────────────────

  Widget _card({required String title, required List<Widget> children}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _label(String text) {
    return Text(text,
        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12));
  }

  Widget _actionRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: color, fontWeight: FontWeight.w600)),
                  Text(subtitle,
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 11)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: color.withOpacity(0.6)),
          ],
        ),
      ),
    );
  }
}
