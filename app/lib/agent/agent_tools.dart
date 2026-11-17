import 'package:drift/drift.dart';

import '../data/database.dart';

/// A tool the assistant can call: what the model reads, and what runs.
class AgentTool {
  const AgentTool(this.name, this.description, this.parameters);
  final String name;
  final String description;
  final Map<String, Object?> parameters; // JSON Schema
}

/// Read-only tools over the local database. Every number the assistant
/// reports comes from these queries; the model only chooses and explains.
/// Results are kept small: on-device models have a short context.
class AgentTools {
  AgentTools(this.db);
  final AppDatabase db;

  static const _period = {
    'from': {'type': 'string', 'description': 'First day, YYYY-MM-DD. Omit for no lower bound.'},
    'to': {'type': 'string', 'description': 'Last day, YYYY-MM-DD, inclusive. Omit for no upper bound.'},
  };

  static const tools = [
    AgentTool(
      'spending_summary',
      'Total money spent or received in a period, broken down by category, payee, account, month or day. '
          'Use for questions like "how much did I spend on food in October" or "where did my money go".',
      {
        'type': 'object',
        'properties': {
          ..._period,
          'group_by': {
            'type': 'string',
            'enum': ['category', 'payee', 'account', 'month', 'day'],
            'description': 'How to break the total down. Default category.',
          },
          'direction': {
            'type': 'string',
            'enum': ['spent', 'received'],
            'description': 'Money out (spent) or in (received). Default spent.',
          },
          'category': {'type': 'string', 'description': 'Only this category, e.g. "Food and cafes" or "Unsorted".'},
        },
      },
    ),
    AgentTool(
      'list_transactions',
      'Individual transactions matching filters, newest or largest first (at most 20). '
          'Use to show examples or find specific payments.',
      {
        'type': 'object',
        'properties': {
          ..._period,
          'category': {'type': 'string', 'description': 'Category name, or "Unsorted".'},
          'payee': {'type': 'string', 'description': 'Part of the payee name.'},
          'direction': {'type': 'string', 'enum': ['spent', 'received']},
          'min_amount': {'type': 'number', 'description': 'Smallest amount in rupees.'},
          'max_amount': {'type': 'number', 'description': 'Largest amount in rupees.'},
          'sort': {'type': 'string', 'enum': ['newest', 'largest'], 'description': 'Default newest.'},
          'limit': {'type': 'integer', 'description': 'How many, 1 to 20. Default 10.'},
        },
      },
    ),
    AgentTool(
      'payee_history',
      'Everything about one payee: total paid and received, number of payments, first and last date, '
          'usual category and the latest payments.',
      {
        'type': 'object',
        'properties': {
          'payee': {'type': 'string', 'description': 'Part of the payee name.'},
        },
        'required': ['payee'],
      },
    ),
    AgentTool(
      'list_categories',
      'The categories in use, and whether each counts as spending.',
      {'type': 'object', 'properties': {}},
    ),
  ];

  /// Runs a tool. Problems come back as {"error": ...} so the model can
  /// recover; a tool never throws.
  Future<Map<String, Object?>> run(String name, Map<String, Object?> args) async {
    try {
      return switch (name) {
        'spending_summary' => await _spendingSummary(args),
        'list_transactions' => await _listTransactions(args),
        'payee_history' => await _payeeHistory(args),
        'list_categories' => await _listCategories(),
        _ => {'error': 'unknown tool $name'},
      };
    } on _BadArgument catch (e) {
      return {'error': e.message};
    }
  }

  // Shared WHERE pieces. Spending leaves out categories that do not count as
  // spending (self transfers), like the Home screen does.
  static const _from = '''
    FROM transactions t
      INNER JOIN accounts a ON a.id = t.account_id
      LEFT JOIN payees p ON p.id = t.payee_id
      LEFT JOIN categories c ON c.id = t.category_id''';

