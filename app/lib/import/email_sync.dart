import '../data/database.dart';
import 'gmail_source.dart';
import 'importer.dart';

class EmailSyncResult {
  const EmailSyncResult({required this.scanned, required this.alerts, required this.added});
  final int scanned;
  final int alerts;
  final int added;

  @override
  String toString() => 'EmailSyncResult(scanned: $scanned, alerts: $alerts, added: $added)';
}

enum EmailSyncStatus { notConnected, needsReconnect }

/// Pulls card alerts from Gmail (slice sends some alerts only by email).
/// Remembers the newest email read, like SmsSync.
class EmailSync {
  EmailSync(this.db, this.source) : _importer = Importer(db);
  final AppDatabase db;
  final EmailSource source;
  final Importer _importer;
  Future<Object>? _running;

  static const _connectedKey = 'gmail.connected';
  static const _lastReadKey = 'gmail.last_read_millis';
  static const _parserKey = 'gmail.parser_version';

  /// Bump when the parser learns new email formats: the next run re-reads
  /// all matching mail once.
  static const parserVersion = 3; // 2: "slice bank account" debits; 3: fill in times

  /// Senders whose alerts are imported (Gmail query syntax).
  static const senders = 'from:slice.bank.in';

  Future<bool> isConnected() async => await db.getSetting(_connectedKey) == '1';

  /// Returns an [EmailSyncResult], or an [EmailSyncStatus] when nothing could
  /// be read. With [interactive], Google's consent screen may be shown.
  Future<Object> run({bool interactive = false}) =>
      _running ??= _run(interactive).whenComplete(() => _running = null);

  Future<Object> _run(bool interactive) async {
    if (!interactive && !await isConnected()) return EmailSyncStatus.notConnected;
    final token = await source.silentToken() ?? (interactive ? await source.interactiveToken() : null);
    if (token == null) {
      return await isConnected() ? EmailSyncStatus.needsReconnect : EmailSyncStatus.notConnected;
    }
    await db.setSetting(_connectedKey, '1');

    final parserChanged = await db.getSetting(_parserKey) != '$parserVersion';
    final last = parserChanged ? 0 : int.tryParse(await db.getSetting(_lastReadKey) ?? '') ?? 0;
    // Gmail's after: takes seconds; re-reading the boundary second is harmless.
    final query = last == 0 ? senders : '$senders after:${last ~/ 1000}';
    final emails = await source.search(token, query);
    emails.sort((a, b) => a.date.compareTo(b.date));
    var alerts = 0, added = 0, newest = last;
    for (final e in emails) {
      final result = await _importer.importSms(e.text, receivedAt: e.date);
      if (result != null) {
        alerts++;
        if (result.inserted) added++;
      }
      if (e.date.millisecondsSinceEpoch > newest) newest = e.date.millisecondsSinceEpoch;
    }
    if (newest != last) await db.setSetting(_lastReadKey, '$newest');
    if (parserChanged) await db.setSetting(_parserKey, '$parserVersion');
    return EmailSyncResult(scanned: emails.length, alerts: alerts, added: added);
  }

  Future<void> disconnect() async {
    await source.disconnect();
    await db.setSetting(_connectedKey, '0');
  }
}
