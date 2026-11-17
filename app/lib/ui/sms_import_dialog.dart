import 'package:flutter/material.dart';

import '../import/importer.dart';
import 'format.dart';

/// Paste a bank / card alert to add it. Stands in for reading the SMS inbox
/// until that permission flow exists.
Future<void> showSmsImportDialog(BuildContext context, Importer importer) async {
  final controller = TextEditingController();
  final body = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Add from SMS'),
      content: TextField(
        controller: controller,
        autofocus: true,
        minLines: 3,
        maxLines: 8,
        decoration: const InputDecoration(hintText: 'Paste the bank or card alert'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Add')),
      ],
    ),
  );
  controller.dispose();
  if (body == null || body.trim().isEmpty) return;

  final result = await importer.importSms(body.trim());
  final message = switch (result) {
    null => "That doesn't look like a transaction alert",
    SmsImport(inserted: false) => 'Already recorded',
    SmsImport(:final sms) =>
      '${sms.direction == 'CR' ? 'Received' : 'Paid'} ${inr(sms.amount)} · ${sms.party}',
  };
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}
