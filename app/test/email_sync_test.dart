import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paisapilot/data/database.dart';
import 'package:paisapilot/import/email_sync.dart';
import 'package:paisapilot/import/gmail_source.dart';
import 'package:paisapilot/import/importer.dart';

class FakeMailbox implements EmailSource {
  FakeMailbox(this.emails);
  final List<EmailMessage> emails;
  bool granted = false; // what a silent request returns
  bool userAccepts = true; // what the consent screen returns
  final queries = <String>[];

  @override
  Future<String?> silentToken() async => granted ? 'token' : null;

  @override
  Future<String?> interactiveToken() async => userAccepts ? (granted = true, 'token').$2 : null;

  @override
  Future<void> disconnect() async => granted = false;

  @override
  Future<List<EmailMessage>> search(String token, String query) async {
    queries.add(query);
    final after = RegExp(r'after:(\d+)').firstMatch(query);
    final since = after == null ? 0 : int.parse(after.group(1)!) * 1000;
    return [for (final e in emails) if (e.date.millisecondsSinceEpoch >= since) e];
  }
}

EmailMessage mail(int day, String text) => EmailMessage(
    id: 'm$day', from: 'slice <alerts@example.com>', subject: 'Transaction alert', text: text,
    date: DateTime(2026, 11, day, 10));

const spend = 'Hi, Rs. 300 spent on your credit card xx7890 at Some Shop on 14-Nov-26. Not you? Call us - slice';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('nothing happens until Gmail is connected', () async {
    final box = FakeMailbox([mail(14, spend)]);
    expect(await EmailSync(db, box).run(), EmailSyncStatus.notConnected);
    expect(box.queries, isEmpty);
  });

  test('connecting imports alerts, later runs only ask for newer mail', () async {
    final box = FakeMailbox([mail(14, spend), mail(15, 'Your statement is ready - slice')]);
    final sync = EmailSync(db, box);
    final first = await sync.run(interactive: true) as EmailSyncResult;
    expect((first.scanned, first.alerts, first.added), (2, 1, 1));
    expect(box.queries.single, EmailSync.senders);
    expect(await sync.isConnected(), isTrue);

    await sync.run();
    expect(box.queries.last, '${EmailSync.senders} after:${DateTime(2026, 11, 15, 10).millisecondsSinceEpoch ~/ 1000}');
  });

  test('declining the consent screen leaves Gmail unconnected', () async {
    final box = FakeMailbox([mail(14, spend)])..userAccepts = false;
    final sync = EmailSync(db, box);
    expect(await sync.run(interactive: true), EmailSyncStatus.notConnected);
    expect(await sync.isConnected(), isFalse);
  });

  test('expired access is reported, not silently treated as disconnected', () async {
    final box = FakeMailbox([mail(14, spend)]);
    final sync = EmailSync(db, box);
    await sync.run(interactive: true);
    box.granted = false; // Google ended the 7-day test grant
    expect(await sync.run(), EmailSyncStatus.needsReconnect);
  });

  test('the same slice spend by SMS and by email is stored once', () async {
    await Importer(db).importSms('Rs. 300 spent on your credit card xx7890 at Some Shop on 14-Nov-26. '
        'Not you? Call 080-4832-9999 - slice');
    final r = await EmailSync(db, FakeMailbox([mail(14, spend)])).run(interactive: true) as EmailSyncResult;
    expect((r.alerts, r.added), (1, 0));
    expect(await db.select(db.transactions).get(), hasLength(1));
  });

  group('email text', () {
    String b64(String s) => base64Url.encode(utf8.encode(s));

    test('prefers the plain-text part and joins lines', () {
      final payload = {
        'mimeType': 'multipart/alternative',
        'parts': [
          {'mimeType': 'text/plain', 'body': {'data': b64('Rs. 300 spent\non your card')}},
          {'mimeType': 'text/html', 'body': {'data': b64('<p>ignored</p>')}},
        ],
      };
      expect(emailText(payload), 'Rs. 300 spent on your card');
    });

    test('falls back to HTML without tags, styles or entities', () {
      final payload = {
        'mimeType': 'text/html',
        'body': {'data': b64('<style>p{color:red}</style><p>&#8377;300&nbsp;spent</p><br>at <b>Shop &amp; Co</b>')},
      };
      expect(emailText(payload), '₹300 spent at Shop & Co');
    });
  });
}
