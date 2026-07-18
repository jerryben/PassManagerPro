import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/credential.dart';
import 'encryption_service.dart';

// ── Result wrapper ────────────────────────────────────────────────────────────

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

// ── Gist service ──────────────────────────────────────────────────────────────

/// Syncs the encrypted credential vault via a single private GitHub Gist.
///
/// ENCRYPTION NOTE
/// ───────────────
/// This service uses [EncryptionService.encryptForSync] /
/// [EncryptionService.decryptForSync] which derive a key from the master
/// password with a FIXED, app-level salt.  This means the blob is decryptable
/// on ANY device that knows the master password, unlike the local SQLite
/// encryption which uses a per-device random salt.
class GistService {
  static final GistService _instance = GistService._internal();
  factory GistService() => _instance;
  GistService._internal();

  final _secure = const FlutterSecureStorage();
  final _enc    = EncryptionService();

  static const _kPat      = 'github_pat';
  static const _kGistId   = 'gist_id';
  static const _kFilename = 'pm_data.enc';
  static const _kApiBase  = 'https://api.github.com';
  static const _timeout   = Duration(seconds: 20);

  // ── Accessors ─────────────────────────────────────────────────

  Future<String?> getPat()    => _secure.read(key: _kPat);
  Future<String?> getGistId() => _secure.read(key: _kGistId);

  /// Strips ALL whitespace before saving — prevents "hostname" errors from
  /// accidentally pasted IDs that contain a space or newline.
  Future<void> savePat(String pat) =>
      _secure.write(key: _kPat, value: pat.replaceAll(RegExp(r'\s+'), ''));

  Future<void> saveGistId(String id) =>
      _secure.write(key: _kGistId, value: id.replaceAll(RegExp(r'\s+'), ''));

  Future<void> clearGistId() => _secure.delete(key: _kGistId);

  Future<bool> isConfigured() async {
    final pat = await getPat();
    return pat != null && pat.isNotEmpty;
  }

  // ── Network pre-check ─────────────────────────────────────────

