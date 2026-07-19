import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/credential.dart';
import '../services/encryption_service.dart';
import '../services/lock_service.dart';
import '../services/storage_service.dart';
import '../services/gist_service.dart';
import '../theme/app_theme.dart';
import 'credential_form_screen.dart';
import 'master_password_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _storage = StorageService();
  final _gist    = GistService();
  final _search  = TextEditingController();

  List<Credential> _all      = [];
  List<Credential> _filtered = [];
  List<Credential> _recent   = [];
  Credential? _selected;

  bool   _loading  = true;
  bool   _syncing  = false;
  String _syncMsg  = '';
  bool   _syncOk   = true;

  @override
  void initState() {
    super.initState();
    _load().then((_) => _autoPull());
  }

  // ── Data loading ──────────────────────────────────────────────

  Future<void> _load() async {
    setState(() => _loading = true);
    final all    = await _storage.getAll();
    final recent = await _storage.getRecent();
    setState(() {
      _all = all;
      _filtered = _applySearch(all, _search.text);
      _recent = recent;
      _loading = false;
    });
  }

  List<Credential> _applySearch(List<Credential> src, String q) {
    if (q.isEmpty) return src;
    return src.where((c) => c.website.toLowerCase().contains(q.toLowerCase())).toList();
  }

  void _onSearch(String q) {
    setState(() => _filtered = _applySearch(_all, q));
  }

  // ── Sync ──────────────────────────────────────────────────────

  Future<void> _autoPull() async {
    if (!await _gist.isConfigured()) return;
    await _pull();
  }

  Future<void> _pull() async {
    _setSyncing('Pulling…');
    final r = await _gist.pull();
    if (r.success && r.data != null) {
      await _storage.mergeFromRemote(r.data!);
      await _load();
      _setSyncMsg('✓ Pulled', true);
    } else {
      _setSyncMsg(r.message, false);
    }
    setState(() => _syncing = false);
  }

  Future<void> _push() async {
    _setSyncing('Pushing…');
    final all = await _storage.getAllForSync();
    final r   = await _gist.push(all);
    _setSyncMsg(r.success ? '✓ Pushed' : r.message, r.success);
    setState(() => _syncing = false);
  }

  Future<void> _fullSync() async {
    final all = await _storage.getAllForSync();
    _setSyncing('Syncing…');
    await _gist.push(all);
    await _pull();
  }

  void _setSyncing(String msg) => setState(() { _syncing = true; _syncMsg = msg; });

  void _setSyncMsg(String msg, bool ok) {
    setState(() { _syncMsg = msg; _syncOk = ok; });
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _syncMsg = '');
    });
  }

  // ── Navigation ────────────────────────────────────────────────

  Future<void> _openForm(Credential? c) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CredentialFormScreen(credential: c)),
    );
    if (changed == true) {
      await _load();
      if (await _gist.isConfigured()) await _push();
    }
  }

  Future<void> _select(Credential c) async {
    await _storage.recordAccess(c.id);
    final recent = await _storage.getRecent();
    setState(() { _selected = c; _recent = recent; });
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width > 720;

    return InactivityDetector(
      child: Scaffold(
      backgroundColor: AppTheme.background,
      appBar: _appBar(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : wide
              ? Row(children: [
                  SizedBox(width: 280, child: _sidebar()),
                  const VerticalDivider(width: 1, color: AppTheme.border),
                  Expanded(child: _selected != null ? _detail(_selected!) : _empty()),
                ])
              : _sidebar(),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(null),
        tooltip: 'New credential',
        child: const Icon(Icons.add),
      ),
    ),   // InactivityDetector
    );
  }

  AppBar _appBar() {
    return AppBar(
      title: Row(
        children: [
          const Icon(Icons.lock, color: AppTheme.primary, size: 20),
          const SizedBox(width: 8),
          const Text('Password Manager Pro'),
          if (_syncMsg.isNotEmpty) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (_syncOk ? AppTheme.success : AppTheme.error).withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _syncMsg,
                style: TextStyle(
                  fontSize: 12,
                  color: _syncOk ? AppTheme.success : AppTheme.error,
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (_syncing)
          const Padding(
            padding: EdgeInsets.all(16),
            child: SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
            ),
          ),
        IconButton(
          icon: const Icon(Icons.sync),
          tooltip: 'Sync with Gist',
          onPressed: _syncing ? null : _fullSync,
        ),
        IconButton(
          icon: const Icon(Icons.lock_outline),
          tooltip: 'Lock vault',
          onPressed: () {
            LockService().lock();
          },
        ),
        IconButton(
          icon: const Icon(Icons.settings),
          tooltip: 'Settings',
          onPressed: () async {
            // Settings returns true if a sync/restore happened
            final didSync = await Navigator.of(context).push<bool>(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            );
            // Always reload — if data was pulled in Settings, show it now
            await _load();
            if (didSync == true) {
              _setSyncMsg('✓ Credentials updated', true);
            }
          },
        ),
      ],
    );
  }

  // ── Sidebar ───────────────────────────────────────────────────

  Widget _sidebar() {
    return Container(
      color: AppTheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _search,
              onChanged: _onSearch,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Search…',
                prefixIcon: Icon(Icons.search, size: 20),
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          if (_recent.isNotEmpty) ...[
            _sectionLabel('⚡  Recent'),
            ..._recent.map((c) => _tile(c)),
            const Divider(color: AppTheme.border),
          ],
          _sectionLabel('📁  All Credentials'),
          Expanded(
            child: _filtered.isEmpty
                ? const Center(
                    child: Text('No credentials found',
                        style: TextStyle(color: AppTheme.textSecondary)))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 80),
                    itemCount: _filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 2),
                    itemBuilder: (_, i) => _tile(_filtered[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
        child: Text(
          t,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
          ),
        ),
      );

  Widget _tile(Credential c) {
    final sel = _selected?.id == c.id;
    return GestureDetector(
      onTap: () {
        _select(c);
        if (MediaQuery.of(context).size.width <= 720) _openForm(c);
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: sel
              ? AppTheme.primary.withOpacity(0.12)
              : AppTheme.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: sel
              ? Border.all(color: AppTheme.primary.withOpacity(0.35))
              : null,
        ),
        child: Row(
          children: [
            _avatar(c),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.website,
                      style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500)),
                  if (c.email != null && c.email!.isNotEmpty)
                    Text(c.email!,
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatar(Credential c) {
    return CircleAvatar(
      radius: 16,
      backgroundColor: AppTheme.primary.withOpacity(0.18),
      child: Text(
        c.website.isNotEmpty ? c.website[0].toUpperCase() : '?',
        style: const TextStyle(
            color: AppTheme.primary,
            fontWeight: FontWeight.bold,
            fontSize: 13),
      ),
    );
  }

  // ── Detail panel ──────────────────────────────────────────────

  Widget _empty() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_open_outlined, color: AppTheme.textSecondary, size: 60),
          SizedBox(height: 16),
          Text('Select a credential or tap + to add one',
              style: TextStyle(color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  Widget _detail(Credential c) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: AppTheme.primary.withOpacity(0.18),
                child: Text(
                  c.website[0].toUpperCase(),
                  style: const TextStyle(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 22),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.website,
                        style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.bold)),
                    if (c.url != null && c.url!.isNotEmpty)
                      Text(c.url!,
                          style: const TextStyle(
                              color: AppTheme.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _openForm(c),
                icon: const Icon(Icons.edit, size: 15),
                label: const Text('Edit'),
              ),
            ],
          ),
          const SizedBox(height: 28),

          if (c.email != null && c.email!.isNotEmpty)
            _plainField('📧  Email / Username', c.email!),
          // Password — optional (SSO entries may not have one)
          if (c.password != null && c.password!.isNotEmpty)
            _maskedField('🔑  Password', c.password!)
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(children: [
                const Text('🔑  Password  ',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceAlt,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: const Text('SSO — no password stored',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                ),
              ]),
            ),

          // Notes
          if (c.notes != null && c.notes!.isNotEmpty)
            _plainField('📝  Notes', c.notes!),

          // Multiple API keys
          for (var i = 0; i < c.apiKeys.length; i++)
            _maskedField(
              c.apiKeys.length == 1
                  ? '🔐  API Key'
                  : '🔐  API Key \${i + 1}',
              c.apiKeys[i],
            ),

          const SizedBox(height: 12),
          Text(
            'Created \${_fmt(c.createdAt)}  •  Modified \${_fmt(c.modifiedAt)}',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _plainField(String label, String value) {
    return _fieldBox(label, [
      Expanded(child: Text(value, style: const TextStyle(color: AppTheme.textPrimary))),
      _CopyBtn(value: value),
    ]);
  }

  Widget _maskedField(String label, String value) {
    return _MaskedRow(label: label, value: value);
  }

  Widget _fieldBox(String label, List<Widget> row) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          const SizedBox(height: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(children: row),
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }
}

// ── Shared subwidgets ────────────────────────────────────────────────────────

class _MaskedRow extends StatefulWidget {
  final String label;
  final String value;
  const _MaskedRow({required this.label, required this.value});

  @override
  State<_MaskedRow> createState() => _MaskedRowState();
}

class _MaskedRowState extends State<_MaskedRow> {
  bool _vis = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.label,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          const SizedBox(height: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _vis ? widget.value : '•' * 18,
                    style: const TextStyle(
                        color: AppTheme.textPrimary, letterSpacing: 1.5),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    _vis ? Icons.visibility_off : Icons.visibility,
                    color: AppTheme.textSecondary,
                    size: 18,
                  ),
                  onPressed: () => setState(() => _vis = !_vis),
                ),
                _CopyBtn(value: widget.value),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CopyBtn extends StatefulWidget {
  final String value;
  const _CopyBtn({required this.value});

  @override
  State<_CopyBtn> createState() => _CopyBtnState();
}

class _CopyBtnState extends State<_CopyBtn> {
  bool _copied = false;

  Future<void> _copy() async {
    if (widget.value.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: widget.value));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: _copy,
      style: TextButton.styleFrom(
        foregroundColor: _copied ? AppTheme.success : AppTheme.textSecondary,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        _copied ? '✓ Copied' : 'Copy',
        style: const TextStyle(fontSize: 12),
      ),
    );
  }
}
