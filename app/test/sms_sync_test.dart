import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisapilot/data/database.dart';
import 'package:paisapilot/import/sms_inbox.dart';
import 'package:paisapilot/import/sms_sync.dart';

class FakeInbox implements SmsInbox {
  FakeInbox(this.messages, {this.granted = false, this.grantOnAsk = true});
  final List<InboxMessage> messages;
  bool granted;
  final bool grantOnAsk;
  final reads = <DateTime>[];

  @override
  Future<bool> hasPermission() async => granted;

  @override
  Future<bool> requestPermission() async => granted = granted || grantOnAsk;

  @override
  Future<List<InboxMessage>> read({required DateTime since}) async {
    reads.add(since);
    return [for (final m in messages) if (m.date.isAfter(since)) m];
  }
}

InboxMessage msg(int minute, String body) =>
    InboxMessage(address: 'VM-BANK', body: body, date: DateTime(2026, 11, 14, 10, minute));

const canaraDr = 'Dear Customer, Acct XXX321 Dr. INR 6,516.00 on 22/10/26 to MAKEMYTRIP I; '
    'UPI: 512300000002; Bal INR 149.12-CanaraBank';
const iciciDr = 'Rs 1999.00 successfully debited from ICICI Bank XX456 on 14-Nov-26 '
    'towards Google Play via UPI AutoPay mandate . RRN: 512300000004';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('without permission nothing is read unless the user is asked', () async {
    final inbox = FakeInbox([msg(1, canaraDr)], grantOnAsk: false);
    final sync = SmsSync(db, inbox);
    expect(await sync.run(), isNull);
    expect(await sync.run(ask: true), isNull);
    expect(inbox.reads, isEmpty);
  });

  test('asking grants access and imports only transaction alerts', () async {
    final inbox = FakeInbox([
      msg(1, canaraDr),
      msg(2, 'Hi, 1234 is the OTP for your transfer. - slice'),
      msg(3, 'See you at 7?'),
      msg(4, iciciDr),
    ]);
    final r = (await SmsSync(db, inbox).run(ask: true))!;
    expect((r.scanned, r.alerts, r.added), (4, 2, 2));
    expect(await db.select(db.transactions).get(), hasLength(2));
  });

  test('later runs only read messages after the last one seen', () async {
    final inbox = FakeInbox([msg(1, canaraDr)], granted: true);
    final sync = SmsSync(db, inbox);
    await sync.run();
    inbox.messages.add(msg(5, iciciDr));
    final r = (await sync.run())!;
    expect((r.scanned, r.added), (1, 1));
    expect(inbox.reads.last, DateTime(2026, 11, 14, 10, 1));

    final none = (await sync.run())!;
    expect((none.scanned, none.added), (0, 0));
  });

  test('a new parser version re-reads the whole inbox once', () async {
    final inbox = FakeInbox([msg(1, canaraDr)], granted: true);
    final sync = SmsSync(db, inbox);
    await sync.run();
    await db.setSetting('sms.parser_version', '${SmsSync.parserVersion - 1}'); // as an older build left it
    final r = (await sync.run())!;
    expect(inbox.reads.last, DateTime.fromMillisecondsSinceEpoch(0));
    expect((r.scanned, r.added), (1, 0));
    await sync.run();
    expect(inbox.reads.last, DateTime(2026, 11, 14, 10, 1));
  });

  test('an alert already recorded is counted but not added again', () async {
    final inbox = FakeInbox([msg(1, canaraDr), msg(2, canaraDr)], granted: true);
    final r = (await SmsSync(db, inbox).run())!;
    expect((r.alerts, r.added), (2, 1));
  });

  test('a version 1 database gains the settings table on upgrade', () async {
    final old = AppDatabase(NativeDatabase.memory(setup: (raw) => raw.execute('PRAGMA user_version = 1')));
    await old.setSetting('probe', 'ok');
    expect(await old.getSetting('probe'), 'ok');
    await old.close();
  });

  test('overlapping runs share one read', () async {
    final inbox = FakeInbox([msg(1, canaraDr)], granted: true);
    final sync = SmsSync(db, inbox);
    final results = await Future.wait([sync.run(), sync.run()]);
    expect(inbox.reads, hasLength(1));
    expect(identical(results[0], results[1]), isTrue);
  });
}
