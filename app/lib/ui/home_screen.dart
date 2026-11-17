import 'package:flutter/material.dart';

import '../data/database.dart';
import 'format.dart';
import 'theme.dart';
import 'txn_tile.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.db,
    required this.onSeeAll,
    required this.onAddSms,
    this.onReadSms,
  });
  final AppDatabase db;
  final VoidCallback onSeeAll;
  final VoidCallback onAddSms;
  final VoidCallback? onReadSms; // null where there is no SMS inbox

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _month; // null = latest month with data

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String?>(
      stream: widget.db.latestMonth().watchSingle(),
      builder: (context, latest) {
        if (latest.connectionState == ConnectionState.waiting) return const SizedBox.shrink();
        if (latest.data == null) return _Empty(onAddSms: widget.onAddSms, onReadSms: widget.onReadSms);
        final month = _month ?? latest.data!;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            _MonthSwitcher(
              month: month,
              onChanged: (m) => setState(() => _month = m),
              canGoForward: month.compareTo(currentMonth()) < 0,
            ),
            const SizedBox(height: 12),
            _Totals(db: widget.db, month: month),
            const SizedBox(height: 16),
            _ByCategory(db: widget.db, month: month),
            const SizedBox(height: 16),
            _Recent(db: widget.db, onSeeAll: widget.onSeeAll),
          ],
        );
      },
    );
  }
}

class _MonthSwitcher extends StatelessWidget {
  const _MonthSwitcher({required this.month, required this.onChanged, required this.canGoForward});
  final String month;
  final ValueChanged<String> onChanged;
  final bool canGoForward;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          IconButton(
            tooltip: 'Previous month',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => onChanged(shiftMonth(month, -1)),
          ),
          Expanded(
            child: Text(monthLabel(month),
                textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
          ),
          IconButton(
            tooltip: 'Next month',
            icon: const Icon(Icons.chevron_right),
            onPressed: canGoForward ? () => onChanged(shiftMonth(month, 1)) : null,
          ),
        ],
      );
}

class _Totals extends StatelessWidget {
  const _Totals({required this.db, required this.month});
  final AppDatabase db;
  final String month;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return StreamBuilder<MonthTotalsResult>(
      stream: db.monthTotals(month).watchSingle(),
      builder: (context, snap) {
        final spent = snap.data?.spent ?? 0;
        final received = snap.data?.received ?? 0;
        return GlassCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Spent', style: text.labelLarge?.copyWith(color: Colors.white60)),
              const SizedBox(height: 4),
              Text(inr(spent), style: text.displaySmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _Figure(label: 'Received', value: inr(received), color: teal)),
                  Expanded(child: _Figure(label: 'Net', value: inr(received - spent))),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.labelMedium?.copyWith(color: Colors.white60)),
        Text(value, style: text.titleMedium?.copyWith(color: color)),
      ],
    );
  }
}

class _ByCategory extends StatelessWidget {
  const _ByCategory({required this.db, required this.month});
  final AppDatabase db;
  final String month;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return StreamBuilder<List<SpendByCategoryResult>>(
      stream: db.spendByCategory(month).watch(),
      builder: (context, snap) {
        final rows = snap.data ?? const <SpendByCategoryResult>[];
        final top = rows.isEmpty ? 0.0 : rows.first.total ?? 0;
        return GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Where it went', style: text.titleMedium),
              const SizedBox(height: 12),
              if (rows.isEmpty)
                Text('No spending this month', style: text.bodyMedium?.copyWith(color: Colors.white60)),
              for (final r in rows) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        r.category ?? 'Unsorted · ${r.txnCount} to label',
                        style: r.category == null ? const TextStyle(color: Colors.amberAccent) : null,
                      ),
                    ),
                    Text(inr(r.total ?? 0)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: top == 0 ? 0 : (r.total ?? 0) / top,
                    minHeight: 6,
                    color: r.category == null ? Colors.amberAccent : teal,
                    backgroundColor: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Recent extends StatelessWidget {
  const _Recent({required this.db, required this.onSeeAll});
  final AppDatabase db;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: StreamBuilder<List<ActivityResult>>(
        stream: db.activity(null, null, '', false, 5).watch(),
        builder: (context, snap) => Column(
          children: [
            Row(
              children: [
                const SizedBox(width: 4),
                Expanded(child: Text('Recent', style: Theme.of(context).textTheme.titleMedium)),
                TextButton(onPressed: onSeeAll, child: const Text('See all')),
              ],
            ),
            for (final r in snap.data ?? const <ActivityResult>[]) TxnTile(db: db, row: r),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onAddSms, this.onReadSms});
  final VoidCallback onAddSms;
  final VoidCallback? onReadSms;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.receipt_long_outlined, size: 48, color: teal),
              const SizedBox(height: 16),
              Text('No transactions yet', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                onReadSms == null
                    ? 'Paste a bank or card alert to get started.'
                    : 'PaisaPilot reads bank and card alerts from your SMS. They never leave this phone.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              if (onReadSms != null) ...[
                FilledButton.icon(
                    onPressed: onReadSms, icon: const Icon(Icons.sms_outlined), label: const Text('Read bank SMS')),
                const SizedBox(height: 8),
                TextButton(onPressed: onAddSms, child: const Text('Paste an alert instead')),
              ] else
                FilledButton.icon(
                    onPressed: onAddSms, icon: const Icon(Icons.sms_outlined), label: const Text('Add from SMS')),
            ],
          ),
        ),
      );
}
