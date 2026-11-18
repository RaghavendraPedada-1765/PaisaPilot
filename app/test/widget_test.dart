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

  testWidgets('the + dialog closes cleanly with Cancel and with Add', (tester) async {
    await pumpApp(tester);
    for (final button in ['Cancel', 'Add']) {
      await tester.tap(find.byTooltip('Paste an SMS alert'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'not a bank alert');
      await tester.tap(find.text(button));
      // Step through the closing animation, where a disposed controller crashed.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await settle(tester);
      expect(tester.takeException(), isNull, reason: button);
      expect(find.byType(AlertDialog), findsNothing);
    }
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

    // Recent activity sits below the cards on the test's small screen, where
    // scrolling leaves it under the app bar; press the button directly.
    await tester.scrollUntilVisible(find.text('See all'), 200);
    tester.widget<TextButton>(find.widgetWithText(TextButton, 'See all')).onPressed!();
    await settle(tester);
    expect(find.widgetWithText(AppBar, 'Activity'), findsOneWidget);
    expect(find.text('ANITA KUMAR'), findsWidgets);
    await finish(tester);
  });
}
