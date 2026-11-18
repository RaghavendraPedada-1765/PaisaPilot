import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/database.dart';
import 'format.dart';
import 'payee_review.dart';
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
  late final _unsortedPayees = widget.db.watchUnsortedPayees();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String?>(
      stream: widget.db.latestMonth().watchSingle(),
      builder: (context, latest) {
        if (latest.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (latest.data == null) {
          return _Empty(onAddSms: widget.onAddSms, onReadSms: widget.onReadSms);
        }
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
            _Totals(key: ValueKey(month), db: widget.db, month: month),
            const SizedBox(height: 16),
            _ByCategory(key: ValueKey(month), db: widget.db, month: month),
            const SizedBox(height: 16),
            StreamBuilder(
              stream: _unsortedPayees,
              builder: (context, snap) {
                final count = snap.data?.length ?? 0;
                if (count == 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: OutlinedButton.icon(
                    onPressed: () => showPayeeReview(context, widget.db),
                    icon: const Icon(Icons.sell_outlined),
                    label: Text('Review unsorted payees ($count)'),
                  ),
                );
              },
            ),
            _Recent(db: widget.db, onSeeAll: widget.onSeeAll),
          ],
        );
      },
    );
  }
}

class _MonthSwitcher extends StatelessWidget {
  const _MonthSwitcher({
    required this.month,
    required this.onChanged,
    required this.canGoForward,
  });
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
        child: Text(
          monthLabel(month),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
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
  const _Totals({super.key, required this.db, required this.month});
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
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF183C31), Color(0xFF10221E)],
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Monthly spending',
                style: text.titleMedium?.copyWith(
                  color: const Color(0xFFC6DECF),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                inr(spent),
                style: text.displaySmall?.copyWith(
                  color: const Color(0xFFF1FFF9),
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1.4,
                ),
              ),
              const SizedBox(height: 20),
              if (spent + received > 0) ...[
                const Text(
                  'Cash flow',
                  style: TextStyle(
                    color: Color(0xFFC6DECF),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                for (final (label, amount, color) in [
                  ('Spent', spent, const Color(0xFF82E5CA)),
                  ('Received', received, const Color(0xFFABA8EF)),
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 80,
                          child: Text(
                            label,
                            style: const TextStyle(color: Color(0xFFC6DECF)),
                          ),
                        ),
                        Expanded(
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(
                              begin: 0,
                              end: amount / math.max(spent, received),
                            ),
                            duration: _motion(context),
                            curve: Curves.easeOutCubic,
                            builder: (_, value, _) => LinearProgressIndicator(
                              value: value,
                              color: color,
                              backgroundColor: const Color(0x33ACCDBF),
                              borderRadius: BorderRadius.circular(6),
                              minHeight: 8,
                              // The value must stay numeric (Flutter asserts on
                              // "₹…"), so the amount goes in the label.
                              semanticsLabel: '$label ${inr(amount)}',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
              ],
              StreamBuilder(
                key: ValueKey(month),
                stream: db.monthTotals(shiftMonth(month, -1)).watchSingle(),
                builder: (context, prior) {
                  final previous = prior.data;
                  // Nothing to compare against before the first month with data.
                  if (previous == null || !snap.hasData || previous.spent + previous.received == 0) {
                    return const SizedBox.shrink();
                  }
                  return Text('Last month net  ${inr(previous.received - previous.spent)}');
                },
              ),
              const Divider(),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _Figure(label: 'Received', value: inr(received)),
                  ),
                  Expanded(
                    child: _Figure(label: 'Net', value: inr(received - spent)),
                  ),
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
  const _Figure({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: text.labelMedium?.copyWith(color: const Color(0xFFAFCDC0)),
        ),
        Text(
          value,
          style: text.titleMedium?.copyWith(
            color: const Color(0xFFF1FFF9),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ByCategory extends StatelessWidget {
  const _ByCategory({super.key, required this.db, required this.month});
  final AppDatabase db;
  final String month;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return StreamBuilder<List<SpendByCategoryResult>>(
      stream: db.spendByCategory(month).watch(),
      builder: (context, snap) {
        final rows = snap.data ?? const <SpendByCategoryResult>[];
        final total = rows.fold<double>(
          0,
          (sum, row) => sum + (row.total ?? 0),
        );
        return GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Spending by category', style: text.titleMedium),
              const SizedBox(height: 12),
              if (rows.isEmpty)
                Text(
                  'No spending this month',
                  style: text.bodyMedium?.copyWith(color: Colors.white60),
                ),
              if (total > 0)
                Center(
                  child: SizedBox.square(
                    dimension: 140,
                    child: TweenAnimationBuilder<double>(
                      duration: _motion(context),
                      curve: Curves.easeOutCubic,
                      tween: Tween(begin: 0, end: 1),
                      builder: (_, reveal, _) => CustomPaint(
                        painter: _RingPainter(rows, total, reveal),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${rows.length}',
                                style: text.headlineMedium,
                              ),
                              Text(
                                rows.length == 1 ? 'category' : 'categories',
                                style: text.labelMedium,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.circle,
                        size: 10,
                        color: _categoryColor(r.categoryId),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(r.category ?? 'Unsorted')),
                      Text(
                        '${(total == 0 ? 0 : 100 * (r.total ?? 0) / total).toStringAsFixed(0)}%',
                        style: text.labelMedium?.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(inr(r.total ?? 0)),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

Duration _motion(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : const Duration(milliseconds: 520);

Color _categoryColor(int? id) {
  const colors = [
    teal,
    Color(0xFF9BB7FF),
    Color(0xFFE9A4BC),
    Color(0xFFD0B0FF),
    Color(0xFF94CBE1),
    Color(0xFFC8DB8C),
    Color(0xFFF4B18D),
  ];
  return id == null ? const Color(0xFFF0CB78) : colors[id % colors.length];
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.rows, this.total, this.reveal);
  final List<SpendByCategoryResult> rows;
  final double total;
  final double reveal;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = (Offset.zero & size).deflate(12);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 17;
    paint.color = const Color(0xFF324039);
    canvas.drawOval(bounds, paint);
    var angle = -math.pi / 2;
    for (final row in rows) {
      final sweep = 2 * math.pi * (row.total ?? 0) / total;
      final visible = math.min(
        sweep,
        -math.pi / 2 + reveal * 2 * math.pi - angle,
      );
      final gap = rows.length == 1 ? 0.0 : math.min(0.035, sweep / 4);
      if (visible > gap) {
        paint.color = _categoryColor(row.categoryId);
        canvas.drawArc(bounds, angle + gap / 2, visible - gap, false, paint);
      }
      angle += sweep;
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.rows != rows || old.total != total || old.reveal != reveal;
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
                Expanded(
                  child: Text(
                    'Recent activity',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton(onPressed: onSeeAll, child: const Text('See all')),
              ],
            ),
            for (final r in snap.data ?? const <ActivityResult>[])
              TxnTile(db: db, row: r, showDate: true),
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
          const CircleAvatar(
            radius: 36,
            backgroundColor: Color(0xFF24453A),
            child: Icon(
              Icons.account_balance_wallet_outlined,
              size: 34,
              color: teal,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No transactions yet',
            style: Theme.of(context).textTheme.titleLarge,
          ),
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
              onPressed: onReadSms,
              icon: const Icon(Icons.sms_outlined),
              label: const Text('Read bank SMS'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onAddSms,
              child: const Text('Paste an alert instead'),
            ),
          ] else
            FilledButton.icon(
              onPressed: onAddSms,
              icon: const Icon(Icons.sms_outlined),
              label: const Text('Add from SMS'),
            ),
        ],
      ),
    ),
  );
}
