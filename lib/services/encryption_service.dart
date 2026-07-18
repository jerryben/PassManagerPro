import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

/// Singleton service wrapping AES-256-CBC encryption.
///
/// TWO SEPARATE KEYS are maintained:
///
///  _key      – device-specific key (PBKDF2 with a random per-device salt).
///              Used for local SQLite row encryption. Never leaves the device.
///
///  _syncKey  – cross-device consistent key (PBKDF2 with a FIXED app-level
///              salt). Used exclusively for the GitHub Gist blob so that every
///              device sharing the same master password can decrypt it.
class EncryptionService {
  static final EncryptionService _instance = EncryptionService._internal();
  factory EncryptionService() => _instance;
  EncryptionService._internal();

  late enc.Key _key;
  late enc.Key _syncKey;
  bool _initialized     = false;
  bool _syncInitialized = false;

  bool get isInitialized => _initialized;

  // ── Fixed salt for cross-device Gist sync ─────────────────────
  // This constant is the same on every install of the app, so all
  // devices with the same master password produce the same _syncKey.
  static const _kSyncSalt = 'PMPro_GistSync_v1_CrossDevice_2024';

  // ── Public API ────────────────────────────────────────────────

  /// Initialise local key from [masterPassword] + per-device [salt].
  void initialize(String masterPassword, String salt) {
    _key         = enc.Key(_deriveKey(masterPassword, salt));
    _initialized = true;
  }

  /// Initialise cross-device sync key from [masterPassword] + fixed salt.
  /// Call this immediately after [initialize] on every app unlock.
  void initializeSyncKey(String masterPassword) {
    _syncKey          = enc.Key(_deriveKey(masterPassword, _kSyncSalt));
    _syncInitialized  = true;
  }

  void reset() {
    _initialized     = false;
    _syncInitialized = false;
  }

  // ── Local encryption (device-specific key) ────────────────────

  String encrypt(String plaintext) {
    _assertReady();
    return _aesEncrypt(_key, plaintext);
  }

  String decrypt(String ciphertext) {
    _assertReady();
    return _aesDecrypt(_key, ciphertext);
  }

  // ── Sync encryption (cross-device consistent key) ─────────────

  /// Encrypt [plaintext] for the Gist blob — same result on all devices
  /// that share the same master password.
  String encryptForSync(String plaintext) {
    _assertSyncReady();
    return _aesEncrypt(_syncKey, plaintext);
  }

  /// Decrypt a blob produced by [encryptForSync] on any device.
  String decryptForSync(String ciphertext) {
    _assertSyncReady();
    return _aesDecrypt(_syncKey, ciphertext);
  }

  // ── Password verification helpers ─────────────────────────────

  String createVerifier()                     => encrypt(_kVerifier);
  bool   verifyPassword(String encVerifier) {
    try { return decrypt(encVerifier) == _kVerifier; } catch (_) { return false; }
  }

  // ── Private helpers ───────────────────────────────────────────

  static const _kVerifier = 'PASSWORD_MANAGER_PRO_v1';

  void _assertReady()     {
    if (!_initialized)     throw StateError('EncryptionService not initialised');
  }
  void _assertSyncReady() {
    if (!_syncInitialized) throw StateError('Sync key not initialised — call initializeSyncKey() after unlock');
  }

  String _aesEncrypt(enc.Key key, String plaintext) {
    final iv        = enc.IV.fromSecureRandom(16);
    final encrypted = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc))
        .encrypt(plaintext, iv: iv);
    return base64Url.encode([...iv.bytes, ...encrypted.bytes]);
  }

  String _aesDecrypt(enc.Key key, String ciphertext) {
    final raw  = base64Url.decode(ciphertext);
    final iv   = enc.IV(Uint8List.fromList(raw.sublist(0, 16)));
    final body = enc.Encrypted(Uint8List.fromList(raw.sublist(16)));
    return enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc))
        .decrypt(body, iv: iv);
  }

  /// PBKDF2-HMAC-SHA256, 10 000 iterations → 32-byte key.
  Uint8List _deriveKey(String password, String salt) {
    final pBytes = utf8.encode(password);
    final sBytes = utf8.encode(salt);
    final hmac   = Hmac(sha256, pBytes);

    var u = hmac.convert([...sBytes, 0, 0, 0, 1]).bytes;
    final result = List<int>.from(u);

    for (var i = 1; i < 10000; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < result.length; j++) {
        result[j] ^= u[j];
      }
    }
    return Uint8List.fromList(result.sublist(0, 32));
  }
}
