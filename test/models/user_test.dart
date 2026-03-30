import 'package:flutter_test/flutter_test.dart';
import 'package:dietry/models/user.dart';

void main() {
  group('User Model', () {
    test('fromJson sollte valides Objekt erstellen', () {
      final json = {
        'id': '123e4567-e89b-12d3-a456-426614174000',
        'email': 'test@example.com',
        'name': 'Test User',
        'created_at': '2026-03-24T10:00:00Z',
        'updated_at': '2026-03-24T10:00:00Z',
        'last_login_at': '2026-03-24T11:00:00Z',
      };

      final user = User.fromJson(json);

      expect(user.id, '123e4567-e89b-12d3-a456-426614174000');
      expect(user.email, 'test@example.com');
      expect(user.name, 'Test User');
      expect(user.createdAt, DateTime.parse('2026-03-24T10:00:00Z'));
      expect(user.lastLoginAt, isNotNull);
    });

    test('fromJson sollte mit null name funktionieren', () {
      final json = {
        'id': '123e4567-e89b-12d3-a456-426614174000',
        'email': 'test@example.com',
        'created_at': '2026-03-24T10:00:00Z',
        'updated_at': '2026-03-24T10:00:00Z',
      };

      final user = User.fromJson(json);

      expect(user.name, isNull);
      expect(user.lastLoginAt, isNull);
    });

    test('toJson sollte korrektes JSON erstellen', () {
      final user = User(
        id: '123e4567-e89b-12d3-a456-426614174000',
        email: 'test@example.com',
        name: 'Test User',
        createdAt: DateTime.parse('2026-03-24T10:00:00Z'),
        updatedAt: DateTime.parse('2026-03-24T10:00:00Z'),
        lastLoginAt: DateTime.parse('2026-03-24T11:00:00Z'),
      );

      final json = user.toJson();

      expect(json['id'], '123e4567-e89b-12d3-a456-426614174000');
      expect(json['email'], 'test@example.com');
      expect(json['name'], 'Test User');
      expect(json['created_at'], '2026-03-24T10:00:00.000Z');
      expect(json.containsKey('last_login_at'), true);
    });

    test('toJson sollte null-Werte auslassen', () {
      final user = User(
        id: '123e4567-e89b-12d3-a456-426614174000',
        email: 'test@example.com',
        createdAt: DateTime.parse('2026-03-24T10:00:00Z'),
        updatedAt: DateTime.parse('2026-03-24T10:00:00Z'),
      );

      final json = user.toJson();

      expect(json.containsKey('name'), false);
      expect(json.containsKey('last_login_at'), false);
    });

    test('initials sollte korrekte Initialen erstellen', () {
      final user1 = User(
        id: 'id1',
        email: 'john.doe@example.com',
        name: 'John Doe',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final user2 = User(
        id: 'id2',
        email: 'alice@example.com',
        name: 'Alice',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final user3 = User(
        id: 'id3',
        email: 'test@example.com',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(user1.initials, 'JD');
      expect(user2.initials, 'A');
      expect(user3.initials, 'T'); // Erster Buchstabe der Email
    });

    test('displayName sollte name oder email zurückgeben', () {
      final userWithName = User(
        id: 'id1',
        email: 'test@example.com',
        name: 'Test User',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final userWithoutName = User(
        id: 'id2',
        email: 'test@example.com',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(userWithName.displayName, 'Test User');
      expect(userWithoutName.displayName, 'test@example.com');
    });

    test('copyWith sollte nur geänderte Felder überschreiben', () {
      final original = User(
        id: 'id1',
        email: 'old@example.com',
        name: 'Old Name',
        createdAt: DateTime(2026, 3, 20),
        updatedAt: DateTime(2026, 3, 20),
      );

      final updated = original.copyWith(
        email: 'new@example.com',
        name: 'New Name',
      );

      expect(updated.id, original.id);
      expect(updated.email, 'new@example.com');
      expect(updated.name, 'New Name');
      expect(updated.createdAt, original.createdAt);
    });

    test('Equality sollte korrekt funktionieren', () {
      final user1 = User(
        id: 'id1',
        email: 'test@example.com',
        name: 'Test',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final user2 = User(
        id: 'id1',
        email: 'test@example.com',
        name: 'Test',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final user3 = User(
        id: 'id2',
        email: 'other@example.com',
        name: 'Other',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(user1 == user2, true);
      expect(user1 == user3, false);
      expect(user1.hashCode == user2.hashCode, true);
    });

    test('toString sollte lesbare Ausgabe liefern', () {
      final user = User(
        id: 'id1',
        email: 'test@example.com',
        name: 'Test User',
        createdAt: DateTime(2026, 3, 24),
        updatedAt: DateTime(2026, 3, 24),
      );

      final string = user.toString();

      expect(string, contains('id1'));
      expect(string, contains('test@example.com'));
      expect(string, contains('Test User'));
    });
  });
}

