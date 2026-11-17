import 'package:flutter/material.dart';

import '../data/database.dart';
import 'format.dart';
import 'theme.dart';
import 'txn_tile.dart';

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key, required this.db});
  final AppDatabase db;

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  String? _direction; // null = all, 'DR' = spent, 'CR' = received
  String _search = '';
  var _byAmount = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Category>>(
      stream: widget.db.watchCategories(),
      builder: (context, snap) {
        // Tabs: All, Unsorted (0), then each category by id.
        final tabs = <(String, int?)>[
          ('All', null),
          ('Unsorted', 0),
          for (final c in snap.data ?? const <Category>[]) (c.name, c.id),
        ];
        return DefaultTabController(
          key: ValueKey(tabs.length), // a new category means a new controller
          length: tabs.length,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: TextField(
                  onChanged: (v) => setState(() => _search = v.trim()),
                  decoration: InputDecoration(
                    hintText: 'Search payee or category',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  ),
                ),
              ),
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                indicatorColor: teal,
                labelColor: teal,
                dividerColor: Colors.transparent,
                tabs: [for (final (label, _) in tabs) Tab(text: label)],
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    for (final (label, dir) in [('All', null), ('Spent', 'DR'), ('Received', 'CR')]) ...[
                      ChoiceChip(
                        label: Text(label),
                        selected: _direction == dir,
                        onSelected: (_) => setState(() => _direction = dir),
                      ),
                      const SizedBox(width: 8),
                    ],
                    const SizedBox(width: 8),
                    FilterChip(
                      avatar: const Icon(Icons.sort, size: 18),
                      label: const Text('Largest first'),
                      selected: _byAmount,
                      onSelected: (v) => setState(() => _byAmount = v),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    for (final (_, category) in tabs)
                      _TxnList(
                        db: widget.db,
                        direction: _direction,
                        category: category,
                        search: _search,
                        byAmount: _byAmount,
                      ),
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

class _TxnList extends StatelessWidget {
  const _TxnList({
    required this.db,
    required this.direction,
    required this.category,
    required this.search,
    required this.byAmount,
  });
  final AppDatabase db;
  final String? direction;
  final int? category; // null = all, 0 = unsorted
  final String search;
  final bool byAmount;

  static const _maxRows = 500;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ActivityResult>>(
      stream: db.activity(direction, category, search, byAmount, _maxRows).watch(),
      builder: (context, snap) {
        final rows = snap.data ?? const <ActivityResult>[];
        if (snap.hasData && rows.isEmpty) {
          return Center(child: Text(category == 0 ? 'Nothing left to sort' : 'Nothing here yet'));
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
          itemCount: rows.length,
          itemBuilder: (context, i) {
            final r = rows[i];
            // Day headers only make sense in date order.
            final newDay = !byAmount && (i == 0 || rows[i - 1].t.txnDate != r.t.txnDate);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (newDay)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
                    child: Text(dayLabel(r.t.txnDate),
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(color: teal)),
                  ),
                TxnTile(db: db, row: r, showDate: byAmount),
              ],
            );
          },
        );
      },
    );
  }
}
