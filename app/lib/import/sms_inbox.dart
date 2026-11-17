import 'package:flutter/services.dart';

class InboxMessage {
  const InboxMessage({required this.address, required this.body, required this.date});
  final String address; // sender, e.g. VM-CNRBNK
  final String body;
  final DateTime date;
}

/// The phone's SMS inbox. Tests use a fake.
abstract interface class SmsInbox {
  Future<bool> hasPermission();

  /// Shows the system prompt if needed; true when access is granted.
  Future<bool> requestPermission();

  /// Messages received after [since], oldest first.
  Future<List<InboxMessage>> read({required DateTime since});
}

/// Talks to MainActivity.kt over the "paisapilot/sms" channel.
class AndroidSmsInbox implements SmsInbox {
  static const _channel = MethodChannel('paisapilot/sms');

  @override
  Future<bool> hasPermission() async => await _channel.invokeMethod<bool>('hasPermission') ?? false;

  @override
  Future<bool> requestPermission() async => await _channel.invokeMethod<bool>('requestPermission') ?? false;

  @override
  Future<List<InboxMessage>> read({required DateTime since}) async {
    final rows = await _channel.invokeListMethod<Map<Object?, Object?>>(
        'readInbox', {'sinceMillis': since.millisecondsSinceEpoch});
    return [
      for (final r in rows ?? const <Map<Object?, Object?>>[])
        InboxMessage(
          address: r['address'] as String? ?? '',
          body: r['body'] as String? ?? '',
          date: DateTime.fromMillisecondsSinceEpoch(r['date'] as int),
        ),
    ];
  }
}
