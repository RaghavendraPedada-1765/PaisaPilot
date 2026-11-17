import 'dart:io';

import 'package:flutter/material.dart';

import 'data/database.dart';
import 'import/email_sync.dart';
import 'import/gmail_source.dart';
import 'import/importer.dart';
import 'import/sms_inbox.dart';
import 'import/sms_sync.dart';
import 'ui/activity_screen.dart';
import 'ui/home_screen.dart';
import 'ui/sms_import_dialog.dart';
import 'ui/statement_import.dart';
import 'ui/theme.dart';

void main() {
  final android = Platform.isAndroid;
  runApp(PaisaPilotApp(
    db: AppDatabase(),
    inbox: android ? AndroidSmsInbox() : null,
    email: android ? GmailSource() : null,
  ));
}

class PaisaPilotApp extends StatelessWidget {
  const PaisaPilotApp({super.key, required this.db, this.inbox, this.email});
  final AppDatabase db;
  final SmsInbox? inbox; // null where there is no SMS inbox (desktop, tests)
  final EmailSource? email;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'PaisaPilot',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        builder: (context, child) => GlassBackground(child: child!),
        home: _Shell(db: db, inbox: inbox, email: email),
      );
}

class _Shell extends StatefulWidget {
  const _Shell({required this.db, this.inbox, this.email});
  final AppDatabase db;
  final SmsInbox? inbox;
  final EmailSource? email;

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  late final _importer = Importer(widget.db);
  late final _sync = widget.inbox == null ? null : SmsSync(widget.db, widget.inbox!);
  late final _email = widget.email == null ? null : EmailSync(widget.db, widget.email!);
  AppLifecycleListener? _lifecycle;
  var _gmailConnected = false;
  var _toldReconnect = false;
  var _tab = 0;

  @override
  void initState() {
    super.initState();
    // Quietly pick up new alerts on launch and whenever the app comes back.
    _readAll();
    _lifecycle = AppLifecycleListener(onResume: _readAll);
    _email?.isConnected().then((c) => mounted ? setState(() => _gmailConnected = c) : null);
  }

  void _readAll() {
    if (_sync != null) _readSms();
    if (_email != null) _readEmail();
  }

  void _toast(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  /// With [interactive], Google's consent screen may be shown and every
  /// outcome is reported; otherwise only new rows and expired access are.
  Future<void> _readEmail({bool interactive = false}) async {
    Object result;
    try {
      result = await _email!.run(interactive: interactive);
    } catch (e, st) {
      debugPrint('Gmail sync failed (interactive: $interactive): $e\n$st');
      if (mounted && interactive) _toast("Couldn't read Gmail: $e");
      return;
    }
    debugPrint('Gmail sync (interactive: $interactive): $result');
    if (!mounted) return;
    setState(() => _gmailConnected = result is EmailSyncResult || result == EmailSyncStatus.needsReconnect);
    switch (result) {
      case EmailSyncResult(:final added) when added > 0:
        _toast('Added $added transaction${added == 1 ? '' : 's'} from Gmail');
      case EmailSyncResult(:final scanned) when interactive:
        _toast(scanned == 0 ? 'No new slice emails' : 'No new transactions in $scanned slice emails');
      case EmailSyncStatus.needsReconnect when interactive || !_toldReconnect:
        _toldReconnect = true;
        _toast('Gmail access expired. Tap sync to reconnect.');
      case EmailSyncStatus.notConnected when interactive:
        _toast('Gmail was not connected');
    }
  }

  Future<void> _disconnectGmail() async {
    await _email!.disconnect();
    if (!mounted) return;
    setState(() => _gmailConnected = false);
    _toast('Gmail disconnected');
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  void _addSms() => showSmsImportDialog(context, _importer);

  /// With [ask], prompts for SMS access and reports the outcome.
  Future<void> _readSms({bool ask = false}) async {
    final result = await _sync!.run(ask: ask);
    if (!mounted) return;
    final String? message;
    if (result == null) {
      message = ask ? 'Allow SMS access in Settings › Apps › PaisaPilot › Permissions to read bank alerts' : null;
    } else if (result.added > 0) {
      message = 'Added ${result.added} transaction${result.added == 1 ? '' : 's'} from SMS';
    } else {
      message = ask ? 'No new transactions in SMS' : null;
    }
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_tab == 0 ? 'PaisaPilot' : 'Activity'),
        actions: [
          if (_sync != null)
            IconButton(
              tooltip: 'Read new alerts',
              icon: const Icon(Icons.sync),
              onPressed: () {
                _readSms(ask: true);
                if (_gmailConnected) _readEmail(interactive: true);
              },
            ),
          PopupMenuButton<void>(
            // The menu's own context closes with it; dialogs need the screen's.
            itemBuilder: (_) => [
              PopupMenuItem(
                onTap: () => importStatementPdf(context, widget.db),
                child: const Text('Import Canara statement PDF'),
              ),
              if (_email != null && _gmailConnected)
                PopupMenuItem(onTap: _disconnectGmail, child: const Text('Disconnect Gmail'))
              else if (_email != null)
                PopupMenuItem(
                  onTap: () => _readEmail(interactive: true),
                  child: const Text('Connect Gmail for slice alerts'),
                ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: IndexedStack(
          index: _tab,
          children: [
            HomeScreen(
              db: widget.db,
              onSeeAll: () => setState(() => _tab = 1),
              onAddSms: _addSms,
              onReadSms: _sync == null ? null : () => _readSms(ask: true),
            ),
            ActivityScreen(db: widget.db),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Paste an SMS alert',
        onPressed: _addSms,
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Activity'),
        ],
      ),
    );
  }
}
