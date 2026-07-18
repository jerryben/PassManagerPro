import 'package:uuid/uuid.dart';

/// Sentinel used in [copyWith] to distinguish "leave unchanged" from explicit null.
class _Unset { const _Unset(); }
const _unset = _Unset();

class Credential {
  final String id;
  String  website;
  String? password;       // optional – SSO / social-login entries may have none
  String? url;
  String? email;
  List<String> apiKeys;   // replaces single apiKey; backward-compat in fromJson
  String? notes;          // single-line note
  final DateTime createdAt;
  DateTime modifiedAt;
  bool isDeleted;

  Credential({
    String? id,
    required this.website,
    this.password,
    this.url,
    this.email,
    List<String>? apiKeys,
    this.notes,
    DateTime? createdAt,
    DateTime? modifiedAt,
    this.isDeleted = false,
  })  : id        = id ?? const Uuid().v4(),
        apiKeys   = apiKeys ?? [],
        createdAt = createdAt ?? DateTime.now().toUtc(),
        modifiedAt = modifiedAt ?? DateTime.now().toUtc();

  // ── Serialisation ────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'id':         id,
        'website':    website,
        'password':   password,
        'url':        url,
        'email':      email,
        'apiKeys':    apiKeys,
        'notes':      notes,
        'createdAt':  createdAt.toIso8601String(),
        'modifiedAt': modifiedAt.toIso8601String(),
        'isDeleted':  isDeleted,
      };

  factory Credential.fromJson(Map<String, dynamic> json) {
    // ── Backward-compat: old records used a single "apiKey" string ──
    List<String> keys = [];
    if (json['apiKeys'] != null) {
      keys = List<String>.from(json['apiKeys'] as List);
    } else if (json['apiKey'] != null && (json['apiKey'] as String).isNotEmpty) {
      keys = [json['apiKey'] as String];
    }

    return Credential(
      id:         json['id']       as String,
      website:    json['website']  as String,
      password:   json['password'] as String?,
      url:        json['url']      as String?,
      email:      json['email']    as String?,
      apiKeys:    keys,
      notes:      json['notes']    as String?,
      createdAt:  DateTime.parse(json['createdAt']  as String),
      modifiedAt: DateTime.parse(json['modifiedAt'] as String),
      isDeleted:  json['isDeleted'] as bool? ?? false,
    );
  }

  // ── copyWith ─────────────────────────────────────────────────
  // Uses _unset sentinel so callers can explicitly pass null for nullable fields.

  Credential copyWith({
    String?      website,
    Object?      password  = _unset,
    Object?      url       = _unset,
    Object?      email     = _unset,
    List<String>? apiKeys,
    Object?      notes     = _unset,
    DateTime?    modifiedAt,
    bool?        isDeleted,
  }) =>
      Credential(
        id:         id,
        website:    website    ?? this.website,
        password:   password  == _unset ? this.password  : password  as String?,
        url:        url        == _unset ? this.url       : url        as String?,
        email:      email      == _unset ? this.email     : email      as String?,
        apiKeys:    apiKeys    ?? List<String>.from(this.apiKeys),
        notes:      notes      == _unset ? this.notes     : notes      as String?,
        createdAt:  createdAt,
        modifiedAt: modifiedAt ?? DateTime.now().toUtc(),
        isDeleted:  isDeleted  ?? this.isDeleted,
      );
}
