import 'dart:async';
import 'dart:convert';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

class EmailMessage {
  const EmailMessage({required this.id, required this.from, required this.subject, required this.text, required this.date});
  final String id;
  final String from;
  final String subject;
  final String text; // body as plain text on one line
  final DateTime date;
}

/// A mailbox the app can search. Tests use a fake.
abstract interface class EmailSource {
  /// Access token without showing UI, or null when the user must grant
  /// access again (Google ends test-mode grants after 7 days).
  Future<String?> silentToken();

  /// Shows Google's account picker and consent screen.
  Future<String?> interactiveToken();

  Future<void> disconnect();

  /// Messages matching a Gmail [query], newest first.
  Future<List<EmailMessage>> search(String token, String query);
}

/// Reads Gmail directly from the phone with read-only access. No server sits
/// in between: requests go from the app to Google and nowhere else.
class GmailSource implements EmailSource {
  GmailSource({http.Client? client, this.retryDelay = const Duration(seconds: 1)}) : _http = client ?? http.Client();
  final http.Client _http;

  /// Wait before the first retry; doubled for the next.
  final Duration retryDelay;

  // OAuth "Web application" client from the PaisaPilot Google Cloud project.
  // Android's sign-in needs it; it is an identifier, not a secret.
  static const _serverClientId = '398535140839-r7av9gqrgjo06ukam4bvtf79lmle936c.apps.googleusercontent.com';
  static const _scopes = ['https://www.googleapis.com/auth/gmail.readonly'];
  static const _api = 'https://gmail.googleapis.com/gmail/v1/users/me';

  final _signIn = GoogleSignIn.instance;
  Future<void>? _initialized;

  Future<GoogleSignInAuthorizationClient> _client() async {
    await (_initialized ??= _signIn.initialize(serverClientId: _serverClientId));
    return _signIn.authorizationClient;
  }

  @override
  Future<String?> silentToken() async =>
      (await (await _client()).authorizationForScopes(_scopes))?.accessToken;

  @override
  Future<String?> interactiveToken() async {
    try {
      return (await (await _client()).authorizeScopes(_scopes)).accessToken;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    await _client();
    await _signIn.disconnect();
  }

  @override
  Future<List<EmailMessage>> search(String token, String query) async {
    final headers = {'Authorization': 'Bearer $token'};
    final ids = <String>[];
    String? page;
    do {
      final uri = Uri.parse('$_api/messages').replace(queryParameters: {
        'q': query,
        'maxResults': '100',
        'pageToken': ?page,
      });
      final body = await _get(uri, headers);
      ids.addAll([for (final m in (body['messages'] as List? ?? const [])) (m as Map)['id'] as String]);
      page = body['nextPageToken'] as String?;
    } while (page != null);

    return [
      for (final id in ids) _message(await _get(Uri.parse('$_api/messages/$id?format=full'), headers)),
    ];
  }

  /// A full re-read makes one request per email, so a single passing error
  /// (Google answers 500 or 429 now and then, or a request stalls) used to
  /// fail the whole sync. Those are retried twice; other errors are not.
  Future<Map<String, Object?>> _get(Uri uri, Map<String, String> headers) async {
    for (var attempt = 0;; attempt++) {
      http.Response? res;
      try {
        res = await _http.get(uri, headers: headers).timeout(const Duration(seconds: 20));
      } on TimeoutException {
        if (attempt == 2) rethrow;
      }
      if (res != null) {
        if (res.statusCode == 200) return jsonDecode(res.body) as Map<String, Object?>;
        final passing = res.statusCode == 429 || res.statusCode >= 500;
        if (!passing || attempt == 2) throw GmailException(res.statusCode, res.body);
      }
      await Future<void>.delayed(retryDelay * (1 << attempt));
    }
  }

  EmailMessage _message(Map<String, Object?> m) {
    final payload = m['payload'] as Map<String, Object?>;
    String header(String name) {
      for (final h in (payload['headers'] as List? ?? const [])) {
        final map = h as Map;
        if ((map['name'] as String).toLowerCase() == name) return map['value'] as String;
      }
      return '';
    }

    return EmailMessage(
      id: m['id'] as String,
      from: header('from'),
      subject: header('subject'),
      text: emailText(payload),
      date: DateTime.fromMillisecondsSinceEpoch(int.parse(m['internalDate'] as String)),
    );
  }
}

class GmailException implements Exception {
  GmailException(this.status, this.body);
  final int status;
  final String body;
  @override
  String toString() => 'Gmail API $status';
}

/// Plain text of a Gmail message payload: the text/plain part if there is
/// one, otherwise the HTML part with tags removed. Whitespace is collapsed so
/// the SMS-style patterns can match across the email's line breaks.
String emailText(Map<String, Object?> payload) {
  String? plain, html;
  void walk(Map<String, Object?> part) {
    final mime = part['mimeType'] as String? ?? '';
    final data = (part['body'] as Map?)?['data'] as String?;
    if (data != null) {
      final text = utf8.decode(base64Url.decode(base64Url.normalize(data)), allowMalformed: true);
      if (mime == 'text/plain') plain ??= text;
      if (mime == 'text/html') html ??= text;
    }
    for (final p in (part['parts'] as List? ?? const [])) {
      walk(p as Map<String, Object?>);
    }
  }

  walk(payload);
  final text = plain ?? htmlToText(html ?? '');
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String htmlToText(String html) => html
    .replaceAll(RegExp(r'<(style|script)[^>]*>.*?</\1>', caseSensitive: false, dotAll: true), ' ')
    .replaceAll(RegExp(r'<br\s*/?>|</(p|div|tr|td|li|h\d)>', caseSensitive: false), ' ')
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&#8377;', '₹')
    .replaceAll('&#x20B9;', '₹')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'");
