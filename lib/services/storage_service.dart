import 'dart:convert';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/credential.dart';
import 'encryption_service.dart';

/// Local SQLite store. Every row's payload is AES-encrypted before write.
class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  Database? _db;
  final _enc = EncryptionService();

  // ── Lifecycle ─────────────────────────────────────────────────

  Future<void> init() async {
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      join(dbPath, 'password_manager.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE credentials (
            id         TEXT PRIMARY KEY,
            data       TEXT    NOT NULL,
            modifiedAt TEXT    NOT NULL,
            isDeleted  INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE recent (
            id         TEXT PRIMARY KEY,
            accessedAt TEXT NOT NULL
          )
        ''');
      },
    );
  }

  // ── Read ──────────────────────────────────────────────────────

  Future<List<Credential>> getAll({bool includeDeleted = false}) async {
    final rows = await _db!.query('credentials');
    final out  = <Credential>[];
    for (final row in rows) {
      if (!includeDeleted && row['isDeleted'] == 1) continue;
      final c = _decode(row['data'] as String);
      if (c != null) out.add(c);
    }
    out.sort((a, b) => a.website.toLowerCase().compareTo(b.website.toLowerCase()));
    return out;
  }

  Future<List<Credential>> getAllForSync() => getAll(includeDeleted: true);

  Future<List<Credential>> search(String query) async {
    final all = await getAll();
    if (query.isEmpty) return all;
    final q = query.toLowerCase();
    return all.where((c) => c.website.toLowerCase().contains(q)).toList();
  }

  Future<List<Credential>> getRecent() async {
    final rows = await _db!.query('recent', orderBy: 'accessedAt DESC', limit: 5);
    final out  = <Credential>[];
    for (final r in rows) {
      final cRows = await _db!.query(
        'credentials',
        where: 'id = ? AND isDeleted = 0',
        whereArgs: [r['id']],
      );
      if (cRows.isNotEmpty) {
        final c = _decode(cRows.first['data'] as String);
        if (c != null) out.add(c);
      }
    }
    return out;
  }

  // ── Write ─────────────────────────────────────────────────────

  Future<void> save(Credential credential) async {
    final encrypted = _enc.encrypt(jsonEncode(credential.toJson()));
    await _db!.insert(
      'credentials',
      {
        'id':         credential.id,
        'data':       encrypted,
        'modifiedAt': credential.modifiedAt.toIso8601String(),
        'isDeleted':  credential.isDeleted ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> softDelete(String id) async {
    final rows = await _db!.query('credentials', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return;
    final c = _decode(rows.first['data'] as String);
    if (c == null) return;
    await save(c.copyWith(isDeleted: true, modifiedAt: DateTime.now().toUtc()));
  }

  Future<void> recordAccess(String id) async {
    await _db!.insert(
      'recent',
      {'id': id, 'accessedAt': DateTime.now().toIso8601String()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ── Sync merge ────────────────────────────────────────────────

  Future<void> mergeFromRemote(List<Credential> remote) async {
    print('DEBUG: mergeFromRemote called with ${remote.length} credentials');
    for (final r in remote) {
      print('DEBUG: Processing credential: ${r.website} (id: ${r.id}, isDeleted: ${r.isDeleted})');
      final existing =
          await _db!.query('credentials', where: 'id = ?', whereArgs: [r.id]);
      if (existing.isEmpty) {
        print('DEBUG: New credential, saving: ${r.website}');
        await save(r);
      } else {
        final localTime = DateTime.parse(existing.first['modifiedAt'] as String);
        final localDeleted = existing.first['isDeleted'] == 1;
        print('DEBUG: Local modifiedAt: $localTime, isDeleted: $localDeleted');
        print('DEBUG: Remote modifiedAt: ${r.modifiedAt}, isDeleted: ${r.isDeleted}');
        
        // Always update if remote is newer OR if local is deleted but remote isn't
        if (r.modifiedAt.isAfter(localTime) || (localDeleted && !r.isDeleted)) {
          print('DEBUG: Updating: ${r.website}');
          await save(r);
        } else {
          print('DEBUG: Local is newer or same, skipping: ${r.website}');
        }
      }
    }
    print('DEBUG: mergeFromRemote complete');
  }

  // ── Export / Import ───────────────────────────────────────────

  Future<String> exportCsv() async {
    final all = await getAll();
    final sb  = StringBuffer();
    sb.writeln('Website,Email/Username,Password,URL,API Keys,Notes,Created,Modified');
    for (final c in all) {
      sb.writeln(
        '"${_csv(c.website)}","${_csv(c.email)}","${_csv(c.password)}",'
        '"${_csv(c.url)}","${_csv(c.apiKeys.join(' | '))}","${_csv(c.notes)}",'
        '"${c.createdAt}","${c.modifiedAt}"',
      );
    }
    return sb.toString();
  }

  Future<String> exportJson() async {
    final all = await getAllForSync();
    return jsonEncode(all.map((c) => c.toJson()).toList());
  }

  Future<int> importJson(String json) async {
    final list = jsonDecode(json) as List;
    int count = 0;
    for (final item in list) {
      await save(Credential.fromJson(item as Map<String, dynamic>));
      count++;
    }
    return count;
  }

  // ── Private ───────────────────────────────────────────────────

  Credential? _decode(String encrypted) {
    try {
      return Credential.fromJson(
          jsonDecode(_enc.decrypt(encrypted)) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  String _csv(String? v) => (v ?? '').replaceAll('"', '""');
}