  ({List<String> where, List<Variable> vars}) _filters(Map<String, Object?> args, {bool spendOnly = true}) {
    final where = <String>[];
    final vars = <Variable>[];
    final from = _date(args['from'], 'from'), to = _date(args['to'], 'to');
    if (from != null) {
      where.add('t.txn_date >= ?');
      vars.add(Variable.withString(from));
    }
    if (to != null) {
      where.add('t.txn_date <= ?');
      vars.add(Variable.withString(to));
    }
    final direction = args['direction'] as String? ?? 'spent';
    if (direction != 'spent' && direction != 'received') throw _BadArgument('direction must be spent or received');
    where.add('t.direction = ?');
    vars.add(Variable.withString(direction == 'spent' ? 'DR' : 'CR'));
    if (spendOnly) where.add('(c.id IS NULL OR c.counts_as_spend)');
    final category = (args['category'] as String?)?.trim();
    if (category != null && category.isNotEmpty) {
      if (category.toLowerCase() == 'unsorted') {
        where.add('t.category_id IS NULL');
      } else {
        where.add('lower(c.name) = lower(?)');
        vars.add(Variable.withString(category));
      }
    }
    final payee = (args['payee'] as String?)?.trim();
    if (payee != null && payee.isNotEmpty) {
      where.add("(p.raw_name LIKE '%' || ? || '%' OR p.display_name LIKE '%' || ? || '%')");
      vars
        ..add(Variable.withString(payee))
        ..add(Variable.withString(payee));
    }
    for (final (key, op) in [('min_amount', '>='), ('max_amount', '<=')]) {
      final v = args[key];
      if (v == null) continue;
      if (v is! num) throw _BadArgument('$key must be a number');
      where.add('t.amount $op ?');
      vars.add(Variable.withReal(v.toDouble()));
    }
    return (where: where, vars: vars);
  }

  Future<Map<String, Object?>> _spendingSummary(Map<String, Object?> args) async {
    final groupBy = args['group_by'] as String? ?? 'category';
    final key = switch (groupBy) {
      'category' => "COALESCE(c.name, 'Unsorted')",
      'payee' => "COALESCE(p.display_name, p.raw_name, 'Unknown')",
      'account' => 'a.name',
      'month' => 'substr(t.txn_date, 1, 7)',
      'day' => 't.txn_date',
      _ => throw _BadArgument('group_by must be category, payee, account, month or day'),
    };
    final f = _filters(args);
    // `grp`, not `name`: accounts and categories both have a name column.
    final order = groupBy == 'month' || groupBy == 'day' ? 'grp' : 'amount DESC';
    final rows = await db.customSelect(
      'SELECT $key AS grp, SUM(t.amount) AS amount, COUNT(*) AS n $_from '
      'WHERE ${f.where.join(' AND ')} GROUP BY grp ORDER BY $order LIMIT 31',
      variables: f.vars,
    ).get();
    final groups = [
      for (final r in rows)
        {'name': r.read<String>('grp'), 'amount': _rupees(r.read<double>('amount')), 'payments': r.read<int>('n')},
    ];
    final total = rows.fold<double>(0, (s, r) => s + r.read<double>('amount'));
    final count = rows.fold<int>(0, (s, r) => s + r.read<int>('n'));
    return {
      'from': args['from'] ?? 'beginning',
      'to': args['to'] ?? 'today',
      'direction': args['direction'] ?? 'spent',
      'total': _rupees(total),
      'payments': count,
      'by_$groupBy': groups,
      if (rows.length == 31) 'note': 'only the first 31 groups are listed',
    };
  }

