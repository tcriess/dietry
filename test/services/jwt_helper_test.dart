import 'package:flutter_test/flutter_test.dart';
import 'package:dietry/services/jwt_helper.dart';

void main() {
  group('JwtHelper', () {
    // Beispiel-JWT (generiert mit jwt.io, Secret: "test-secret")
    // Payload: {"sub": "123e4567-e89b-12d3-a456-426614174000", "email": "test@example.com", "name": "Test User", "exp": 9999999999}
    const validJwt = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjNlNDU2Ny1lODliLTEyZDMtYTQ1Ni00MjY2MTQxNzQwMDAiLCJlbWFpbCI6InRlc3RAZXhhbXBsZS5jb20iLCJuYW1lIjoiVGVzdCBVc2VyIiwiZXhwIjo5OTk5OTk5OTk5fQ.KxwZ5VrK-qEW0FxKkqxB7V5M1YvJPILlQ8Z4qK1xCXk';
    
    test('decodeToken sollte Payload extrahieren', () {
      final payload = JwtHelper.decodeToken(validJwt);
      
      expect(payload, isNotNull);
      expect(payload!['sub'], '123e4567-e89b-12d3-a456-426614174000');
      expect(payload['email'], 'test@example.com');
      expect(payload['name'], 'Test User');
    });

    test('decodeToken sollte null bei ungültigem Token zurückgeben', () {
      final payload = JwtHelper.decodeToken('invalid.token.here');
      
      expect(payload, isNull);
    });

    test('extractUserId sollte User-ID aus sub extrahieren', () {
      final userId = JwtHelper.extractUserId(validJwt);
      
      expect(userId, '123e4567-e89b-12d3-a456-426614174000');
    });

    test('extractUserId sollte null bei ungültigem Token zurückgeben', () {
      final userId = JwtHelper.extractUserId('invalid.token');
      
      expect(userId, isNull);
    });

    test('extractEmail sollte Email extrahieren', () {
      final email = JwtHelper.extractEmail(validJwt);
      
      expect(email, 'test@example.com');
    });

    test('extractName sollte Name extrahieren', () {
      final name = JwtHelper.extractName(validJwt);
      
      expect(name, 'Test User');
    });

    test('isTokenExpired sollte false für gültigen Token zurückgeben', () {
      final expired = JwtHelper.isTokenExpired(validJwt);
      
      // exp: 9999999999 = Jahr 2286
      expect(expired, false);
    });

    test('isTokenExpired sollte true für abgelaufenen Token zurückgeben', () {
      // JWT mit exp in der Vergangenheit (2000-01-01)
      const expiredJwt = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwiZXhwIjo5NDY2ODQ4MDB9.Z3BhMmE0MDU5NjI5NDYwNjI5MDYyOTA2MjkwNjI5MDY';
      
      final expired = JwtHelper.isTokenExpired(expiredJwt);
      
      expect(expired, true);
    });

    test('getExpirationDate sollte korrektes Datum zurückgeben', () {
      final expDate = JwtHelper.getExpirationDate(validJwt);
      
      expect(expDate, isNotNull);
      expect(expDate!.year, 2286); // 9999999999 = 16.09.2286
    });

    test('getTokenPayload sollte vollständigen Payload zurückgeben', () {
      final payload = JwtHelper.getTokenPayload(validJwt);
      
      expect(payload, isNotNull);
      expect(payload!['sub'], isNotNull);
      expect(payload['email'], isNotNull);
      expect(payload['name'], isNotNull);
      expect(payload['exp'], 9999999999);
    });
  });
}

