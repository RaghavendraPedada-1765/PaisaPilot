import 'package:flutter/material.dart';

import '../data/database.dart';
import 'format.dart';
import 'theme.dart';

String paymentsLabel(int n) => n == 1 ? '1 unsorted payment' : '$n unsorted payments';

/// Every payee with unsorted spending, largest first, across all months.
Future<void> showPayeeReview(BuildContext context, AppDatabase db) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: FractionallySizedBox(
          heightFactor: .8,
          child: StreamBuilder(
            stream: db.watchUnsortedPayees(),
            builder: (context, snap) {
              final payees = snap.data ?? const <UnsortedPayee>[];
              final total = payees.fold<double>(0, (s, p) => s + p.spent);
              final text = Theme.of(context).textTheme;
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  Text('Review unsorted payees', style: text.titleLarge),
                  const SizedBox(height: 4),
                  if (snap.hasData && payees.isNotEmpty)
                    Text(
                      '${inr(total)} awaiting a category across ${payees.length} '
                      '${payees.length == 1 ? 'payee' : 'payees'} · all months',
                      style: money(text.bodyMedium)?.copyWith(color: textMuted),
                    ),
                  const SizedBox(height: 8),
                  if (snap.hasError)
                    const ListTile(title: Text('Could not load payees'))
                  else if (!snap.hasData)
                    const LinearProgressIndicator()
                  else if (payees.isEmpty)
                    const ListTile(title: Text('Nothing left to sort'))
                  else
                    for (final p in payees) UnsortedPayeeTile(db: db, payee: p),
                ],
              );
            },
          ),
        ),
      ),
    );

/// A payee awaiting a category; tapping starts labelling it.
class UnsortedPayeeTile extends StatelessWidget {
  const UnsortedPayeeTile({super.key, required this.db, required this.payee});
  final AppDatabase db;
  final UnsortedPayee payee;

  @override
  Widget build(BuildContext context) => PressScale(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          leading: const Icon(Icons.sell_outlined, color: unsortedColor),
          title: Text(payee.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(paymentsLabel(payee.payments)),
          trailing: Text(inr(payee.spent), style: money(Theme.of(context).textTheme.titleSmall)),
          onTap: () => labelPayeeFlow(context, db, payee),
        ),
      );
}

/// Choose a category for [payee], preview how many payments it labels, then
/// label them and remember it for future payments.
Future<void> labelPayeeFlow(BuildContext context, AppDatabase db, UnsortedPayee payee) async {
  final categories = await db.watchCategories().first;
  if (!context.mounted) return;
  final category = await showModalBottomSheet<Category>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          ListTile(
            title: Text('Category for ${payee.name}', style: Theme.of(context).textTheme.titleMedium),
            subtitle: Text('${paymentsLabel(payee.payments)} · ${inr(payee.spent)}'),
          ),
          for (final c in categories)
            ListTile(
              leading: Icon(Icons.circle, size: 12, color: categoryColor(c.id)),
              title: Text(c.name),
              onTap: () => Navigator.pop(context, c),
            ),
        ],
      ),
    ),
  );
  if (category == null || !context.mounted) return;
  // Bound the write to the reviewed snapshot; preserve intervening corrections.
  final ids = await db.unsortedPaymentIds(payee.id);
  if (ids.isEmpty || !context.mounted) return;
  final okay = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Label ${paymentsLabel(ids.length)} as ${category.name}?'),
      content: Text('From ${payee.name}. Future payments to ${payee.name} will be ${category.name} too.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Apply')),
      ],
    ),
  );
  if (okay != true) return;
  await db.labelPayee(payee.id, category.id, ids);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${payee.name}: ${ids.length == 1 ? '1 payment' : '${ids.length} payments'} → ${category.name}')),
    );
  }
}