  Future<Map<String, Object?>> _listTransactions(Map<String, Object?> args) async {
    final f = _filters(args, spendOnly: false);
    final limit = ((args['limit'] as num?) ?? 10).toInt().clamp(1, 20);
    final order = args['sort'] == 'largest' ? 't.amount DESC' : 't.txn_date DESC, t.txn_time DESC';
    final rows = await db.customSelect(
      "SELECT t.txn_date AS date, t.txn_time AS time, COALESCE(p.display_name, p.raw_name, 'Unknown') AS payee, "
      "t.amount AS amount, COALESCE(c.name, 'Unsorted') AS category, a.name AS account $_from "
      'WHERE ${f.where.join(' AND ')} ORDER BY $order LIMIT $limit',
      variables: f.vars,
    ).get();
    return {
      'transactions': [
        for (final r in rows)
          {
            'date': r.read<String>('date'),
            if (r.readNullable<String>('time') != null) 'time': r.read<String>('time').substring(0, 5),
            'payee': r.read<String>('payee'),
            'amount': _rupees(r.read<double>('amount')),
            'category': r.read<String>('category'),
            'account': r.read<String>('account'),
          },
      ],
    };
  }

  Future<Map<String, Object?>> _payeeHistory(Map<String, Object?> args) async {
    final payee = (args['payee'] as String?)?.trim() ?? '';
    if (payee.isEmpty) throw _BadArgument('payee is required');
    final match = "(p.raw_name LIKE '%' || ?1 || '%' OR p.display_name LIKE '%' || ?1 || '%')";
    final summary = await db.customSelect(
      "SELECT COUNT(*) AS n, MIN(t.txn_date) AS first, MAX(t.txn_date) AS last, "
      "COALESCE(SUM(CASE WHEN t.direction = 'DR' THEN t.amount END), 0) AS paid, "
      "COALESCE(SUM(CASE WHEN t.direction = 'CR' THEN t.amount END), 0) AS received, "
      'COUNT(DISTINCT p.id) AS payees $_from WHERE $match',
      variables: [Variable.withString(payee)],
    ).getSingle();
    if (summary.read<int>('n') == 0) return {'error': 'no payee matches "$payee"'};
    final usual = await db.customSelect(
      "SELECT COALESCE(c.name, 'Unsorted') AS grp, COUNT(*) AS n $_from WHERE $match "
      'GROUP BY grp ORDER BY n DESC LIMIT 1',
      variables: [Variable.withString(payee)],
    ).getSingle();
    final latest = await db.customSelect(
      "SELECT t.txn_date AS date, t.direction AS dir, t.amount AS amount, "
      "COALESCE(p.display_name, p.raw_name) AS payee $_from WHERE $match "
      'ORDER BY t.txn_date DESC, t.txn_time DESC LIMIT 5',
      variables: [Variable.withString(payee)],
    ).get();
    return {
      'payee_search': payee,
      'matching_payees': summary.read<int>('payees'),
      'payments': summary.read<int>('n'),
      'total_paid': _rupees(summary.read<double>('paid')),
      'total_received': _rupees(summary.read<double>('received')),
      'first_date': summary.read<String>('first'),
      'last_date': summary.read<String>('last'),
      'usual_category': usual.read<String>('grp'),
      'latest': [
        for (final r in latest)
          {
            'date': r.read<String>('date'),
            'payee': r.read<String>('payee'),
            'amount': _rupees(r.read<double>('amount')),
            'direction': r.read<String>('dir') == 'DR' ? 'paid' : 'received',
          },
      ],
    };
  }

  Future<Map<String, Object?>> _listCategories() async {
    final cats = await (db.select(db.categories)..orderBy([(c) => OrderingTerm.asc(c.name)])).get();
    return {
      'categories': [
        for (final c in cats) {'name': c.name, 'counts_as_spending': c.countsAsSpend},
        {'name': 'Unsorted', 'counts_as_spending': true},
      ],
    };
  }

  static final _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  String? _date(Object? v, String name) {
    if (v == null || (v is String && v.trim().isEmpty)) return null;
    if (v is String && _isoDate.hasMatch(v.trim())) return v.trim();
    throw _BadArgument('$name must be a date like 2026-10-31');
  }

  static num _rupees(double v) {
    final r = (v * 100).round() / 100;
    return r == r.roundToDouble() ? r.round() : r;
  }
}

class _BadArgument implements Exception {
  _BadArgument(this.message);
  final String message;
}
