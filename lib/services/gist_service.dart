import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/credential.dart';
import 'encryption_service.dart';

// ── Result wrapper ───────────────────────────────────────────────────────────

class SyncResult<T> {
  final bool success;
  final String message;
  final T? data;

  const SyncResult._({required this.success, required this.message, this.data});

  factory SyncResult.ok(String message, [T? data]) =>
      SyncResult._(success: true, message: message, data: data);

  factory SyncResult.err(String message) =>
      SyncResult._(success: false, message: message);
}

// ── Gist service ─────────────────────────────────────────────────────────────

/// Syncs the entire (encrypted) credential database via a single private GitHub Gist.
///
/// Flow
/// ─────
///  PUSH  : encrypt all credentials → PATCH (or POST) Gist file
///  PULL  : GET Gist → decrypt → return [Credential] list for local merge
///
/// Security
/// ─────────
///  • The blob written to GitHub is AES-256-CBC encrypted by [EncryptionService].
///  • The PAT is stored in [FlutterSecureStorage] (Keychain / Keystore / libsecret).
///  • The Gist is created with `"public": false` ("secret Gist").
class GistService {
  static final GistService _instance = GistService._internal();
  factory GistService() => _instance;
  GistService._internal();

  final _secure = const FlutterSecureStorage();
  final _enc = EncryptionService();

  static const _kPat = 'github_pat';
  static const _kGistId = 'gist_id';
  static const _kFilename = 'pm_data.enc';
  static const _kApiBase = 'https://api.github.com';

  // ── Accessors ────────────────────────────────────────────────

  Future<String?> getPat() => _secure.read(key: _kPat);
  Future<String?> getGistId() => _secure.read(key: _kGistId);

  Future<void> savePat(String pat) => _secure.write(key: _kPat, value: pat.trim());
  Future<void> saveGistId(String id) => _secure.write(key: _kGistId, value: id.trim());
  Future<void> clearGistId() => _secure.delete(key: _kGistId);

  Future<bool> isConfigured() async {
    final pat = await getPat();
    return pat != null && pat.isNotEmpty;
  }

  // ── Push ─────────────────────────────────────────────────────

  Future<SyncResult<void>> push(List<Credential> credentials) async {
    final pat = await getPat();
    if (pat == null || pat.isEmpty) {
      return SyncResult.err('GitHub PAT not configured. Go to Settings → Gist Sync.');
    }

    try {
      final blob = _enc.encrypt(
        jsonEncode(credentials.map((c) => c.toJson()).toList()),
      );
      final gistId = await getGistId();

      if (gistId == null || gistId.isEmpty) {
        return await _createGist(pat, blob);
      } else {
        return await _updateGist(pat, gistId, blob);
      }
    } catch (e) {
      return SyncResult.err('Push failed: $e');
    }
  }

  Future<SyncResult<void>> _createGist(String pat, String blob) async {
    final res = await http.post(
      Uri.parse('$_kApiBase/gists'),
      headers: _headers(pat),
      body: jsonEncode({
        'description': 'Password Manager Pro — Encrypted Vault',
        'public': false,
        'files': {
          _kFilename: {'content': blob},
        },
      }),
    );
    if (res.statusCode == 201) {
      final id = (jsonDecode(res.body) as Map<String, dynamic>)['id'] as String;
      await saveGistId(id);
      return SyncResult.ok('Gist created (ID: $id). Copy this ID to your other devices.');
    }
    return SyncResult.err('Create Gist failed: HTTP ${res.statusCode}\n${res.body}');
  }

  Future<SyncResult<void>> _updateGist(String pat, String gistId, String blob) async {
    final res = await http.patch(
      Uri.parse('$_kApiBase/gists/$gistId'),
      headers: _headers(pat),
      body: jsonEncode({
        'files': {
          _kFilename: {'content': blob},
        },
      }),
    );
    if (res.statusCode == 200) {
      return SyncResult.ok('Pushed successfully');
    }
    return SyncResult.err('Update Gist failed: HTTP ${res.statusCode}\n${res.body}');
  }

  // ── Pull ─────────────────────────────────────────────────────

  Future<SyncResult<List<Credential>>> pull() async {
    final pat = await getPat();
    if (pat == null || pat.isEmpty) {
      return SyncResult.err('GitHub PAT not configured.');
    }
    final gistId = await getGistId();
    if (gistId == null || gistId.isEmpty) {
      return SyncResult.err('Gist ID not set. Push from this device first, or enter the ID in Settings.');
    }

    try {
      final res = await http.get(
        Uri.parse('$_kApiBase/gists/$gistId'),
        headers: _headers(pat),
      );

      if (res.statusCode != 200) {
        return SyncResult.err('Fetch Gist failed: HTTP ${res.statusCode}');
      }

      final files =
          ((jsonDecode(res.body) as Map)['files'] as Map<String, dynamic>);

      if (!files.containsKey(_kFilename)) {
        return SyncResult.err('No data file found in Gist.');
      }

      final blob = files[_kFilename]['content'] as String;
      final decrypted = _enc.decrypt(blob);
      final list = jsonDecode(decrypted) as List;
      final credentials =
          list.map((e) => Credential.fromJson(e as Map<String, dynamic>)).toList();

      return SyncResult.ok('Pulled ${credentials.length} entries', credentials);
    } catch (e) {
      return SyncResult.err('Pull failed: $e');
    }
  }

  // ── Helpers ──────────────────────────────────────────────────

  Map<String, String> _headers(String pat) => {
        'Authorization': 'token $pat',
        'Accept': 'application/vnd.github.v3+json',
        'Content-Type': 'application/json',
        'X-GitHub-Api-Version': '2022-11-28',
      };
}
