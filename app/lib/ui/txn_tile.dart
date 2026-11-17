import 'package:flutter/material.dart';

import '../data/database.dart';
import 'category_sheet.dart';
import 'format.dart';
import 'theme.dart';

class TxnTile extends StatelessWidget {
  const TxnTile({super.key, required this.db, required this.row, this.showDate = false});
  final AppDatabase db;
  final ActivityResult row;
  final bool showDate; // when the list is not grouped by day

  @override
  Widget build(BuildContext context) {
    final t = row.t;
    final credit = t.direction == 'CR';
    final name = row.payee ?? 'Unknown';
    final text = Theme.of(context).textTheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: CircleAvatar(
        backgroundColor: (credit ? teal : Colors.white).withValues(alpha: 0.08),
        foregroundColor: credit ? teal : Colors.white70,
        child: Text(name.isEmpty ? '?' : name[0].toUpperCase()),
      ),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (showDate) dayLabel(t.txnDate),
          ?timeLabel(t.txnTime),
          row.category ?? 'Unsorted',
          row.account,
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: row.category == null ? text.bodyMedium?.copyWith(color: Colors.amberAccent) : null,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '${credit ? '+' : '−'}${inr(t.amount)}',
            style: text.titleMedium?.copyWith(color: credit ? teal : null, fontWeight: FontWeight.w600),
          ),
          if (row.photos > 0)
            Icon(Icons.photo_camera_outlined, size: 14, color: Colors.white54, semanticLabel: '${row.photos} photos'),
        ],
      ),
      onTap: () => showCategorySheet(context, db, row),
    );
  }
}
