import 'package:uuid/uuid.dart';

class Credential {
  final String id;
  String website;
  String password;
  String? url;
  String? email;
  String? apiKey;
  final DateTime createdAt;
  DateTime modifiedAt;
  bool isDeleted;

  Credential({
    String? id,
    required this.website,
    required this.password,
    this.url,
    this.email,
    this.apiKey,
    DateTime? createdAt,
    DateTime? modifiedAt,
    this.isDeleted = false,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now().toUtc(),
        modifiedAt = modifiedAt ?? DateTime.now().toUtc();

  Map<String, dynamic> toJson() => {
        'id': id,
        'website': website,
        'password': password,
        'url': url,
        'email': email,
        'apiKey': apiKey,
        'createdAt': createdAt.toIso8601String(),
        'modifiedAt': modifiedAt.toIso8601String(),
        'isDeleted': isDeleted,
      };

  factory Credential.fromJson(Map<String, dynamic> json) => Credential(
        id: json['id'] as String,
        website: json['website'] as String,
        password: json['password'] as String,
        url: json['url'] as String?,
        email: json['email'] as String?,
        apiKey: json['apiKey'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
        modifiedAt: DateTime.parse(json['modifiedAt'] as String),
        isDeleted: json['isDeleted'] as bool? ?? false,
      );

  Credential copyWith({
    String? website,
    String? password,
    String? url,
    String? email,
    String? apiKey,
    DateTime? modifiedAt,
    bool? isDeleted,
  }) =>
      Credential(
        id: id,
        website: website ?? this.website,
        password: password ?? this.password,
        url: url ?? this.url,
        email: email ?? this.email,
        apiKey: apiKey ?? this.apiKey,
        createdAt: createdAt,
        modifiedAt: modifiedAt ?? DateTime.now().toUtc(),
        isDeleted: isDeleted ?? this.isDeleted,
      );
}
