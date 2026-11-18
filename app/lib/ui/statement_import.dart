import 'package:drift/drift.dart' hide Column, Table;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart' show PdfPasswordException;

import '../data/database.dart';
import '../import/importer.dart';
import '../import/pdf_text.dart';
import '../import/statement_parser.dart';
import 'format.dart';

/// Picks a Canara e-passbook PDF, reads it on the phone and imports it.
/// Rows already known from SMS are matched by UPI ref; balance-only SMS rows
/// gain the statement's payee.
Future<void> importStatementPdf(BuildContext context, AppDatabase db) async {
  void toast(String m) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
  final path = picked.isEmpty ? null : picked.single.path;
  if (path == null || !context.mounted) return;

  final String text;
  try {
    text = await pdfLayoutText(path, password: () => _askPassword(context));
  } on PdfPasswordException {
    toast('Statement not opened: it needs its password');
    return;
  } catch (e) {
    debugPrint('Statement PDF failed: $e');
    toast("Couldn't read that PDF");
    return;
  }

  final StatementResult preview;
  try {
    preview = parseStatement(text);
  } catch (e, st) {
    debugPrint('Statement parse failed: $e\n$st');
    toast("Couldn't read the transactions in that PDF");
    return;
  }
  if (preview.rows.isEmpty) {
    toast('No Canara passbook transactions found in that PDF');
    return;
  }
  if (!context.mounted) return;
  final mismatches = preview.mismatches;
  final go = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Import statement?'),
      content: Text('Found ${preview.rows.length} transactions.'
          '${mismatches > 0 ? '\n\n$mismatches of them do not match the printed running balance, so the PDF may '
              'not have been read correctly.' : ''}'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Import')),
      ],
    ),
  );
  if (go != true || !context.mounted) return;
  final accountId = await _chooseAccount(context, db, statementAccount(text));
  if (accountId == null) return;

  final result = await Importer(db).importStatement(accountId, text);
  final summary = '${result.inserted} new, ${result.duplicates} already recorded'
      '${result.named > 0 ? ' (${result.named} given payee names)' : ''}';
  final inStatement = result.result.rows.length;
  if (result.reconciles) {
    toast('$summary · $inStatement in statement = $inStatement in PaisaPilot');
    return;
  }
  // The account has more (or fewer) rows over these dates than the statement:
  // something is doubled or missing.
  if (!context.mounted) return;
  final diff = result.inApp - inStatement;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text("Counts don't match"),
      content: Text('$summary.\n\n'
          'From ${dayLabel(result.firstDate!)} to ${dayLabel(result.lastDate!)} the statement has $inStatement '
          'transactions, but PaisaPilot has ${result.inApp} for this account.\n\n'
          '${diff > 0 ? '$diff may be duplicates.' : '${-diff} are missing from PaisaPilot.'}'),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
    ),
  );
}

Future<String?> _askPassword(BuildContext context) async {
  if (!context.mounted) return null;
  return showDialog<String>(context: context, builder: (_) => const _PasswordDialog());
}

/// Owns its controller and disposes it only once the dialog has closed (see
/// _PasteAlertDialog in sms_import_dialog.dart for the crash this avoids).
class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog();

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Statement password'),
        content: TextField(
          controller: _controller,
          autofocus: true,
          obscureText: true,
          decoration: const InputDecoration(hintText: 'Password for this PDF'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, _controller.text), child: const Text('Open')),
        ],
      );
}

String _digits(String s) => s.replaceAll(RegExp(r'\D'), '');

/// The Canara account whose trailing digits match the statement header, or
/// the user's pick when the header has no number or several accounts fit.
Future<int?> _chooseAccount(BuildContext context, AppDatabase db, String? printed) async {
  final banks = await (db.select(db.accounts)..where((a) => a.kind.equals('bank'))).get();
  final canara = banks.where((a) => a.name.toLowerCase().startsWith('canara')).toList();
  final digits = _digits(printed ?? '');
  if (digits.length >= 3) {
    final fits = canara.where((a) {
      final d = _digits(a.maskedNumber ?? '');
      return d.length >= 3 && (digits.endsWith(d) || d.endsWith(digits));
    }).toList();
    if (fits.length == 1) return fits.single.id;
  }
  if (!context.mounted) return null;
  const newAccount = -1;
  final choice = await showDialog<int>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Which account is this statement for?'),
      children: [
        for (final a in banks) SimpleDialogOption(onPressed: () => Navigator.pop(context, a.id), child: Text(a.name)),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, newAccount),
          child: const Text('New Canara account'),
        ),
      ],
    ),
  );
  if (choice != newAccount) return choice;
  final last = digits.length >= 4 ? digits.substring(digits.length - 4) : digits;
  return db.into(db.accounts).insert(AccountsCompanion.insert(
    name: last.isEmpty ? 'Canara' : 'Canara XX$last',
    kind: 'bank',
    maskedNumber: Value(last.isEmpty ? null : 'XX$last'),
  ));
}
