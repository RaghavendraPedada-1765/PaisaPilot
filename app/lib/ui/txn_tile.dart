import 'package:flutter/material.dart';

import '../data/database.dart';
import 'category_sheet.dart';
import 'format.dart';
import 'theme.dart';

/// One transaction: payee, when and where, category, and the signed amount
/// right-aligned. Tapping opens the detail sheet.
class TxnTile extends StatelessWidget {
  const TxnTile({super.key, required this.db, required this.row, this.showDate = false});
  final AppDatabase db;
  final ActivityResult row;
  final bool showDate; // when the list is not grouped by day

  @override
  Widget build(BuildContext context) {
    final t = row.t;
    final isCredit = t.direction == 'CR';
    final name = row.payee ?? 'Unknown';
    final text = Theme.of(context).textTheme;
    final amount = signedInr(t.amount, credit: isCredit);
    final when = [if (showDate) dayLabel(t.txnDate), ?timeLabel(t.txnTime)].join(', ');
    // With large text there is no room beside the payee: the amount takes its
    // own right-aligned line instead of squeezing the name to nothing.
    final stacked = MediaQuery.textScalerOf(context).scale(10) > 15;
    final amountText = Text(
      amount,
      textAlign: TextAlign.right,
      style: money(text.titleMedium)?.copyWith(color: isCredit ? credit : debit, fontWeight: FontWeight.w600),
    );
    return Semantics(
      container: true,
      button: true,
      label: '$name, ${isCredit ? 'received' : 'paid'} ${inr(t.amount)}, ${row.category ?? 'Unsorted'}'
          '${when.isEmpty ? '' : ', $when'}${row.photos > 0 ? ', ${row.photos} receipt photos' : ''}',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => showCategorySheet(context, db, row),
        borderRadius: BorderRadius.circular(14),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: categoryColor(t.categoryId).withValues(alpha: 0.14),
                  foregroundColor: categoryColor(t.categoryId),
                  child: Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodyLarge),
                      const SizedBox(height: 2),
                      Text.rich(
                        TextSpan(children: [
                          if (row.photos > 0)
                            const WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Padding(
                                padding: EdgeInsets.only(right: 4),
                                child: Icon(Icons.receipt_long, size: 14, color: teal),
                              ),
                            ),
                          TextSpan(
                            text: row.category ?? 'Unsorted',
                            style: TextStyle(color: row.category == null ? unsortedColor : textMuted),
                          ),
                          TextSpan(text: [when, row.account].where((s) => s.isNotEmpty).map((s) => ' · $s').join()),
                        ]),
                        maxLines: stacked ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(color: textFaint),
                      ),
                      if (stacked) Align(alignment: Alignment.centerRight, child: amountText),
                    ],
                  ),
                ),
                if (!stacked) ...[const SizedBox(width: 12), amountText],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
