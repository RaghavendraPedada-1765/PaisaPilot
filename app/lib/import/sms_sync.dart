import '../data/database.dart';
import 'importer.dart';
import 'outline.dart';
import 'sms_inbox.dart';

class SmsSyncResult {
  const SmsSyncResult({required this.scanned, required this.alerts, required this.added, this.unrecognised = const []});
  final int scanned; // inbox messages read
  final int alerts; // recognised as transactions
  final int added; // new rows (the rest were already recorded)
  /// Masked outlines of messages that mention money but matched no format.
  final List<String> unrecognised;
}

/// Pulls new bank / card alerts from the inbox into the database. Remembers
/// the newest message it has read, so each run only reads what came after.
class SmsSync {
  SmsSync(this.db, this.inbox) : _importer = Importer(db);
  final AppDatabase db;
  final SmsInbox inbox;
  final Importer _importer;
  Future<SmsSyncResult?>? _running;

  static const _lastReadKey = 'sms.last_read_millis';
  static const _parserKey = 'sms.parser_version';

  /// Bump when sms_parser.dart learns new formats: the next run re-reads the
  /// whole inbox once so older alerts in those formats are picked up.
  // 3: slice card repayment SMS; 4: fill in times; 5: ICICI salary credits; 6: Canara reversals, NEFT and
  // newer debit card wordings, India Post, FamPay credits and charges, slice card UPI spends; 7: those
  // card and India Post wordings with extra spaces
  static const parserVersion = 7;

  /// Returns null when SMS access is not granted. With [ask], the user is
  /// prompted first. Overlapping calls share one run.
  Future<SmsSyncResult?> run({bool ask = false}) =>
      _running ??= _run(ask).whenComplete(() => _running = null);

  Future<SmsSyncResult?> _run(bool ask) async {
    final allowed = ask ? await inbox.requestPermission() : await inbox.hasPermission();
    if (!allowed) return null;

    final parserChanged = await db.getSetting(_parserKey) != '$parserVersion';
    final last = parserChanged ? 0 : int.tryParse(await db.getSetting(_lastReadKey) ?? '') ?? 0;
    final messages = await inbox.read(since: DateTime.fromMillisecondsSinceEpoch(last));
    var alerts = 0, added = 0, newest = last;
    final unrecognised = <String>[];
    for (final m in messages) {
      final result = await _importer.importSms(m.body, receivedAt: m.date);
      if (result != null) {
        alerts++;
        if (result.inserted) added++;
      } else if (looksLikeMoney(m.body)) {
        unrecognised.add('${m.address}: ${outline(m.body)}');
      }
      if (m.date.millisecondsSinceEpoch > newest) newest = m.date.millisecondsSinceEpoch;
    }
    if (newest != last) await db.setSetting(_lastReadKey, '$newest');
    if (parserChanged) await db.setSetting(_parserKey, '$parserVersion');
    return SmsSyncResult(scanned: messages.length, alerts: alerts, added: added, unrecognised: unrecognised);
  }
}
