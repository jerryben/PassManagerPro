import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

/// Singleton service wrapping AES-256-CBC encryption.
/// Must be initialised with the master password before use.
class EncryptionService {
  static final EncryptionService _instance = EncryptionService._internal();
  factory EncryptionService() => _instance;
  EncryptionService._internal();

  late enc.Key _key;
  bool _initialized = false;

  bool get isInitialized => _initialized;

  // ── Public API ──────────────────────────────────────────────

  /// Derive key from [masterPassword] + [salt] and mark as ready.
  void initialize(String masterPassword, String salt) {
    _key = enc.Key(_deriveKey(masterPassword, salt));
    _initialized = true;
  }

  void reset() => _initialized = false;

  /// Encrypt [plaintext] → base64url string (IV prepended).
  String encrypt(String plaintext) {
    _assertReady();
    final iv = enc.IV.fromSecureRandom(16);
    final encrypted =
        enc.Encrypter(enc.AES(_key, mode: enc.AESMode.cbc)).encrypt(plaintext, iv: iv);
    return base64Url.encode([...iv.bytes, ...encrypted.bytes]);
  }

  /// Decrypt a base64url string produced by [encrypt].
  String decrypt(String ciphertext) {
    _assertReady();
    final raw = base64Url.decode(ciphertext);
    final iv = enc.IV(Uint8List.fromList(raw.sublist(0, 16)));
    final body = enc.Encrypted(Uint8List.fromList(raw.sublist(16)));
    return enc.Encrypter(enc.AES(_key, mode: enc.AESMode.cbc)).decrypt(body, iv: iv);
  }

  /// Encrypt a known sentinel string for password-verification.
  String createVerifier() => encrypt(_kVerifier);

  /// Try to decrypt [encryptedVerifier]; returns true on success.
  bool verifyPassword(String encryptedVerifier) {
    try {
      return decrypt(encryptedVerifier) == _kVerifier;
    } catch (_) {
      return false;
    }
  }

  // ── Internals ────────────────────────────────────────────────

  static const _kVerifier = 'PASSWORD_MANAGER_PRO_v1';

  void _assertReady() {
    if (!_initialized) throw StateError('EncryptionService not initialised');
  }

  /// PBKDF2-HMAC-SHA256, 10 000 iterations → 32-byte key.
  Uint8List _deriveKey(String password, String salt) {
    final pBytes = utf8.encode(password);
    final sBytes = utf8.encode(salt);
    final hmac = Hmac(sha256, pBytes);

    // PRF(password, salt || INT(1))
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
