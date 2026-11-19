import 'package:flutter/material.dart';

import '../data/database.dart';
import 'activity_filter.dart';
import 'format.dart';
import 'theme.dart';
import 'txn_tile.dart';

/// Every transaction, compact and easy to scan: search, one row of filter
/// chips, a summary of what is shown, then payments grouped by day.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key, required this.db, required this.filter});
  final AppDatabase db;
  final ValueNotifier<ActivityFilter> filter; // shared with Home

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  static const _maxRows = 500;
  final _searchField = TextEditingController();
  final _scroll = ScrollController();
  String _search = '';
  late Stream<List<ActivityResult>> _rows;
  late Stream<ActivityTotalsResult> _totals;

  ActivityFilter get _filter => widget.filter.value;

  @override
  void initState() {
    super.initState();
    _subscribe();
    widget.filter.addListener(_changed);
  }

  @override
  void dispose() {
    widget.filter.removeListener(_changed);
    _searchField.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _subscribe() {
    final f = _filter;
    _rows = widget.db.activity(f.direction, f.category, f.month, _search, f.byAmount, _maxRows).watch();
    _totals = widget.db.activityTotals(f.direction, f.category, f.month, _search).watchSingle();
  }

  /// New filters: new queries, from the top of the list.
  void _changed() {
    setState(_subscribe);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _set(ActivityFilter f) => widget.filter.value = f;

  void _clearAll() {
    _searchField.clear();
    _search = '';
    final keepSort = ActivityFilter(byAmount: _filter.byAmount);
    if (_filter == keepSort) {
      _changed();
    } else {
      _set(keepSort);
    }
  }

  Future<void> _pickCategory() async {
    final cats = await widget.db.watchCategories().first;
    if (!mounted) return;
    final picked = await showModalBottomSheet<(int?, String?)>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            const ListTile(title: Text('Show category')),
            ListTile(title: const Text('All categories'), onTap: () => Navigator.pop(context, (null, null))),
            ListTile(
              leading: const Icon(Icons.circle, size: 12, color: unsortedColor),
              title: const Text('Unsorted'),
              onTap: () => Navigator.pop(context, (0, 'Unsorted')),
            ),
            for (final c in cats)
              ListTile(
                leading: Icon(Icons.circle, size: 12, color: categoryColor(c.id)),
                title: Text(c.name),
                selected: c.id == _filter.category,
                onTap: () => Navigator.pop(context, (c.id, c.name)),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    _set(_filter.copyWith(category: picked.$1, categoryName: picked.$2));
  }

  Future<void> _pickMonth() async {
    final months = await widget.db.activityMonths().get();
    if (!mounted) return;
    final picked = await showModalBottomSheet<(String?,)>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            const ListTile(title: Text('Show month')),
            ListTile(title: const Text('All months'), onTap: () => Navigator.pop(context, (null,))),
            for (final m in months)
              ListTile(
                title: Text(monthLabel(m)),
                selected: m == _filter.month,
                onTap: () => Navigator.pop(context, (m,)),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    _set(_filter.copyWith(month: picked.$1));
  }

  @override
  Widget build(BuildContext context) {
    final f = _filter;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: TextField(
            controller: _searchField,
            onChanged: (v) => setState(() {
              _search = v.trim();
              _subscribe();
            }),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search payee or category',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() {
                        _searchField.clear();
                        _search = '';
                        _subscribe();
                      }),
                    ),
            ),
          ),
        ),
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            children: [
              if (f.narrows || _search.isNotEmpty) ...[
                ActionChip(
                  avatar: const Icon(Icons.filter_alt_off_outlined, size: 18),
                  label: const Text('Clear'),
                  tooltip: 'Clear all filters',
                  onPressed: _clearAll,
                ),
                const SizedBox(width: 8),
              ],
              for (final (label, dir, tip) in [
                ('All', null, 'Money in and out'),
                ('Out', 'DR', 'Money out'),
                ('In', 'CR', 'Money in'),
              ]) ...[
                ChoiceChip(
                  label: Text(label),
                  tooltip: tip,
                  selected: f.direction == dir,
                  onSelected: (_) => _set(f.copyWith(direction: dir)),
                ),
                const SizedBox(width: 6),
              ],
              const SizedBox(width: 4),
              _ValueChip(
                label: 'Category',
                value: f.categoryName,
                onPick: _pickCategory,
                onClear: () => _set(f.withoutCategory()),
              ),
              const SizedBox(width: 6),
              _ValueChip(
                label: 'Month',
                value: f.month == null ? null : monthLabel(f.month!),
                onPick: _pickMonth,
                onClear: () => _set(f.copyWith(month: null)),
              ),
              const SizedBox(width: 6),
              FilterChip(
                avatar: const Icon(Icons.sort, size: 18),
                label: const Text('Largest first'),
                selected: f.byAmount,
                onSelected: (v) => _set(f.copyWith(byAmount: v)),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<ActivityResult>>(
            stream: _rows,
            builder: (context, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator(semanticsLabel: 'Loading'));
              final rows = snap.data!;
              return Column(
                children: [
                  _Summary(totals: _totals, shown: rows.length, filter: f, search: _search),
                  Expanded(child: rows.isEmpty ? _empty(f) : _list(rows, f)),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _empty(ActivityFilter f) {
    final text = Theme.of(context).textTheme;
    final filtered = _search.isNotEmpty || f.direction != null || f.month != null;
    final (title, body) = switch ((filtered, f.category)) {
      (false, 0) => ('Nothing left to sort', 'Every payment has a category.'),
      (false, null) => ('No transactions yet', 'Read your bank SMS or paste an alert to begin.'),
      _ => ('No matching transactions', 'Nothing matches ${_search.isEmpty ? 'these filters' : '"$_search"'}.'),
    };
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 112),
      children: [
        Icon(f.category == 0 && !filtered ? Icons.task_alt : Icons.search_off, size: 40, color: textFaint),
        const SizedBox(height: 12),
        Text(title, textAlign: TextAlign.center, style: text.titleMedium),
        const SizedBox(height: 4),
        Text(
          body,
          textAlign: TextAlign.center,
          style: text.bodyMedium?.copyWith(color: textMuted),
        ),
        if (f.narrows || _search.isNotEmpty) ...[
          const SizedBox(height: 16),
          Center(
            child: OutlinedButton(onPressed: _clearAll, child: const Text('Clear filters')),
          ),
        ],
      ],
    );
  }

  Widget _list(List<ActivityResult> rows, ActivityFilter f) {
    // Day totals come from the rows on screen. If the list stops at the row
    // limit, the oldest day shown may be missing rows, and says so.
    final out = <String, double>{};
    final inn = <String, double>{};
    for (final r in rows) {
      final day = r.t.txnDate;
      final map = r.t.direction == 'CR' ? inn : out;
      map[day] = (map[day] ?? 0) + r.t.amount;
    }
    final truncated = rows.length >= _maxRows;
    final lastDay = rows.last.t.txnDate;
    return ListView.builder(
      controller: _scroll,
      key: const PageStorageKey('activity'),
      // Room under the last row for the Add alert button.
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 112),
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final r = rows[i];
        final day = r.t.txnDate;
        // Day headers only make sense in date order.
        final newDay = !f.byAmount && (i == 0 || rows[i - 1].t.txnDate != day);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (newDay)
              _DayHeader(day: day, out: out[day] ?? 0, inn: inn[day] ?? 0, partial: truncated && day == lastDay),
            TxnTile(db: widget.db, row: r, showDate: f.byAmount),
          ],
        );
      },
    );
  }
}

