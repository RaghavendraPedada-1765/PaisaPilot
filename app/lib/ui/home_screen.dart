import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/database.dart';
import 'activity_filter.dart';
import 'format.dart';
import 'payee_review.dart';
import 'statement_import.dart';
import 'theme.dart';
import 'txn_tile.dart';

/// Home answers "how much did I spend this month?" first, then where it went,
/// what still needs a category, and the latest payments.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.db,
    required this.onOpenActivity,
    required this.onAddSms,
    this.onReadSms,
    this.now,
  });
  final AppDatabase db;
  final ValueChanged<ActivityFilter> onOpenActivity;
  final VoidCallback onAddSms;
  final VoidCallback? onReadSms; // null where there is no SMS inbox
  final DateTime Function()? now; // tests pin the date

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// A query result together with the month it was asked for. While a newer
/// month is loading, the old result must not be shown under the new label.
typedef _ForMonth<T> = (String, T);

class _HomeScreenState extends State<HomeScreen> {
  String? _month; // null = latest month with data
  late final _latest = widget.db.latestMonth().watchSingle();
  late final _unsorted = widget.db.watchUnsortedPayees();
  String? _loaded;
  late Stream<_ForMonth<PeriodTotalsResult>> _totals;
  late Stream<_ForMonth<PeriodTotalsResult>> _previous;
  late Stream<_ForMonth<List<SpendByCategoryResult>>> _categories;
  late String _compareLabel;

  DateTime _now() => (widget.now ?? DateTime.now)();

  /// Streams for [month], made once per month rather than on every build.
  void _load(String month) {
    if (_loaded == month) return;
    _loaded = month;
    final db = widget.db;
    final compare = monthComparison(month, _now());
    _compareLabel = compare.label;
    _totals = db.periodTotals('$month-01', '$month-31').watchSingle().map((r) => (month, r));
    _previous =
        db.periodTotals(compare.previous.from, compare.previous.to).watchSingle().map((r) => (month, r));
    _categories = db.spendByCategory(month).watch().map((r) => (month, r));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<String?>(
      stream: _latest,
      builder: (context, latest) {
        if (latest.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(semanticsLabel: 'Loading'));
        }
        if (latest.data == null) {
          return _Welcome(db: widget.db, onAddSms: widget.onAddSms, onReadSms: widget.onReadSms);
        }
        final month = _month ?? latest.data!;
        _load(month);
        final now = _now();
        return ListView(
          key: const PageStorageKey('home'),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 112),
          children: [
            _MonthBar(
              month: month,
              running: month == currentMonth(now),
              onChanged: (m) => setState(() => _month = m),
              canGoForward: month.compareTo(currentMonth(now)) < 0,
            ),
            const SizedBox(height: 8),
            _Hero(
              month: month,
              totals: _totals,
              previous: _previous,
              compareLabel: _compareLabel,
              onAddSms: widget.onAddSms,
              onImportPdf: () => importStatementPdf(context, widget.db),
            ),
            const SizedBox(height: 16),
            _ReviewCard(db: widget.db, payees: _unsorted),
            _Categories(
              month: month,
              categories: _categories,
              onOpen: widget.onOpenActivity,
            ),
            const SizedBox(height: 16),
            _Recent(db: widget.db, onSeeAll: () => widget.onOpenActivity(const ActivityFilter())),
          ],
        );
      },
    );
  }
}

class _MonthBar extends StatelessWidget {
  const _MonthBar({required this.month, required this.running, required this.onChanged, required this.canGoForward});
  final String month;
  final bool running;
  final ValueChanged<String> onChanged;
  final bool canGoForward;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        IconButton(
          tooltip: 'Previous month',
          icon: const Icon(Icons.chevron_left),
          onPressed: () => onChanged(shiftMonth(month, -1)),
        ),
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: Column(
              children: [
                Text(monthLabel(month), textAlign: TextAlign.center, style: text.titleMedium),
                Text(running ? 'In progress' : 'Full month',
                    textAlign: TextAlign.center, style: text.labelSmall?.copyWith(color: textFaint)),
              ],
            ),
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
}

