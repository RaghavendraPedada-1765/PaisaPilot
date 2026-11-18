import 'package:flutter/material.dart';

import '../data/database.dart';
import 'format.dart';

String _payments(int n) => n == 1 ? '1 unsorted payment' : '$n unsorted payments';

Future<void> showPayeeReview(BuildContext context, AppDatabase db) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: .75,
          child: StreamBuilder(
            stream: db.watchUnsortedPayees(),
            builder: (context, snap) => ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                Text(
                  'Review unsorted payees',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Text('Unsorted spending across all months'),
                if (snap.hasError)
                  const ListTile(title: Text('Could not load payees'))
                else if (!snap.hasData)
                  const LinearProgressIndicator()
                else if (snap.data!.isEmpty)
                  const ListTile(
                    title: Text('No unsorted spending with a known payee'),
                  )
                else
                  for (final p in snap.data!)
                    ListTile(
                      title: Text(p.name),
                      subtitle: Text(_payments(p.payments)),
                      trailing: Text(inr(p.spent)),
                      onTap: () => _label(context, db, p),
                    ),
              ],
            ),
          ),
        ),
      ),
    );

Future<void> _label(BuildContext context, AppDatabase db, UnsortedPayee payee) async {
  final categories = await db.watchCategories().first;
  if (!context.mounted) return;
  final category = await showModalBottomSheet<Category>(
    context: context,
    showDragHandle: true,
    builder: (context) => ListView(
      children: [
        ListTile(title: Text('Choose category for ${payee.name}')),
        for (final c in categories)
          ListTile(title: Text(c.name), onTap: () => Navigator.pop(context, c)),
      ],
    ),
  );
  if (category == null || !context.mounted) return;
  // Bound the write to the reviewed snapshot; preserve intervening corrections.
  final ids = await db.unsortedPaymentIds(payee.id);
  if (ids.isEmpty || !context.mounted) return;
  final okay = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Apply ${category.name}?'),
      content: Text(
        'Label ${_payments(ids.length)} from ${payee.name} and remember this category for future payments.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Apply'),
        ),
      ],
    ),
  );
  if (okay != true) return;
  await db.labelPayee(payee.id, category.id, ids);
}
