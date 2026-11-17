import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisapilot/data/database.dart';
import 'package:paisapilot/import/importer.dart';
import 'package:paisapilot/main.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(
      DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true)));

  // Widget tests run on fake time, but drift completes queries on real async.
  // Give it real time, then rebuild; repeat so dependent streams can land.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
    }
  }

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(PaisaPilotApp(db: db));
    await settle(tester);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  }

  testWidgets('empty database shows the get-started prompt', (tester) async {
    await pumpApp(tester);
    expect(find.text('No transactions yet'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('home shows the month, totals and categories', (tester) async {
    await tester.runAsync(() async {
      final importer = Importer(db);
      await importer.importSms('Dear Customer, Acct XXX321 Dr. INR 6,516.00 on 22/10/26 to MAKEMYTRIP I; '
          'UPI: 512300000002; Bal INR 149.12-CanaraBank');
      await importer.importSms('Dear Customer, Acct XXX321 credited with INR 6,600.00 on 22/10/26 '
          'from ANITA KUMAR; UPI:512300000001; Bal INR 6,665.12-CanaraBank');
    });
    await pumpApp(tester);

    expect(find.text('October 2026'), findsOneWidget);
    expect(find.text('₹6,516'), findsWidgets); // spent, category row
    expect(find.text('₹6,600'), findsOneWidget); // received
    expect(find.text('Trip bookings'), findsOneWidget);

    await tester.tap(find.text('See all'));
    await settle(tester);
    expect(find.text('ANITA KUMAR'), findsWidgets);
    await finish(tester);
  });
}
