# Archiv - Test-Services & Test-Screens

Dieses Verzeichnis enthält archivierte Test-Services und Test-Screens aus der Entwicklungsphase.

**Archiviert am**: 2026-03-25

## Inhalt

### Test-Services
- `database_connection_tester.dart` - Test der PostgreSQL-Verbindung
- `simple_db_tester.dart` - Einfache DB-Tests ohne Auth
- `jwt_debug_tester.dart` - JWT-Token-Debugging
- `user_creation_tester.dart` - User-Erstellungs-Tests
- `session_tester.dart` - Session-Management-Tests

### Test-Screens
- `nutrition_goals_test_screen.dart` - Test-UI für Nutrition Goals

### Alte Screen-Versionen
- `profile_screen_old.dart` - Alte Version des Profil-Screens (ohne Graphen, ersetzt durch aktuelle Version mit fl_chart)

## Warum archiviert?

Diese Test-Services und Test-Screens waren primär während der Entwicklung nützlich für:
- Debugging von Authentifizierung
- Testen der Datenbank-Verbindung
- Manuelle Funktions-Tests

Sie wurden aus der produktiven App entfernt, da:
- Die Features jetzt stabil funktionieren
- Unit-Tests die Test-Services ersetzen können
- Die UI übersichtlicher bleibt ohne Test-Buttons

## Reaktivierung

Falls ein Test-Service wieder benötigt wird:
1. Datei zurück nach `lib/services/` oder `lib/screens/` verschieben
2. Import in `main.dart` hinzufügen
3. Test-Button in AppBar hinzufügen (siehe Git-History)

---

**Hinweis**: Diese Files können bei Bedarf gelöscht werden, falls nicht mehr benötigt.