  Future<bool> _hasNetwork() async {
    try {
      final result = await InternetAddress.lookup('api.github.com')
          .timeout(const Duration(seconds: 5));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ── Push ──────────────────────────────────────────────────────

  Future<SyncResult<void>> push(List<Credential> credentials) async {
    final pat = await getPat();
    if (pat == null || pat.isEmpty) {
      return SyncResult.err(
          'GitHub PAT not configured. Go to Settings → Gist Sync.');
    }

    if (!await _hasNetwork()) {
      return SyncResult.err(
          'No internet connection. Check your network and try again.');
    }

    try {
      // ── Use cross-device sync key, NOT the device-specific local key ──
      final plainJson = jsonEncode(
          credentials.map((c) => c.toJson()).toList());
      final blob = _enc.encryptForSync(plainJson);

      final gistId = await getGistId();
      return gistId == null || gistId.isEmpty
          ? await _createGist(pat, blob)
          : await _updateGist(pat, gistId, blob);
    } on SocketException catch (e) {
      return SyncResult.err('Network error: ${e.message}');
    } on TimeoutException {
      return SyncResult.err('Request timed out. Check your connection.');
    } catch (e) {
      return SyncResult.err('Push failed: $e');
    }
  }

  Future<SyncResult<void>> _createGist(String pat, String blob) async {
    final res = await http
        .post(
          Uri.parse('$_kApiBase/gists'),
          headers: _headers(pat),
          body: jsonEncode({
            'description': 'Password Manager Pro — Encrypted Vault',
            'public': false,
            'files': {
              _kFilename: {'content': blob}
            },
          }),
        )
        .timeout(_timeout);

    if (res.statusCode == 201) {
      final id =
          (jsonDecode(res.body) as Map<String, dynamic>)['id'] as String;
      await saveGistId(id);
      return SyncResult.ok(
          'Gist created ✓\nID: $id\nCopy this ID to Settings on your other devices.');
    }
    return SyncResult.err(
        'Create Gist failed: HTTP ${res.statusCode}\n${res.body}');
  }

  Future<SyncResult<void>> _updateGist(
      String pat, String gistId, String blob) async {
    final res = await http
        .patch(
          Uri.parse('$_kApiBase/gists/$gistId'),
          headers: _headers(pat),
          body: jsonEncode({
            'files': {
              _kFilename: {'content': blob}
            }
          }),
        )
        .timeout(_timeout);

    if (res.statusCode == 200) return SyncResult.ok('Pushed ✓');
    return SyncResult.err(
        'Update Gist failed: HTTP ${res.statusCode}\n${res.body}');
  }

  // ── Pull ──────────────────────────────────────────────────────

  Future<SyncResult<List<Credential>>> pull() async {
    final pat = await getPat();
    if (pat == null || pat.isEmpty) {
      return SyncResult.err('GitHub PAT not configured.');
    }

    final rawGistId = await getGistId();
    if (rawGistId == null || rawGistId.isEmpty) {
      return SyncResult.err(
          'Gist ID not set.\n'
          'Push from your other device first, then paste its Gist ID here in Settings.');
    }

    // Extra safety: strip any whitespace that survived UI input
    final gistId = rawGistId.replaceAll(RegExp(r'\s+'), '');

    if (!await _hasNetwork()) {
      return SyncResult.err(
          'No internet connection. Check your network and try again.');
    }

    try {
      final res = await http
          .get(Uri.parse('$_kApiBase/gists/$gistId'), headers: _headers(pat))
          .timeout(_timeout);

      if (res.statusCode == 404) {
        return SyncResult.err(
            'Gist not found (404).\nVerify the Gist ID is correct.');
      }
      if (res.statusCode == 401) {
        return SyncResult.err(
            'Invalid PAT (401). Re-check your token in Settings.');
      }
      if (res.statusCode != 200) {
        return SyncResult.err('Fetch failed: HTTP ${res.statusCode}');
      }

      final body  = jsonDecode(res.body) as Map<String, dynamic>;
      final files = body['files'] as Map<String, dynamic>;

      if (!files.containsKey(_kFilename)) {
        return SyncResult.err(
            'Encrypted data file not found in Gist.\n'
            'Push from your other device first.');
      }

      final fileEntry = files[_kFilename] as Map<String, dynamic>;

      // GitHub truncates files >1 MB — fetch raw content if needed
      String blob;
      if (fileEntry['truncated'] == true) {
        final rawUrl  = fileEntry['raw_url'] as String;
        final rawRes  = await http.get(Uri.parse(rawUrl), headers: _headers(pat))
            .timeout(_timeout);
        if (rawRes.statusCode != 200) {
          return SyncResult.err(
              'Failed to fetch raw Gist content: HTTP ${rawRes.statusCode}');
        }
        blob = rawRes.body;
      } else {
        blob = fileEntry['content'] as String;
      }

      if (blob.isEmpty) {
        return SyncResult.err('Gist file is empty. Push from your other device first.');
      }

      // ── Decrypt with cross-device sync key ──────────────────────
      final decrypted   = _enc.decryptForSync(blob);
      final list        = jsonDecode(decrypted) as List;
      final credentials = list
          .map((e) => Credential.fromJson(e as Map<String, dynamic>))
          .toList();

      return SyncResult.ok(
          'Pulled ${credentials.length} entr${credentials.length == 1 ? 'y' : 'ies'} ✓',
          credentials);
    } on SocketException catch (e) {
      return SyncResult.err('Network error: ${e.message}');
    } on TimeoutException {
      return SyncResult.err('Request timed out. Check your connection.');
    } on FormatException catch (e) {
      return SyncResult.err(
          'Decryption failed — wrong master password on this device, '
          'or the Gist was not created by this app.\nDetail: $e');
    } catch (e) {
      return SyncResult.err('Pull failed: $e');
    }
  }

  // ── Helpers ───────────────────────────────────────────────────

  Map<String, String> _headers(String pat) => {
        'Authorization':        'token $pat',
        'Accept':               'application/vnd.github.v3+json',
        'Content-Type':         'application/json',
        'X-GitHub-Api-Version': '2022-11-28',
      };
}
