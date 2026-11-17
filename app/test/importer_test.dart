import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisapilot/data/database.dart';
import 'package:paisapilot/import/importer.dart';
import 'package:paisapilot/import/statement_parser.dart';

import 'statement_fixture.dart';

void main() {
  late AppDatabase db;
  late Importer importer;
  late int canara;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    importer = Importer(db);
    canara = await db.into(db.accounts).insert(AccountsCompanion.insert(
        name: 'Canara savings', kind: 'bank', maskedNumber: const Value('XXX321')));
  });
  tearDown(() => db.close());

  Future<List<Txn>> txns() => db.select(db.transactions).get();

  test('new database is seeded with categories', () async {
    final names = [for (final c in await db.select(db.categories).get()) c.name];
    expect(names, containsAll(['Self transfer', 'Food and cafes', 'Shopping']));
    final self = await (db.select(db.categories)..where((c) => c.name.equals('Self transfer'))).getSingle();
    expect(self.countsAsSpend, isFalse);
  });

  test('statement import stores rows with payees and rule categories', () async {
    final res = await importer.importStatement(canara, statementFixture);
    expect((res.inserted, res.duplicates, res.result.mismatches), (4, 0, 0));

    final rows = await txns();
    final swiggy = rows.firstWhere((t) => t.upiRef == '222222222222');
    expect((swiggy.direction, swiggy.amount, swiggy.balanceAfter, swiggy.txnTime, swiggy.source),
        ('DR', 1700.0, -200.0, '12:00:00', 'statement'));
    expect(swiggy.categorySource, 'rule');
    final payee = await (db.select(db.payees)..where((p) => p.id.equals(swiggy.payeeId!))).getSingle();
    expect((payee.rawName, payee.vpa), ('SWIGGY', 'swiggy@yes'));

    final alice = rows.firstWhere((t) => t.upiRef == '111111111111');
    expect((alice.categoryId, alice.categorySource), (null, null)); // unsorted
  });

  test('a clean import reconciles with the app over the statement dates', () async {
    final res = await importer.importStatement(canara, statementFixture);
    expect((res.inApp, res.reconciles, res.firstDate, res.lastDate), (4, true, '2026-10-01', '2026-10-04'));
  });

  test('an extra row in the statement period is flagged', () async {
    // The Swiggy payment stored twice: once with its UPI ref, and a stray
    // balance-only copy that pairing missed.
    for (final ref in ['222222222222', null]) {
      await db.into(db.transactions).insert(TransactionsCompanion.insert(
          accountId: canara, txnDate: '2026-10-02', direction: 'DR', amount: 1700, source: 'sms',
          upiRef: Value(ref), rawText: Value('copy $ref')));
    }
    // Rows outside the statement's dates or on other accounts do not count.
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
        accountId: canara, txnDate: '2026-11-02', direction: 'DR', amount: 5, source: 'manual'));
    final res = await importer.importStatement(canara, statementFixture);
    expect((res.inApp, res.reconciles), (5, false));
  });

  test('a balance-only SMS row gets its payee from the statement', () async {
    // Canara's balance alert for the Swiggy payment: no payee, no ref.
    final sms = await importer.importSms('An amount of INR 1,700.00 has been DEBITED to your account XXX321 on '
        '02/10/2026. Total Avail.bal INR 200.00.Dial 1930 to report cyber fraud - Canara Bank');
    expect(sms!.inserted, isTrue);
    final res = await importer.importStatement(canara, statementFixture);
    expect((res.inserted, res.named, res.reconciles), (3, 1, true));
    final swiggy = (await txns()).firstWhere((t) => t.upiRef == '222222222222');
    final payee = await (db.select(db.payees)..where((p) => p.id.equals(swiggy.payeeId!))).getSingle();
    expect(payee.rawName, 'SWIGGY');
  });

  test('a charge whose SMS balance differs from the statement is not doubled', () async {
    // The SMS reports a different balance than the statement's running balance
    // for the same 5.00 credit on 04/10 (another posting landed in between).
    await importer.importSms('An amount of INR 5.00 has been CREDITED to your account XXX321 on 04/10/2026.'
        'Total Avail.bal INR 777.00.- Canara Bank');
    final first = await importer.importStatement(canara, statementFixture);
    expect((first.inserted, first.named, first.reconciles), (3, 1, true));
    final again = await importer.importStatement(canara, statementFixture);
    expect((again.inserted, again.reconciles), (0, true));
  });

  test('re-reading the charge SMS after the statement adds nothing', () async {
    const charge = 'An amount of INR 5.00 has been CREDITED to your account XXX321 on 04/10/2026.'
        'Total Avail.bal INR 777.00.- Canara Bank';
    await importer.importStatement(canara, statementFixture); // statement first this time
    expect((await importer.importSms(charge))!.inserted, isFalse);
    expect(await txns(), hasLength(4));
  });

  test('two identical charges on one day stay two rows', () async {
    final twice = statementFixture.replaceFirst(
        "Chq: \n${' ' * 25}Closing", // after the SBINT row, add the same credit again
        "Chq: \n${'04-10-2026  SBINT FOR THE PERIOD'.padRight(48)}${'5.00'.padLeft(14)}${'500.00'.padLeft(16)}\nChq: \n${' ' * 25}Closing");
    expect(parseStatement(twice).rows, hasLength(5));
    await importer.importSms('An amount of INR 5.00 has been CREDITED to your account XXX321 on 04/10/2026.'
        'Total Avail.bal INR 777.00.- Canara Bank');
    final res = await importer.importStatement(canara, twice);
    expect((res.inserted, res.named, res.inApp, res.reconciles), (4, 1, 5, true));
  });

  test('re-importing the same statement adds nothing', () async {
    await importer.importStatement(canara, statementFixture);
    final again = await importer.importStatement(canara, statementFixture);
    expect((again.inserted, again.duplicates), (0, 4));
    expect(await txns(), hasLength(4));
  });

  test('SMS for a payment already in the statement is not duplicated', () async {
    await importer.importStatement(canara, statementFixture);
    final sms = await importer.importSms('Dear Customer, Acct XXX321 credited with INR 500.00 on 01/10/26 '
        'from ALICE; UPI:111111111111; Bal INR 1,500.00-CanaraBank');
    expect(sms!.inserted, isFalse);
    expect(await txns(), hasLength(4));
  });

  test('SMS from an unknown card creates the account', () async {
    await importer.importSms('Rs. 300 spent on your credit card xx7890 at Some Shop on 14-Nov-26. - slice');
    final card = await (db.select(db.accounts)..where((a) => a.kind.equals('credit_card'))).getSingle();
    expect((card.name, card.maskedNumber), ('slice xx7890', 'xx7890'));
    final t = (await txns()).single;
    expect((t.accountId, t.txnDate, t.amount, t.source), (card.id, '2026-11-14', 300.0, 'sms'));
  });

  test('payee default category overrides the rules', () async {
    final cat = await (db.select(db.categories)..where((c) => c.name.equals('Shopping'))).getSingle();
    await db.into(db.payees).insert(PayeesCompanion.insert(
        rawName: 'ALICE', vpa: const Value('alice@okaxis'), defaultCategoryId: Value(cat.id)));
    await importer.importStatement(canara, statementFixture);
    final alice = (await txns()).firstWhere((t) => t.upiRef == '111111111111');
    expect((alice.categoryId, alice.categorySource), (cat.id, 'user'));
  });

  test('labelling a payee relabels its other rows but not individual picks', () async {
    await importer.importStatement(canara, statementFixture);
    final cats = {for (final c in await db.select(db.categories).get()) c.name: c.id};
    final first = (await txns()).firstWhere((t) => t.upiRef == '111111111111');
    Future<int> another(String ref) => db.into(db.transactions).insert(TransactionsCompanion.insert(
        accountId: canara, txnDate: '2026-10-09', direction: 'CR', amount: 10,
        payeeId: Value(first.payeeId), upiRef: Value(ref), source: 'manual'));
    final picked = await another('900000000001');
    final open = await another('900000000002');
    Future<Txn> row(int id) => (db.select(db.transactions)..where((t) => t.id.equals(id))).getSingle();

    await db.setCategory(await row(picked), cats['Shopping']);
    await db.setCategory(first, cats['Family'], forPayee: true);

    expect((await row(first.id)).categoryId, cats['Family']);
    expect((await row(open)).categoryId, cats['Family']);
    expect((await row(picked)).categoryId, cats['Shopping']);
    final payee = await (db.select(db.payees)..where((p) => p.id.equals(first.payeeId!))).getSingle();
    expect(payee.defaultCategoryId, cats['Family']);
  });

  group('Canara UPI and balance-only alerts for one payment', () {
    const upi = 'Rs.1,250.00 paid thru A/C XX4321 on 22-10-26 13:05:09 to TEA STALL, UPI Ref 512345678901. '
        'If not done, SMS BLOCKUPI to 9901771222.-Canara Bank';
    const bal = 'An amount of INR 1,250.00 has been DEBITED to your account XXX321 on 22/10/2026. '
        'Total Avail.bal INR 3,415.12.Dial 1930 to report cyber fraud - Canara Bank';

    Future<Txn> only() async => (await txns()).single;

    test('UPI alert first, then balance alert: one row with the balance', () async {
      expect((await importer.importSms(upi))!.inserted, isTrue);
      expect((await importer.importSms(bal))!.inserted, isFalse);
      final t = await only();
      expect((t.accountId, t.upiRef, t.balanceAfter, t.txnTime), (canara, '512345678901', 3415.12, '13:05:09'));
    });

    test('balance alert first, then UPI alert: the row is upgraded', () async {
      expect((await importer.importSms(bal))!.inserted, isTrue);
      expect((await importer.importSms(upi))!.inserted, isFalse);
      final t = await only();
      expect((t.upiRef, t.balanceAfter, t.txnTime, t.payeeId != null), ('512345678901', 3415.12, '13:05:09', true));
    });

    test('a repeated balance alert is not added twice', () async {
      await importer.importSms(bal);
      expect((await importer.importSms(bal))!.inserted, isFalse);
      expect(await txns(), hasLength(1));
    });

    test('two same-amount payments on one day stay two rows', () async {
      await importer.importSms(bal);
      final second = bal.replaceAll('3,415.12', '2,165.12');
      expect((await importer.importSms(second))!.inserted, isTrue);
      expect(await txns(), hasLength(2));
    });
  });

  test('accounts match on bank and trailing digits', () async {
    await importer.importSms('ICICI Bank Acct XX321 debited for Rs 10.00 on 10-Nov-26; SHOP credited. UPI:712345678901.');
    final icici = await (db.select(db.accounts)..where((a) => a.name.like('ICICI%'))).getSingle();
    expect(icici.id, isNot(canara)); // same digits, different bank
    await importer.importSms('You received Rs.150.0 from Some Friend with txn ABC123. Your FamPay a/c balance is Rs.900.00');
    await importer.importSms('You received Rs.20.0 from Another Friend with txn ABC124. Your FamPay a/c balance is Rs.920.00');
    final wallets = await (db.select(db.accounts)..where((a) => a.kind.equals('wallet'))).get();
    expect([for (final w in wallets) w.name], ['FamPay']);
  });

  test('slice card repayment lands on the card as a self transfer', () async {
    await importer.importSms('Rs. 300 spent on your credit card xx7890 at Some Shop on 14-Nov-26. - slice');
    await importer.importSms('Hi Someone ₹40 debited from your slice account xx1234 via UPI. Transaction date '
        '14-Nov-26 To Tea Stall RRN 812345678901 Regards Team slice');
    await importer.importSms('We received your repayment of ₹300 for the slice credit card.',
        receivedAt: DateTime(2026, 11, 20));
    final accounts = {for (final a in await db.select(db.accounts).get()) a.id: a};
    final repay = (await txns()).firstWhere((t) => t.direction == 'CR');
    expect((accounts[repay.accountId]!.name, repay.txnDate), ('slice xx7890', '2026-11-20'));
    expect(accounts.values.map((a) => (a.name, a.kind)),
        containsAll([('slice xx7890', 'credit_card'), ('slice bank xx1234', 'bank')]));
    final self = await (db.select(db.categories)..where((c) => c.name.equals('Self transfer'))).getSingle();
    expect((repay.categoryId, repay.categorySource), (self.id, 'rule'));
  });

  group('times', () {
    const balanceOnly = 'An amount of INR 1,250.00 has been DEBITED to your account XXX321 on 22/10/2026. '
        'Total Avail.bal INR 3,415.12.Dial 1930 to report cyber fraud - Canara Bank';

    test('an alert without a time takes the time it arrived', () async {
      await importer.importSms(balanceOnly, receivedAt: DateTime(2026, 10, 22, 19, 5, 42));
      expect((await txns()).single.txnTime, '19:05:42');
    });

    test('an arrival on another day is not used as the time', () async {
      await importer.importSms(balanceOnly, receivedAt: DateTime(2026, 10, 23, 0, 0, 5));
      expect((await txns()).single.txnTime, isNull);
    });

    test("the alert's own time wins over the arrival time", () async {
      await importer.importSms('Rs.40.00 paid thru A/C XX4321 on 22-10-26 13:05:09 to TEA STALL, UPI Ref 512345678901.'
          ' If not done, SMS BLOCKUPI to 9901771222.-Canara Bank', receivedAt: DateTime(2026, 10, 22, 13, 6));
      expect((await txns()).single.txnTime, '13:05:09');
    });

    test('re-reading an alert fills in a missing time without adding a row', () async {
      await importer.importSms(balanceOnly); // first read: no arrival time known
      expect((await txns()).single.txnTime, isNull);
      final again = await importer.importSms(balanceOnly, receivedAt: DateTime(2026, 10, 22, 19, 5, 42));
      expect(again!.inserted, isFalse);
      expect((await txns()).single.txnTime, '19:05:42');
    });

    test('an existing time is never overwritten', () async {
      await importer.importSms(balanceOnly, receivedAt: DateTime(2026, 10, 22, 19, 5, 42));
      await importer.importSms(balanceOnly, receivedAt: DateTime(2026, 10, 22, 20, 0));
      expect((await txns()).single.txnTime, '19:05:42');
    });
  });

  test('OTP messages are not imported', () async {
    expect(await importer.importSms('Hi, 1234 is the OTP for your transfer. - slice'), isNull);
    expect(await txns(), isEmpty);
  });
}
