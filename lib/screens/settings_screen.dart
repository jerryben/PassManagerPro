import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../services/gist_service.dart';
import '../services/lock_service.dart';
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
  bool   _didSync  = false; // returned to home screen to trigger reload

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _patCtrl.dispose();
    _gistIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final pat    = await _gist.getPat();
    final gistId = await _gist.getGistId();
    setState(() {
      _patCtrl.text    = pat    ?? '';
      _gistIdCtrl.text = gistId ?? '';
    });
  }

  // ── Back navigation ────────────────────────────────────────────
  // Returns _didSync so the home screen knows whether to reload.

  void _goBack() => Navigator.of(context).pop(_didSync);

  // ── Gist actions ───────────────────────────────────────────────

  Future<void> _saveSettings() async {
    await _gist.savePat(_patCtrl.text);
    final id = _gistIdCtrl.text;
    if (id.isNotEmpty) await _gist.saveGistId(id);
    final cleanId = await _gist.getGistId();
    setState(() => _gistIdCtrl.text = cleanId ?? '');
    _ok('Settings saved ✓');
  }

  Future<void> _clearGistId() async {
    final ok = await _confirm(
      'Clear Gist ID',
      'Removes the saved Gist ID from this device only.\n\n'
      'Your local credentials are NOT deleted.\n'
      'The next Push will create a brand-new Gist.',
    );
    if (!ok) return;
    await _gist.clearGistId();
    setState(() => _gistIdCtrl.text = '');
    _ok('Gist ID cleared ✓');
  }

  /// Push only — send local data to Gist.
  /// Use this on the device that HAS the data (e.g. Linux).
  Future<void> _pushOnly() async {
    _run('Pushing to Gist…', () async {
      final all = await _storage.getAllForSync();
      if (all.isEmpty) {
        throw Exception(
            'No credentials to push.\n'
            'Add credentials first, or pull from another device.');
      }
      final r      = await _gist.push(all);
      final gistId = await _gist.getGistId();
      setState(() => _gistIdCtrl.text = gistId ?? '');
      if (!r.success) throw Exception(r.message);
      return 'Pushed ${all.length} entr${all.length == 1 ? 'y' : 'ies'} ✓\n\n'
             'Copy the Gist ID above to your other devices.';
    });
  }

  /// Pull only — fetch remote data and merge into local.
  /// Use this on a new device (e.g. Android) to get data from another device.
  Future<void> _pullOnly() async {
    _run('Pulling from Gist…', () async {
      final pull = await _gist.pull();
      if (!pull.success) throw Exception(pull.message);
      if (pull.data == null || pull.data!.isEmpty) {
        throw Exception(
            'The Gist is empty or has no credentials.\n\n'
            'Make sure you pushed from your other device first.');
      }
      await _storage.mergeFromRemote(pull.data!);
      _didSync = true;
      final count = pull.data!.length;
      return 'Pulled $count entr${count == 1 ? 'y' : 'ies'} ✓\n\n'
             'Tap the back arrow to see your credentials.';
    });
  }

  /// Full sync — PULL first (never lose remote data), then PUSH merged result.
  ///
  /// CORRECT ORDER:
  ///   1. Pull remote → merge into local
  ///   2. Push merged local → remote
  ///
  /// WRONG (old behaviour, now fixed):
  ///   1. Push local (empty on new device!) → wipes remote data
  ///   2. Pull empty data back
  Future<void> _fullSync() async {
    _run('Syncing…', () async {
      int pulled = 0;

      // ── Step 1: pull & merge ─────────────────────────────────────
      final pull = await _gist.pull();
      if (pull.success && pull.data != null && pull.data!.isNotEmpty) {
        await _storage.mergeFromRemote(pull.data!);
        pulled   = pull.data!.length;
        _didSync = true;
      } else if (!pull.success) {
        // If the Gist doesn't exist yet, that's OK — we'll create it on push.
        // Any other error should be surfaced.
        final isNoGist = pull.message.contains('Gist ID not set') ||
                         pull.message.contains('not found');
        if (!isNoGist) throw Exception('Pull failed: ${pull.message}');
      }

      // ── Step 2: push merged result ────────────────────────────────
      final all  = await _storage.getAllForSync();
      final push = await _gist.push(all);
      if (!push.success) throw Exception('Push failed: ${push.message}');

      final gistId = await _gist.getGistId();
      setState(() => _gistIdCtrl.text = gistId ?? '');

      final pushed = all.length;
      if (pulled > 0) {
        return 'Sync complete ✓\n'
               'Pulled $pulled entr${pulled == 1 ? 'y' : 'ies'}, '
               'pushed $pushed.\n\n'
               'Tap the back arrow to see your credentials.';
      }
      return 'Sync complete ✓  —  pushed $pushed entr${pushed == 1 ? 'y' : 'ies'} '
             '(nothing new to pull).';
    });
  }

  // ── Export / Import ────────────────────────────────────────────

  Future<void> _exportCsv() async {
    _run('Exporting CSV…', () async {
      final csv  = await _storage.exportCsv();
      final file = await _writeFile('passwords_export', 'csv', csv);
      return 'Exported to:\n${file.path}';
    });
  }

  Future<void> _exportBackup() async {
    _run('Creating backup…', () async {
      final json = await _storage.exportJson();
      final file = await _writeFile('passwords_backup', 'json', json);
      return 'Backup saved to:\n${file.path}';
    });
  }

  Future<void> _restoreBackup() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
    } catch (e) {
      _err('Could not open file picker: $e');
      return;
    }

    if (result == null || result.files.isEmpty) return;

    final ok = await _confirm(
      'Restore Backup',
      'Merges the selected backup into your current vault.\n\n'
      'Existing entries are kept — only newer versions from the '
      'backup will overwrite them.\n\nContinue?',
    );
    if (!ok) return;

    _run('Restoring backup…', () async {
      String content;
      final picked = result!.files.single;
      if (picked.path != null) {
        content = await File(picked.path!).readAsString();
      } else if (picked.bytes != null) {
        content = String.fromCharCodes(picked.bytes!);
      } else {
        throw Exception('Could not read the selected file.');
      }
      final count = await _storage.importJson(content);
      _didSync = true;
      return 'Restored $count entries ✓\n\nTap the back arrow to see them.';
    });
  }

  // ── Helpers ────────────────────────────────────────────────────

  Future<File> _writeFile(String name, String ext, String content) async {
    final dir  = await getApplicationDocumentsDirectory();
    final ts   = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/${name}_$ts.$ext');
    await file.writeAsString(content);
    return file;
  }

  Future<void> _run(String busyMsg, Future<String?> Function() fn) async {
    setState(() { _busy = true; _msg = busyMsg; _msgOk = true; });
    try {
      final result = await fn();
      _ok(result ?? 'Done');
    } catch (e) {
      _err(e.toString().replaceFirst('Exception: ', ''));
    }
    setState(() => _busy = false);
  }

  void _ok(String msg)  { setState(() { _msg = msg;  _msgOk = true;  }); _autoClear(); }
  void _err(String msg) { setState(() { _msg = msg;  _msgOk = false; }); _autoClear(); }

  void _autoClear() {
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted) setState(() => _msg = '');
    });
  }

  Future<bool> _confirm(String title, String body) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppTheme.surface,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: AppTheme.border)),
            title:   Text(title,
                style: const TextStyle(color: AppTheme.textPrimary)),
            content: Text(body,
                style: const TextStyle(
                    color: AppTheme.textSecondary, height: 1.5)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Confirm')),
            ],
          ),
        ) ??
        false;
  }

  // ── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // PopScope with canPop: false lets us intercept BOTH the back button
    // and the Android back gesture so we can return _didSync to home screen.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBack();
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: const Text('Settings'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _goBack,
          ),
        ),
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
                  _lockSection(),
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
      ),
    );
  }

  // ── Sections ───────────────────────────────────────────────────

  Widget _gistSection() {
    return _card(
      title: '🔄  GitHub Gist Sync',
      children: [
        // Info box
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.primary.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.primary.withOpacity(0.25)),
          ),
          child: const Text(
            '🔒  Credentials are AES-256 encrypted before leaving this device.\n\n'
            '📋  Setup:\n'
            '  1. Enter PAT + Save Settings on BOTH devices\n'
            '  2. On the device with data → tap Push Only\n'
            '  3. Copy the Gist ID to your other device → Save Settings\n'
            '  4. On the new device → tap Pull Only',
            style: TextStyle(
                color: AppTheme.textSecondary, fontSize: 12, height: 1.6),
          ),
        ),
        const SizedBox(height: 20),

        // PAT
        _label('Personal Access Token (PAT)'),
        const SizedBox(height: 6),
        TextField(
          controller: _patCtrl,
          obscureText: !_showPat,
          style: const TextStyle(
              color: AppTheme.textPrimary,
              fontFamily: 'monospace',
              fontSize: 13),
          decoration: InputDecoration(
            hintText: 'ghp_xxxxxxxxxxxxxxxxxxxx',
            suffixIcon: IconButton(
              icon: Icon(
                  _showPat ? Icons.visibility_off : Icons.visibility,
                  color: AppTheme.textSecondary),
              onPressed: () => setState(() => _showPat = !_showPat),
            ),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          '→ github.com/settings/tokens → New token → enable "gist" scope only',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
        ),
        const SizedBox(height: 16),

        // Gist ID
        _label('Gist ID  (auto-set after first Push)'),
        const SizedBox(height: 6),
        TextField(
          controller: _gistIdCtrl,
          style: const TextStyle(
              color: AppTheme.textPrimary,
              fontFamily: 'monospace',
              fontSize: 12),
          decoration: InputDecoration(
            hintText: 'Leave empty — will be created on first Push',
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.copy,
                      color: AppTheme.textSecondary, size: 18),
                  tooltip: 'Copy Gist ID',
                  onPressed: () {
                    final id = _gistIdCtrl.text.trim();
                    if (id.isEmpty) return;
                    Clipboard.setData(ClipboardData(text: id));
                    _ok('Gist ID copied ✓ — paste it on your other devices');
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: AppTheme.error, size: 18),
                  tooltip: 'Clear Gist ID',
                  onPressed: _busy ? null : _clearGistId,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Each device uses its own PAT. The Gist ID is shared across all devices.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 11),
        ),
        const SizedBox(height: 20),

        // Save
        ElevatedButton(
          onPressed: _busy ? null : _saveSettings,
          style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.surfaceAlt),
          child: const Text('Save Settings'),
        ),
        const SizedBox(height: 12),

        // Push / Pull row
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _busy ? null : _pushOnly,
                icon: const Icon(Icons.upload, size: 16),
                label: const Text('Push Only'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.secondary),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _busy ? null : _pullOnly,
                icon: const Icon(Icons.download, size: 16),
                label: const Text('Pull Only'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Full sync
        ElevatedButton.icon(
          onPressed: _busy ? null : _fullSync,
          icon: _busy
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.sync),
          label: const Text('Full Sync  (pull first → push)'),
          style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.surfaceAlt),
        ),
      ],
    );
  }

  Widget _lockSection() {
    return _card(
      title: '🔒  Auto-Lock',
      children: [
        const Text(
          'Automatically locks the vault after a period of inactivity.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 16),
        _label('Lock after'),
        const SizedBox(height: 8),
        // Timeout option chips
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: LockService.timeoutOptions.map((opt) {
            final selected = LockService().timeoutSeconds == opt.seconds;
            return GestureDetector(
              onTap: () async {
                await LockService().setTimeoutSeconds(opt.seconds);
                setState(() {});
                _ok(opt.seconds == 0
                    ? 'Auto-lock disabled'
                    : 'Auto-lock set to \${opt.label} ✓');
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: selected
                      ? AppTheme.primary.withOpacity(0.20)
                      : AppTheme.surfaceAlt,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected ? AppTheme.primary : AppTheme.border,
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Text(
                  opt.label,
                  style: TextStyle(
                    color: selected ? AppTheme.primary : AppTheme.textSecondary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    fontSize: 13,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        // Current setting indicator
        Row(
          children: [
            const Icon(Icons.info_outline, color: AppTheme.textSecondary, size: 14),
            const SizedBox(width: 6),
            Text(
              LockService().isNeverLock
                  ? 'Auto-lock is disabled — not recommended'
                  : 'Vault locks after \${LockService().timeoutLabel} of inactivity',
              style: TextStyle(
                color: LockService().isNeverLock
                    ? AppTheme.warning
                    : AppTheme.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _dataSection() {
    return _card(
      title: '💾  Data Management',
      children: [
        _actionRow(
          icon: Icons.upload_file,
          title: 'Restore from Backup',
          subtitle: 'Merge a previously saved JSON backup into your vault',
          color: AppTheme.primary,
          onTap: _busy ? null : _restoreBackup,
        ),
        const SizedBox(height: 10),
        _actionRow(
          icon: Icons.save_alt,
          title: 'Export Backup (JSON)',
          subtitle: '⚠️  Unencrypted — store the file securely',
          color: AppTheme.secondary,
          onTap: _busy ? null : _exportBackup,
        ),
        const SizedBox(height: 10),
        _actionRow(
          icon: Icons.table_chart_outlined,
          title: 'Export to CSV',
          subtitle: '⚠️  Unencrypted — store the file securely',
          color: AppTheme.warning,
          onTap: _busy ? null : _exportCsv,
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
              _msgOk
                  ? Icons.check_circle_outline
                  : Icons.error_outline,
              color: _msgOk ? AppTheme.success : AppTheme.error,
              size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(_msg,
                style: TextStyle(
                    color: _msgOk ? AppTheme.success : AppTheme.error,
                    fontSize: 13,
                    height: 1.5)),
          ),
        ],
      ),
    );
  }

  // ── Widget helpers ─────────────────────────────────────────────

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

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Text(text,
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 12)),
      );

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