/// The month's spending, as large as the screen allows, with received, net,
/// a comparison with the previous month and a compact cash-flow chart.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.month,
    required this.totals,
    required this.previous,
    required this.compareLabel,
    required this.onAddSms,
    required this.onImportPdf,
  });
  final String month;
  final Stream<_ForMonth<PeriodTotalsResult>> totals;
  final Stream<_ForMonth<PeriodTotalsResult>> previous;
  final String compareLabel;
  final VoidCallback onAddSms;
  final VoidCallback onImportPdf;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final monthName = monthLabel(month).split(' ').first;
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x3382E5CA), Color(0x0F82E5CA)],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: teal.withValues(alpha: 0.22)),
      ),
      child: StreamBuilder<_ForMonth<PeriodTotalsResult>>(
        stream: totals,
        builder: (context, snap) {
          final t = snap.data?.$1 == month ? snap.data!.$2 : null;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Spent in $monthName', style: text.labelLarge?.copyWith(color: textMuted)),
              const SizedBox(height: 4),
              if (t == null)
                _loading(text)
              else if (t.txns == 0)
                _emptyMonth(context, text)
              else ...[
                Semantics(
                  container: true,
                  label: 'Spent in ${monthLabel(month)}: ${inr(t.spent)}',
                  excludeSemantics: true,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      inr(t.spent),
                      style: money(text.displayMedium)?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -1),
                    ),
                  ),
                ),
                if (t.spent == 0)
                  Text('No spending recorded this month', style: text.bodySmall?.copyWith(color: textMuted)),
                const SizedBox(height: 6),
                _Comparison(month: month, spent: t.spent, previous: previous, label: compareLabel),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 32,
                  runSpacing: 12,
                  children: [
                    _Figure(label: 'Received', value: signedNet(t.received), color: t.received > 0 ? credit : null),
                    _Figure(
                      label: 'Net',
                      value: signedNet(t.received - t.spent),
                      color: t.received - t.spent > 0 ? credit : (t.received - t.spent < 0 ? debit : null),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _CashFlow(spent: t.spent, received: t.received),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _loading(TextTheme text) => Semantics(
        label: 'Loading this month',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('₹ ···', style: money(text.displayMedium)?.copyWith(color: textFaint)),
            const SizedBox(height: 12),
            const LinearProgressIndicator(minHeight: 2),
          ],
        ),
      );

  Widget _emptyMonth(BuildContext context, TextTheme text) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('No transactions', style: text.headlineSmall),
          const SizedBox(height: 4),
          Text('Nothing is recorded for ${monthLabel(month)} yet.', style: text.bodyMedium?.copyWith(color: textMuted)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: onAddSms,
                icon: const Icon(Icons.add),
                label: const Text('Paste an alert'),
              ),
              OutlinedButton.icon(
                onPressed: onImportPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Import statement'),
              ),
            ],
          ),
        ],
      );
}