/// A filter chip that shows its value once set: "Category ▾", or
/// "Food and cafes ✕".
class _ValueChip extends StatelessWidget {
  const _ValueChip({required this.label, required this.value, required this.onPick, required this.onClear});
  final String label;
  final String? value;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    if (value == null) {
      return ActionChip(
        label: Text(label),
        avatar: const Icon(Icons.arrow_drop_down, size: 18),
        tooltip: 'Filter by ${label.toLowerCase()}',
        onPressed: onPick,
      );
    }
    return InputChip(
      label: Text(value!),
      selected: true,
      tooltip: 'Change ${label.toLowerCase()}',
      onPressed: onPick,
      onDeleted: onClear,
      deleteButtonTooltipMessage: 'Remove ${label.toLowerCase()} filter',
    );
  }
}

/// What the list shows and its totals over every matching transaction.
class _Summary extends StatelessWidget {
  const _Summary({required this.totals, required this.shown, required this.filter, required this.search});
  final Stream<ActivityTotalsResult> totals;
  final int shown;
  final ActivityFilter filter;
  final String search;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return StreamBuilder<ActivityTotalsResult>(
      stream: totals,
      builder: (context, snap) {
        final t = snap.data;
        if (t == null || t.n == 0) return const SizedBox.shrink();
        final scope = [if (filter.narrows) filter.describe(), if (search.isNotEmpty) '"$search"'].join(' · ');
        final count = '${t.n} ${t.n == 1 ? 'transaction' : 'transactions'}';
        final cut = t.n > shown
            ? 'Showing the ${filter.byAmount ? 'largest' : 'newest'} $shown; totals cover all ${t.n}'
            : null;
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: listFill,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: glassEdge),
          ),
          child: Semantics(
            container: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  scope.isEmpty ? 'All transactions' : 'Filtered: $scope',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelMedium?.copyWith(color: textMuted),
                ),
                const SizedBox(height: 2),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 12,
                  children: [
                    Text(count, style: text.bodyMedium),
                    Text.rich(
                      TextSpan(
                        children: [
                          if (t.outTotal > 0)
                            TextSpan(
                              text: signedInr(t.outTotal, credit: false),
                              style: const TextStyle(color: debit),
                            ),
                          if (t.outTotal > 0 && t.inTotal > 0) const TextSpan(text: '   '),
                          if (t.inTotal > 0)
                            TextSpan(
                              text: signedInr(t.inTotal, credit: true),
                              style: const TextStyle(color: credit),
                            ),
                        ],
                      ),
                      style: money(text.bodyMedium)?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                if (cut != null) Text(cut, style: text.labelSmall?.copyWith(color: textFaint)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.out, required this.inn, required this.partial});
  final String day;
  final double out;
  final double inn;
  final bool partial;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final heading = dayHeading(day);
    return Semantics(
      container: true,
      header: true,
      label:
          '$heading${out > 0 ? ', ${inr(out)} out' : ''}${inn > 0 ? ', ${inr(inn)} in' : ''}'
          '${partial ? ', partial: older rows not shown' : ''}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 18, 8, 4),
        // Heading left, the day's figures right; with large text they wrap
        // under the heading instead of overflowing.
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 12,
          children: [
            Text(heading, style: text.titleSmall?.copyWith(color: teal)),
            Text.rich(
              TextSpan(
                children: [
                  if (out > 0) TextSpan(text: signedInr(out, credit: false)),
                  if (out > 0 && inn > 0) const TextSpan(text: '  '),
                  if (inn > 0)
                    TextSpan(
                      text: signedInr(inn, credit: true),
                      style: const TextStyle(color: credit),
                    ),
                  if (partial)
                    const TextSpan(
                      text: '  partial',
                      style: TextStyle(color: unsortedColor),
                    ),
                ],
              ),
              textAlign: TextAlign.right,
              style: money(text.labelMedium)?.copyWith(color: textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
