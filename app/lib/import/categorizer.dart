/// Rule-based first-pass categoriser (port of tools/categorize.py).
///
/// Rules are keyword matches on the UPI payee name / handle. Anything that
/// matches nothing returns null ("Unsorted") for the user to label.
library;

class _Rule {
  const _Rule(this.category, this.direction, this.pattern);
  final String category;
  final String? direction; // 'CR', 'DR' or null for both
  final String pattern; // regex on "NAME|VPA"
}

// Personal keywords (own and family names, account numbers) stay out of the
// repository. Build and test with
//   --dart-define-from-file=../data/personal_rules.json
// (format: personal_rules.example.json at the repo root). Without the file
// these parts match nothing and the rules still work for everything else.
const _selfTransfer = String.fromEnvironment('PP_SELF_TRANSFER');
const _family = String.fromEnvironment('PP_FAMILY');
const _college = String.fromEnvironment('PP_COLLEGE');

/// Joins rule parts, skipping empty ones; `(?!)` never matches.
String _any(List<String> parts) {
  final p = parts.where((s) => s.isNotEmpty).join('|');
  return p.isEmpty ? r'(?!)' : p;
}

final _rules = [
  _Rule('Self transfer', null, _any([_selfTransfer, 'SUPERMONEY', 'CARD REPAYMENT'])),
  _Rule('Family', null, _any([_family])),
  _Rule('Bank charges and interest', null, r'SMS CHARGES|REV:EXCESS|SBINT|INET-IMPS'),
  _Rule('Trip bookings', null, r'MAKEMYT|REDBUS|ABHIBUS|IXIGO'),
  _Rule('Local transport', null, r'^BMTC|^BANGALORE\|.*PAYU'),
  _Rule('Food and cafes', 'DR',
      r'CAFETERIA|CAFE|SWIGGY|ZOMATO|KITCHEN|HOTEL|AKASHHOT|BAKERY|GOTHAM BI|MSBONDA|TIFFIN|JUICE|TEA'),
  _Rule('Subscriptions', 'DR', r'SPOTIFY|NETFLIX|JIOSTAR|JIOHOTSTAR|GOOGLEPL'),
  _Rule('Recharge and bills', 'DR', r'JIOPREPA|AIRTEL(?!.*PAYU)|RECHARGE'),
  _Rule('Shopping', 'DR', r'AMAZON|ZUDIO|FLIPKART|MYNTRA|MEESHO'),
  _Rule('Entertainment', 'DR', r'BIGTREE|BOOKMYSHOW|PVR'),
  _Rule('College', 'DR', _any([_college])),
];

final _compiled = [for (final r in _rules) (r, RegExp(r.pattern))];

/// Category names seeded into a new database, in rule order.
final categoryNames = [for (final r in _rules) r.category];

/// Categories that move money around without being spending.
const nonSpendCategories = {'Self transfer'};

/// Payee name and VPA from a Canara statement description
/// (`UPI/DR/<ref>/NAME/BANK/VPA/...`).
(String, String) party(String desc) {
  final p = desc.split('/');
  if (p[0] == 'UPI' && p.length > 5) return (p[3].trim(), p[5].trim());
  return (desc.length > 40 ? desc.substring(0, 40) : desc, '');
}

/// Category for a payee, or null when no rule matches.
String? categorise(String name, String vpa, String direction) {
  final key = '$name|$vpa'.toUpperCase();
  for (final (rule, rx) in _compiled) {
    if (rule.direction != null && rule.direction != direction) continue;
    if (rx.hasMatch(key)) return rule.category;
  }
  return null;
}