/// "₹2,340 more vs 1–18 Oct (same days)", or "vs October (full month)" for a
/// finished month.
class _Comparison extends StatelessWidget {
  const _Comparison({required this.month, required this.spent, required this.previous, required this.label});
  final String month;
  final double spent;
  final Stream<_ForMonth<PeriodTotalsResult>> previous;
  final String label;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme.bodyMedium;
    return StreamBuilder<_ForMonth<PeriodTotalsResult>>(
      stream: previous,
      builder: (context, snap) {
        final p = snap.data?.$1 == month ? snap.data!.$2 : null;
        if (p == null) return Text(' ', style: text);
        if (p.txns == 0) {
          return Text('No transactions to compare $label', style: text?.copyWith(color: textFaint));
        }
        final delta = spent - p.spent;
        final same = delta.abs() < 0.5;
        final color = same ? textMuted : (delta > 0 ? debit : credit);
        final words = same ? 'Same spending' : '${inr(delta.abs())} ${delta > 0 ? 'more' : 'less'}';
        return Semantics(
          label: '$words $label. Spent ${inr(p.spent)} then.',
          excludeSemantics: true,
          child: Text.rich(
            TextSpan(children: [
              if (!same)
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Icon(delta > 0 ? Icons.arrow_upward : Icons.arrow_downward, size: 16, color: color),
                ),
              TextSpan(text: ' $words ', style: TextStyle(color: color, fontWeight: FontWeight.w600)),
              TextSpan(text: label, style: const TextStyle(color: textMuted)),
            ]),
            style: money(text),
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
        Text(label, style: text.labelMedium?.copyWith(color: textMuted)),
        Text(value, style: money(text.titleLarge)?.copyWith(color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

/// Money out against money in as two bars; the figures sit above it.
class _CashFlow extends StatelessWidget {
  const _CashFlow({required this.spent, required this.received});
  final double spent;
  final double received;

  @override
  Widget build(BuildContext context) {
    final top = math.max(spent, received);
    final label = Theme.of(context).textTheme.labelSmall?.copyWith(color: textMuted);
    return Semantics(
      label: 'Cash flow: ${inr(spent)} out, ${inr(received)} in',
      excludeSemantics: true,
      child: Column(
        children: [
          for (final (name, value, color) in [('Out', spent, debit), ('In', received, credit)])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(width: 36, child: Text(name, style: label)),
                  Expanded(
                    // Implicit: animates from the bar's current length when the
                    // figures change, never on rebuilds with the same figures.
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: top == 0 ? 0 : value / top),
                      duration: motion(context, 520),
                      curve: Curves.easeOutCubic,
                      builder: (_, v, _) => LinearProgressIndicator(
                        value: v,
                        color: color,
                        backgroundColor: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(4),
                        minHeight: 6,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Unsorted spending waiting for a category, biggest payees first. Tap a
/// payee, pick a category: two taps (plus a confirmation with the count).
class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.db, required this.payees});
  final AppDatabase db;
  final Stream<List<UnsortedPayee>> payees;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return StreamBuilder<List<UnsortedPayee>>(
      stream: payees,
      builder: (context, snap) {
        final all = snap.data ?? const <UnsortedPayee>[];
        if (all.isEmpty) return const SizedBox.shrink();
        final total = all.fold<double>(0, (s, p) => s + p.spent);
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: GlassCard(
            fill: const Color(0x14F0CB78),
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Review unsorted payees', style: text.titleMedium),
                      const SizedBox(height: 2),
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(
                            text: inr(total),
                            style: const TextStyle(color: unsortedColor, fontWeight: FontWeight.w700),
                          ),
                          TextSpan(
                            text: ' awaiting a category · ${all.length} ${all.length == 1 ? 'payee' : 'payees'}'
                                ' · all months',
                          ),
                        ]),
                        style: money(text.bodyMedium)?.copyWith(color: textMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                for (final p in all.take(3)) UnsortedPayeeTile(db: db, payee: p),
                if (all.length > 3)
                  TextButton(
                    onPressed: () => showPayeeReview(context, db),
                    child: Text('Review all ${all.length} payees'),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One donut and its legend. Tapping a slice or a legend row opens Activity
/// on that category and month.
class _Categories extends StatelessWidget {
  const _Categories({required this.month, required this.categories, required this.onOpen});
  final String month;
  final Stream<_ForMonth<List<SpendByCategoryResult>>> categories;
  final ValueChanged<ActivityFilter> onOpen;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
      child: StreamBuilder<_ForMonth<List<SpendByCategoryResult>>>(
        stream: categories,
        builder: (context, snap) {
          final ready = snap.data?.$1 == month;
          final rows = snap.data?.$2 ?? const <SpendByCategoryResult>[];
          final total = rows.fold<double>(0, (s, r) => s + (r.total ?? 0));
          void open(SpendByCategoryResult r) =>
              onOpen(ActivityFilter.slice(categoryId: r.categoryId, categoryName: r.category, month: month));
          final slices = [
            for (final r in rows) (key: r.categoryId ?? 0, value: r.total ?? 0, color: categoryColor(r.categoryId)),
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text('Where it went', style: text.titleMedium),
              ),
              if (snap.hasData && rows.isEmpty && ready)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
                  child: Text('No spending in ${monthLabel(month)}', style: text.bodyMedium?.copyWith(color: textMuted)),
                ),
              if (rows.isNotEmpty) ...[
                const SizedBox(height: 12),
                Center(
                  child: _Donut(
                    key: const ValueKey('donut'),
                    slices: slices,
                    semanticsLabel: 'Spending by category, ${monthLabel(month)}: '
                        '${[for (final r in rows) '${r.category ?? 'Unsorted'} ${inr(r.total ?? 0)}'].join(', ')}',
                    center: '${rows.length}',
                    centerCaption: rows.length == 1 ? 'category' : 'categories',
                    onTap: (key) => open(rows.firstWhere((r) => (r.categoryId ?? 0) == key)),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (!ready)
                const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator(minHeight: 2))
              else
                for (final r in rows)
                  _LegendRow(
                    key: ValueKey('legend:${r.categoryId ?? 0}'),
                    name: r.category ?? 'Unsorted',
                    color: categoryColor(r.categoryId),
                    share: total == 0 ? 0 : (r.total ?? 0) / total,
                    amount: r.total ?? 0,
                    payments: r.txnCount,
                    onTap: () => open(r),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    super.key,
    required this.name,
    required this.color,
    required this.share,
    required this.amount,
    required this.payments,
    required this.onTap,
  });
  final String name;
  final Color color;
  final double share;
  final double amount;
  final int payments;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final percent = '${(share * 100).round()}%';
    // With large text the figures move under the name instead of squeezing it.
    final stacked = MediaQuery.textScalerOf(context).scale(10) > 15;
    final figures = [
      Text(percent, style: money(text.labelMedium)?.copyWith(color: textFaint)),
      const SizedBox(width: 12),
      Text(inr(amount), textAlign: TextAlign.right, style: money(text.bodyLarge)),
    ];
    return Semantics(
      container: true,
      button: true,
      label: '$name, $percent, ${inr(amount)}, $payments ${payments == 1 ? 'payment' : 'payments'}. '
          'Show these payments',
      excludeSemantics: true,
      child: PressScale(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Row(
                children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(name, style: text.bodyLarge?.copyWith(color: name == 'Unsorted' ? unsortedColor : null)),
                        if (stacked) Wrap(alignment: WrapAlignment.end, children: figures),
                      ],
                    ),
                  ),
                  if (!stacked) ...[const SizedBox(width: 8), ...figures],
                  const Icon(Icons.chevron_right, size: 18, color: textFaint),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

typedef _Slice = ({int key, double value, Color color});

/// Category donut. Changing slices morph from the current geometry over 520
/// ms (instantly with reduced motion); a rebuild with the same slices does
/// nothing. Colours come from the slices, so they stay put across months.
class _Donut extends StatefulWidget {
  const _Donut({
    super.key,
    required this.slices,
    required this.semanticsLabel,
    required this.center,
    required this.centerCaption,
    required this.onTap,
  });
  final List<_Slice> slices;
  final String semanticsLabel;
  final String center;
  final String centerCaption;
  final ValueChanged<int> onTap;

  @override
  State<_Donut> createState() => _DonutState();
}

class _DonutState extends State<_Donut> with SingleTickerProviderStateMixin {
  static const _size = 172.0;
  static const _stroke = 20.0;
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 520))
    ..addListener(() => setState(() {}));
  var _from = <int, double>{};
  var _to = <int, double>{};
  var _order = <int>[];
  final _colors = <int, Color>{};
  var _started = false;

  Map<int, double> _fractions(List<_Slice> slices) {
    final total = slices.fold<double>(0, (s, x) => s + x.value);
    return {for (final s in slices) s.key: total == 0 ? 0 : s.value / total};
  }

  double _t() => Curves.easeOutCubic.transform(_controller.value);

  Map<int, double> _current() {
    final t = _t();
    return {for (final k in _order) k: (_from[k] ?? 0) + ((_to[k] ?? 0) - (_from[k] ?? 0)) * t};
  }

  void _retarget() {
    final next = _fractions(widget.slices);
    _from = _started ? _current() : {};
    _to = next;
    _order = [...next.keys, ..._from.keys.where((k) => !next.containsKey(k))];
    for (final s in widget.slices) {
      _colors[s.key] = s.color;
    }
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward(from: 0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) _retarget();
  }

  @override
  void didUpdateWidget(_Donut old) {
    super.didUpdateWidget(old);
    final next = _fractions(widget.slices);
    final same = next.length == _to.length && next.entries.every((e) => (_to[e.key] ?? -1) == e.value);
    if (!same) _retarget();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _tapAt(Offset p) {
    final c = const Offset(_size / 2, _size / 2);
    final d = p - c;
    final r = d.distance;
    if (r < _size / 2 - _stroke * 2 || r > _size / 2 + 4) return;
    // Clockwise from 12 o'clock, 0..1.
    final turn = ((math.atan2(d.dy, d.dx) + math.pi / 2) / (2 * math.pi)) % 1;
    var acc = 0.0;
    for (final k in _to.keys) {
      acc += _to[k]!;
      if (turn <= acc) return widget.onTap(k);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final segments = [for (final e in _current().entries) (fraction: e.value, color: _colors[e.key] ?? glassEdge)];
    return Semantics(
      container: true,
      label: widget.semanticsLabel,
      excludeSemantics: true,
      child: GestureDetector(
        onTapUp: (d) => _tapAt(d.localPosition),
        child: SizedBox.square(
          dimension: _size,
          child: CustomPaint(
            painter: _RingPainter(segments, _stroke),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.center, style: money(text.headlineMedium)),
                  Text(widget.centerCaption, style: text.labelMedium?.copyWith(color: textMuted)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter(this.segments, this.stroke);
  final List<({double fraction, Color color})> segments;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = (Offset.zero & size).deflate(stroke / 2 + 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    paint.color = Colors.white.withValues(alpha: 0.06);
    canvas.drawOval(bounds, paint);
    final visible = segments.where((s) => s.fraction > 0.0005).length;
    var angle = -math.pi / 2;
    for (final s in segments) {
      final sweep = 2 * math.pi * s.fraction;
      final gap = visible <= 1 ? 0.0 : math.min(0.03, sweep / 4);
      if (sweep > gap) {
        paint.color = s.color;
        canvas.drawArc(bounds, angle + gap / 2, sweep - gap, false, paint);
      }
      angle += sweep;
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => true;
}

class _Recent extends StatefulWidget {
  const _Recent({required this.db, required this.onSeeAll});
  final AppDatabase db;
  final VoidCallback onSeeAll;

  @override
  State<_Recent> createState() => _RecentState();
}

class _RecentState extends State<_Recent> {
  late final _rows = widget.db.activity(null, null, null, '', false, 5).watch();

  @override
  Widget build(BuildContext context) => GlassCard(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: StreamBuilder<List<ActivityResult>>(
          stream: _rows,
          builder: (context, snap) => Column(
            children: [
              Row(
                children: [
                  const SizedBox(width: 8),
                  Expanded(child: Text('Recent', style: Theme.of(context).textTheme.titleMedium)),
                  TextButton(onPressed: widget.onSeeAll, child: const Text('See all')),
                ],
              ),
              for (final r in snap.data ?? const <ActivityResult>[]) TxnTile(db: widget.db, row: r, showDate: true),
            ],
          ),
        ),
      );
}

/// First run: nothing recorded yet. Every way in, one tap each.
class _Welcome extends StatelessWidget {
  const _Welcome({required this.db, required this.onAddSms, this.onReadSms});
  final AppDatabase db;
  final VoidCallback onAddSms;
  final VoidCallback? onReadSms;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 112),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset('assets/brand/logo_192.png', width: 80, height: 80, semanticLabel: 'PaisaPilot'),
            ),
            const SizedBox(height: 20),
            Text('No transactions yet', style: text.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              onReadSms == null
                  ? 'Paste a bank or card alert to get started.'
                  : 'PaisaPilot reads bank and card alerts from your SMS. They never leave this phone.',
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: textMuted),
            ),
            const SizedBox(height: 20),
            if (onReadSms != null) ...[
              FilledButton.icon(
                onPressed: onReadSms,
                icon: const Icon(Icons.sms_outlined),
                label: const Text('Read bank SMS'),
              ),
              const SizedBox(height: 8),
            ],
            FilledButton.tonalIcon(
              onPressed: onAddSms,
              icon: const Icon(Icons.add),
              label: Text(onReadSms == null ? 'Add from SMS' : 'Paste an alert instead'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => importStatementPdf(context, db),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Import a statement PDF'),
            ),
          ],
        ),
      ),
    );
  }
}
