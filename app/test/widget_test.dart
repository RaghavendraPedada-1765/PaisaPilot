import 'package:drift/drift.dart' show DatabaseConnection, Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisapilot/data/database.dart';
import 'package:paisapilot/import/importer.dart';
import 'package:paisapilot/main.dart';
import 'package:paisapilot/ui/activity_screen.dart';
import 'package:paisapilot/ui/format.dart';
import 'package:paisapilot/ui/home_screen.dart';
import 'package:paisapilot/ui/txn_tile.dart';

// All names and amounts here are made up.
final today = DateTime(2026, 11, 18, 10);

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
    await tester.pumpWidget(PaisaPilotApp(db: db, now: () => today));
    await settle(tester);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  }

  /// Fictional rows: (payee, date, direction, amount, category name or null).
  Future<void> seed(WidgetTester tester, List<(String, String, String, double, String?)> rows) =>
      tester.runAsync(() async {
        final account = await db.into(db.accounts).insert(AccountsCompanion.insert(name: 'Canara XX4321', kind: 'bank'));
        final cats = {for (final c in await db.select(db.categories).get()) c.name: c.id};
        final payees = <String, int>{};
        for (final (payee, date, dir, amount, category) in rows) {
          final payeeId = payees[payee] ??= await db.into(db.payees).insert(PayeesCompanion.insert(rawName: payee));
          await db.into(db.transactions).insert(TransactionsCompanion.insert(
              accountId: account, txnDate: date, direction: dir, amount: amount, source: 'manual',
              payeeId: Value(payeeId), categoryId: Value(category == null ? null : cats[category]!)));
        }
      });

  // Home's own list (Activity, its chip row and sheets scroll too).
  final homeList = find.descendant(of: find.byType(HomeScreen), matching: find.byType(Scrollable)).first;

  /// A narrow phone (320 × 640 dp).
  void narrowPhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(960, 1920);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  final november = [
    ('SWIGGY', '2026-11-17', 'DR', 420.0, 'Food and cafes'),
    ('CAFE NOVA', '2026-11-12', 'DR', 180.5, 'Food and cafes'),
    ('ZUDIO', '2026-11-10', 'DR', 1999.0, 'Shopping'),
    ('RAVI KUMAR', '2026-11-03', 'DR', 750.0, null),
    ('ANITA KUMAR', '2026-11-01', 'CR', 5000.0, null),
    ('SWIGGY', '2026-10-28', 'DR', 300.0, 'Food and cafes'),
    ('TEA STALL', '2026-10-05', 'DR', 60.0, null),
  ];

  testWidgets('empty database shows the get-started prompt', (tester) async {
    await pumpApp(tester);
    expect(find.text('No transactions yet'), findsOneWidget);
    expect(find.text('Paste an alert instead').evaluate().isNotEmpty || find.text('Add from SMS').evaluate().isNotEmpty,
        isTrue);
    expect(find.text('Import a statement PDF'), findsOneWidget);
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
    expect(find.text('Full month'), findsOneWidget);
    expect(find.text('₹6,516'), findsWidgets); // hero, legend
    expect(find.text('+₹6,600'), findsOneWidget); // received
    expect(find.text('+₹84'), findsOneWidget); // net
    expect(find.text('No transactions to compare vs September (full month)'), findsOneWidget);
    expect(find.text('Trip bookings'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('See all'), 200);
    await tester.tap(find.text('See all'), warnIfMissed: false);
    tester.widget<TextButton>(find.widgetWithText(TextButton, 'See all')).onPressed!();
    await settle(tester);
    expect(find.widgetWithText(AppBar, 'Activity'), findsOneWidget);
    expect(find.text('ANITA KUMAR'), findsWidgets);
    expect(find.text('All transactions'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('the running month compares with the same days of last month', (tester) async {
    await seed(tester, november);
    await pumpApp(tester);
    expect(find.text('November 2026'), findsOneWidget);
    expect(find.text('In progress'), findsOneWidget);
    // Nov so far 3,349.50 against 1-18 Oct, which has only the 60 (the 300 is on 28 Oct).
    expect(find.text('₹3,349.50'), findsWidgets);
    expect(find.textContaining('₹3,289.50 more'), findsOneWidget);
    expect(find.textContaining('vs 1–18 Oct (same days)'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('tapping a category opens Activity on that category and month; sums agree', (tester) async {
    await seed(tester, november);
    await pumpApp(tester);

    final food = (await tester.runAsync(() => (db.select(db.categories)..where((c) => c.name.equals('Food and cafes')))
        .getSingle()))!;
    final legend = find.byKey(ValueKey('legend:${food.id}'));
    await tester.dragUntilVisible(legend.hitTestable(), homeList, const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(legend);
    await settle(tester);

    expect(find.widgetWithText(AppBar, 'Activity'), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'Food and cafes'), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'November 2026'), findsOneWidget);
    expect(find.text('Filtered: Money out · Food and cafes · November 2026'), findsOneWidget);
    expect(find.text('2 transactions'), findsOneWidget);
    // The slice is 420 + 180.50; October's Swiggy payment is not included.
    final slice = (await tester.runAsync(() => db.spendByCategory('2026-11').get()))!
        .firstWhere((s) => s.category == 'Food and cafes');
    expect(slice.total, 600.5);
    expect(find.text(signedInr(slice.total!, credit: false)), findsOneWidget);
    expect(find.text('SWIGGY'), findsOneWidget);
    expect(find.text('CAFE NOVA'), findsOneWidget);

    // Clearing brings everything back.
    await tester.tap(find.text('Clear'));
    await settle(tester);
    expect(find.text('All transactions'), findsOneWidget);
    expect(find.text('7 transactions'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('tapping the donut ring itself opens the largest slice', (tester) async {
    await seed(tester, november);
    await pumpApp(tester);
    final donut = find.byKey(const ValueKey('donut'));
    await tester.scrollUntilVisible(donut, 150, scrollable: homeList);
    await tester.ensureVisible(donut);
    await tester.pumpAndSettle();
    // Just clockwise of 12 o'clock on the ring: the first (largest) slice.
    final box = tester.getRect(donut);
    await tester.tapAt(Offset(box.center.dx + 8, box.top + 14));
    await settle(tester);
    expect(find.widgetWithText(InputChip, 'Shopping'), findsOneWidget);
    expect(find.text('ZUDIO'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('rapid month changes land on the right month without stale figures', (tester) async {
    await seed(tester, november);
    await pumpApp(tester);
    final previous = find.byTooltip('Previous month');
    final next = find.byTooltip('Next month');
    for (final b in [previous, previous, next, previous]) { // Oct, Sep, Oct, Sep
      await tester.tap(b);
      await tester.pump(const Duration(milliseconds: 30));
    }
    // Mid-flight: September is labelled, and October's figures are not shown as September's.
    expect(find.text('September 2026'), findsOneWidget);
    expect(find.text('₹360'), findsNothing);
    await settle(tester);
    expect(find.text('September 2026'), findsOneWidget);
    expect(find.text('No transactions'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(next);
    await settle(tester);
    expect(find.text('October 2026'), findsOneWidget);
    expect(find.text('₹360'), findsWidgets);
    await finish(tester);
  });

  testWidgets('a month with only income shows a real ₹0, not an empty month', (tester) async {
    await seed(tester, [('ANITA KUMAR', '2026-11-02', 'CR', 900.0, null)]);
    await pumpApp(tester);
    expect(find.text('₹0'), findsOneWidget);
    expect(find.text('No spending recorded this month'), findsOneWidget);
    expect(find.text('No transactions'), findsNothing);
    await finish(tester);
  });

  testWidgets('a search with no results says so and clears', (tester) async {
    await seed(tester, november);
    await pumpApp(tester);
    await tester.tap(find.text('Activity'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'zzz');
    await settle(tester);
    expect(find.text('No matching transactions'), findsOneWidget);
    await tester.tap(find.text('Clear filters'));
    await settle(tester);
    expect(find.text('7 transactions'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('a payee with many payments: review previews the count and labels them all', (tester) async {
    await seed(tester, [for (var i = 0; i < 120; i++) ('METRO CARD', '2026-11-${(i % 17 + 1).toString().padLeft(2, '0')}', 'DR', 25.0, null)]);
    await pumpApp(tester);
    expect(find.textContaining('₹3,000 awaiting a category'), findsOneWidget);
    await tester.tap(find.text('METRO CARD'));
    await settle(tester);
    await tester.tap(find.text('Local transport'));
    await settle(tester);
    expect(find.text('Label 120 unsorted payments as Local transport?'), findsOneWidget);
    await tester.tap(find.text('Apply'));
    await settle(tester);
    final left = await tester.runAsync(() => db.watchUnsortedPayees().first);
    expect(left, isEmpty);
    expect(find.textContaining('awaiting a category'), findsNothing);
    await finish(tester);
  });

  testWidgets('the detail sheet shows the payment and counts before a payee-wide change', (tester) async {
    await seed(tester, november);
    await pumpApp(tester);
    await tester.tap(find.text('Activity'));
    await settle(tester);
    await tester.tap(find.text('ZUDIO'));
    await settle(tester);
    expect(find.text('Paid to'), findsOneWidget);
    expect(find.text('−₹1,999'), findsWidgets);
    expect(find.text('Canara XX4321'), findsWidgets);
    await tester.drag(find.text('Paid to'), const Offset(0, -400));
    await settle(tester);
    expect(find.text('Affects 1 payment; ones you labelled one by one are kept'), findsOneWidget);
    // Off until switched on.
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isFalse);
    await finish(tester);
  });

  testWidgets('narrow phone with large text: no overflow on Home, Activity or the sheet', (tester) async {
    narrowPhone(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await seed(tester, november);
    await pumpApp(tester);
    // Scroll the whole of Home so every card lays out.
    await tester.drag(find.byType(ListView).first, const Offset(0, -3000));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.receipt_long_outlined));
    await settle(tester);
    final row = find.descendant(of: find.byType(ActivityScreen), matching: find.byType(TxnTile)).first;
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await settle(tester);
    await tester.drag(find.text('Paid to'), const Offset(0, -2000));
    await settle(tester);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('reduced motion: the sheet and the month change appear at once', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await seed(tester, november);
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pump(); // subscribes to October
    for (var i = 0; i < 2; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(); // no animation time: figures and charts are final at once
    }
    expect(find.text('₹360'), findsWidgets);
    // The money-out bar is already at full length (360 out, nothing in).
    final bars = tester.widgetList<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect([for (final b in bars) b.value], [1.0, 0.0]);
    await tester.tap(find.text('Activity'));
    await tester.pump();
    await settle(tester);
    await tester.tap(find.text('ZUDIO'));
    await tester.pump(); // one frame, no animation time
    expect(find.text('Paid to'), findsOneWidget);
    await finish(tester);
  });
}
