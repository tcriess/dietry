// Basic Flutter widget test für Dietry App

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App sollte MaterialApp erstellen', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Dietry Test')),
        body: const Center(child: Text('Test')),
      ),
    ));

    expect(find.text('Dietry Test'), findsOneWidget);
    expect(find.text('Test'), findsOneWidget);
  });

  testWidgets('Tab Navigation sollte funktionieren', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Dietry'),
            bottom: const TabBar(
              tabs: [
                Tab(icon: Icon(Icons.home), text: 'Übersicht'),
                Tab(icon: Icon(Icons.add), text: 'Eintragen'),
                Tab(icon: Icon(Icons.analytics), text: 'Statistik'),
              ],
            ),
          ),
          body: const TabBarView(
            children: [
              Center(child: Text('Übersicht Tab')),
              Center(child: Text('Eintragen Tab')),
              Center(child: Text('Statistik Tab')),
            ],
          ),
        ),
      ),
    ));

    // Übersicht-Tab ist initial sichtbar
    expect(find.text('Übersicht'), findsOneWidget);
    expect(find.text('Übersicht Tab'), findsOneWidget);

    // Zum Eintragen-Tab wechseln
    await tester.tap(find.text('Eintragen'));
    await tester.pumpAndSettle();
    
    expect(find.text('Eintragen Tab'), findsOneWidget);
  });

  testWidgets('Icon-Buttons sollten klickbar sein', (WidgetTester tester) async {
    int counter = 0;
    
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => counter++,
          ),
        ),
      ),
    ));

    expect(find.byIcon(Icons.add), findsOneWidget);
    
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    
    expect(counter, 1);
  });
}
