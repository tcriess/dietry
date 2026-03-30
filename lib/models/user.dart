/// User Model für Dietry App
/// Repräsentiert einen authentifizierten Nutzer (OAuth)
class User {
  final String id;           // UUID von Neon Auth (JWT sub)
  final String email;        // Email vom OAuth-Provider
  final String? name;        // Display-Name (optional)
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastLoginAt;

  const User({
    required this.id,
    required this.email,
    this.name,
    required this.createdAt,
    required this.updatedAt,
    this.lastLoginAt,
  });

  /// Erstelle User aus JSON (Datenbank)
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      email: json['email'] as String,
      name: json['name'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      lastLoginAt: json['last_login_at'] != null
          ? DateTime.parse(json['last_login_at'] as String)
          : null,
    );
  }

  /// Konvertiere User zu JSON (für Datenbank)
  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        if (name != null) 'name': name,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        if (lastLoginAt != null)
          'last_login_at': lastLoginAt!.toIso8601String(),
      };

  /// Erstelle Kopie mit geänderten Werten
  User copyWith({
    String? id,
    String? email,
    String? name,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastLoginAt,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
    );
  }

  /// Getter: Initials für Avatar (z.B. "JD" für "John Doe")
  String get initials {
    if (name == null || name!.isEmpty) {
      return email[0].toUpperCase();
    }

    final parts = name!.trim().split(' ');
    if (parts.length == 1) {
      return parts[0][0].toUpperCase();
    }

    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  /// Getter: Display-Name oder Email als Fallback
  String get displayName => name ?? email;

  @override
  String toString() =>
      'User(id: $id, email: $email, name: $name, createdAt: $createdAt)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is User &&
        other.id == id &&
        other.email == email &&
        other.name == name;
  }

  @override
  int get hashCode => id.hashCode ^ email.hashCode ^ name.hashCode;
}

