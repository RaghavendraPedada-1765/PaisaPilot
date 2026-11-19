/// SMS parser for bank / UPI / card / wallet alerts (started as a port of
/// tools/sms_parser.py).
///
/// Each pattern is built from real alert wording; formats were checked
/// against the counts of matching messages in Raghav's inbox. [parseSms]
/// returns null for non-transaction messages (OTPs, promos, money requests,
/// mandate reminders).
library;

class SmsTxn {
  const SmsTxn({
    required this.source,
    required this.direction,
    required this.amount,
    required this.date,
    required this.account,
    required this.party,
    this.time,
    this.ref,
    this.balance,
  });

  final String source; // canara, icici, slice (card), slicebank (savings), cgg, fampay
  final String direction; // CR or DR
  final double amount;
  final String? date; // ISO date, null if unparseable
  final String? time; // HH:MM:SS when the alert has one
  final String account; // masked, e.g. XXX321, or the wallet name
  final String party; // empty when the alert does not name one
  final String? ref; // UPI ref / RRN
  final double? balance;
}

class _Pattern {
  const _Pattern(this.source, this.direction, this.regex, {this.dayFirst = true, this.account, this.party});
  final String source;
  final String? direction; // null: read from the `dir` group (debited / credited)
  final RegExp regex;
  final bool dayFirst; // false for m/d/y dates
  final String? account; // for alerts that carry no account number
  final String? party; // for alerts that name no counterparty
}

// Adjacent literals: raw strings keep the regex readable, '$x' splices in parts.
String _amt(String name) => r'(?:INR|Rs\.?|₹)\s*(?<' '$name' r'>-?[\d,]+(?:\.\d{1,2})?)';

final _amount = _amt('amount');
final _bal = _amt('bal');

final _patterns = [
  // Canara credit (older format)
  _Pattern('canara', 'CR', RegExp(
      r'Acct (?<acct>X+\d+) credited with ' '$_amount' r' on (?<date>\d{2}/\d{2}/\d{2}) '
      r'from (?<party>[^;]+); UPI:\s*(?<ref>\d+); Bal ' '$_bal')),
  // Canara debit (older format)
  _Pattern('canara', 'DR', RegExp(
      r'Acct (?<acct>X+\d+) Dr\. ' '$_amount' r' on (?<date>\d{2}/\d{2}/\d{2}) '
      r'to (?<party>[^;]+); UPI:\s*(?<ref>\d+); Bal ' '$_bal')),
  // Canara UPI payment: "Rs.40.00 paid thru A/C XX1234 on 22-10-26 13:05:09 to NAME, UPI Ref 1234..."
  _Pattern('canara', 'DR', RegExp(
      '$_amount' r' paid thru A/C (?<acct>X+\d+) on (?<date>\d{1,2}-\d{1,2}-\d{2}) '
      r'(?<time>\d{1,2}:\d{2}:\d{2}) to (?<party>.+?),? UPI Ref (?<ref>\d+)')),
  // Canara UPI credit, month first: "Your a/c no. XX1234 has been credited with Rs.300.00 on
  // 9/14/26 7:05 PM from a/c no. XX9876 (UPI Ref no 1234...)"
  _Pattern('canara', 'CR', RegExp(
      r'Your a/c no\. (?<acct>X+\d+) has been credited with ' '$_amount' r' on '
      r'(?<date>\d{1,2}/\d{1,2}/\d{2}) (?<time>\d{1,2}:\d{2} [AP]M) from (?<party>.+?) '
      r'\(UPI Ref no (?<ref>\d+)\)'), dayFirst: false),
  // Canara balance alert, no payee or ref: "An amount of INR 40.00 has been DEBITED to your
  // account XXX321 on 22/10/2026[ towards ATM / IMPS ...]. Total Avail.bal INR 1,234.00".
  // Also "Rs INR 40.00 has been credited to your account ...", and NEFT credits "An amount of
  // INR 40.00 has been credited to XXX321 on ... towards NEFT by ..., Total Avail. Bal INR ...".
  _Pattern('canara', null, RegExp(
      r'(?:An amount of|Rs\.?) ' '$_amount' r' has been (?<dir>DEBITED|CREDITED|debited|credited) to '
      r'(?:your (?:account|A/c) )?(?<acct>X+\d+) on (?<date>\d{1,2}/\d{1,2}/\d{2,4})'
      r'(?: towards (?<party>.+?))?[.,]?\s*(?:Total Avail\.\s?[Bb]al|Avl Bal) ' '$_bal')),
  // "Your a/c XXX321 CREDITED with INR 40.00 on 14/11/2026. Avl.Bal INR 1,234.00. - Canara Bank"
  _Pattern('canara', null, RegExp(
      r'Your a/c (?<acct>X+\d+) (?<dir>CREDITED|DEBITED) with ' '$_amount' r' on '
      r'(?<date>\d{1,2}/\d{1,2}/\d{2,4})\.\s*\S+\s*' '$_bal')),
  // Canara UPI reversal, month first: "Your a/c no. XX4321is credited for Rs.250.00 on 9/14/26
  // 7:05 PM for reversal of transaction (UPI Ref no 1234...)". The ref is the failed payment's.
  _Pattern('canara', 'CR', RegExp(
      r'Your a/c no\. (?<acct>X+\d+)\s*is credited for ' '$_amount' r' on '
      r'(?<date>\d{1,2}/\d{1,2}/\d{2}) (?<time>\d{1,2}:\d{2} [AP]M) for reversal of transaction '
      r'\(UPI Ref no (?<ref>\d+)\)'), dayFirst: false, party: 'UPI reversal'),
  // Canara debit card at a shop (POS) or ATM, three wordings (spacing varies, so \s+):
  //   "A/C XXX321 linked to card XX9876 debited Rs 40.00 on 14/11/2026 POS SHOP txn. Avl Bal is Rs 1,234.00"
  //   "A/C XXX321 linked to card debited Rs INR 40.00 on 14/11/26 POS SHOP Bal is Rs INR 1,234.00"
  //   "A/c XXX321 linked to card debited INR 40.00 on 14/11/26 POS txn. Avl Bal INR 1,234.00"
  _Pattern('canara', 'DR', RegExp(
      r'A/[Cc]\s+(?<acct>X+\d+)\s+linked to card\s+(?:X+\d+\s+)?debited\s+(?:Rs\s+)?' '$_amount' r'\s+on\s+'
      r'(?<date>\d{2}/\d{2}/\d{2,4})\s+(?<party>.+?)(?:\s+txn)?\.?\s*(?:Avl\s+)?Bal(?:\s+is)?\s+(?:Rs\s+)?'
      '$_bal')),
  // India Post savings: "Account No. XXXX1234 CREDIT with amount Rs. 500.00 on 14-11-2026.
  // Bal: Rs.1234.00."
  _Pattern('indiapost', null, RegExp(
      r'Account No\.?\s*(?<acct>X+\d+)\s+(?<dir>CREDIT|DEBIT)\s+with amount\s+' '$_amount' r'\s+on\s+'
      r'(?<date>\d{2}-\d{2}-\d{4})\.?\s*\S+:?\s*' '$_bal')),
  // ICICI credit
  _Pattern('icici', 'CR', RegExp(
      r'Acct (?<acct>X+\d+) is credited with ' '$_amount' r' on (?<date>\d{2}-[A-Za-z]{3}-\d{2}) '
      r'from (?<party>.+?)\. UPI:\s*(?<ref>\d+)')),
  // ICICI salary (NEFT) credit: "ICICI Bank Acc XX456 is credited with salary of Rs. 25,000.00 on
  // 06-Nov-26. Info: NEFT*ACME. Avl Bal Rs. 25,300.00."
  _Pattern('icici', 'CR', RegExp(
      r'ICICI Bank Acc(?:t)? (?<acct>X+\d+) is credited with (?:salary of )?' '$_amount' r' on '
      r'(?<date>\d{2}-[A-Za-z]{3}-\d{2})\.\s*Info:\s*(?<party>[^.]+)\..*?Avl Bal ' '$_bal')),
  // ICICI debit (UPI / AutoPay)
  _Pattern('icici', 'DR', RegExp(
      '$_amount' r' successfully debited from ICICI Bank (?<acct>X+\d+) on '
      r'(?<date>\d{2}-[A-Za-z]{3}-\d{2}) towards (?<party>.+?) via .*?RRN:\s*(?<ref>\d+)')),
  // ICICI UPI debit: "ICICI Bank Acct XX456 debited for Rs 40.00 on 14-Nov-26; NAME credited. UPI:1234..."
  _Pattern('icici', 'DR', RegExp(
      r'ICICI Bank Acct (?<acct>X+\d+) debited for ' '$_amount' r' on '
      r'(?<date>\d{2}-[A-Za-z]{3}-\d{2}); (?<party>.+?) credited\.(?:\s*UPI:\s*(?<ref>\d+))?')),
  // slice credit card spend
  _Pattern('slice', 'DR', RegExp(
      '$_amount' r' spent on your credit card (?<acct>x+\d+) at (?<party>.+?) on '
      r'(?<date>\d{2}-[A-Za-z]{3}-\d{2})',
      caseSensitive: false)),
  // slice credit card used for UPI (email): "₹40 spent on your slice credit card xx7890 via UPI.
  // Transaction date 18-Nov-26 To NAME RRN 1234..."
  _Pattern('slice', 'DR', RegExp(
      '$_amount' r' spent on your slice credit card (?<acct>x+\d+) via UPI\. Transaction date '
      r'(?<date>\d{1,2}-[A-Za-z]{3}-\d{2,4}) To (?<party>.+?) RRN (?<ref>\d+)',
      caseSensitive: false)),
  // slice credit card repayment (SMS and email name no card number)
  _Pattern('slice', 'CR', RegExp(
      r'(?:\w+ of|received your repayment of) ' '$_amount' r' (?:received )?for the slice credit card'),
      account: '', party: 'slice credit card repayment'),
  // slice savings account, from email: "₹40 debited from your slice account xx1234 via UPI.
  // Transaction date 14-Nov-26 To NAME RRN 1234..."
  _Pattern('slicebank', 'DR', RegExp(
      '$_amount' r' debited from your slice (?:bank )?account (?<acct>xx\d+) via UPI\. Transaction date '
      r'(?<date>\d{1,2}-[A-Za-z]{3}-\d{2,4}) To (?<party>.+?) RRN (?<ref>\d+)',
      caseSensitive: false)),
  // "You have received ₹300 via UPI in your slice bank account xx1234. ... Transaction date
  // 14-Nov-26 From NAME RRN 1234..."
  _Pattern('slicebank', 'CR', RegExp(
      r'You have received ' '$_amount' r' via UPI in your slice bank account (?<acct>xx\d+)\..*?'
      r'Transaction date (?<date>\d{1,2}-[A-Za-z]{3}-\d{2,4}) From (?<party>.+?) RRN (?<ref>\d+)',
      caseSensitive: false)),
  // "You have received ₹300 in your slice bank a/c xx1234. ... Transaction Date 14-Nov-26
  // SOURCE Ref No. 1234..."
  _Pattern('slicebank', 'CR', RegExp(
      r'You have received ' '$_amount' r' in your slice bank a/c (?<acct>xx\d+)\..*?'
      r'Transaction Date (?<date>\d{1,2}-[A-Za-z]{3}-\d{2,4}) (?<party>.+?) Ref No\. (?<ref>\d+)',
      caseSensitive: false)),
  // CGG Bank: "Dear Customer, An amount of Rs.500 is Credited in Acct XXX1234 on 14-11-2026.
  // Available Balance Rs.1234.00"
  _Pattern('cgg', null, RegExp(
      r'amount of ' '$_amount' r' is (?<dir>credited|debited) in Acct (?<acct>X+\d+) on '
      r'(?<date>\d{2}-\d{2}-\d{4})\.\s*Available Balance:?\s*(?:is\s*)?' '$_bal',
      caseSensitive: false)),
  // FamPay wallet: "You received Rs.150.0 from NAME with txn ..."
  _Pattern('fampay', 'CR', RegExp(
      r'You received ' '$_amount' r' from (?<party>.+?) with txn'), account: 'FamPay'),
  // "Rs 150.0 was credited to your account with transaction ID ABC123. ..."
  _Pattern('fampay', 'CR', RegExp(
      '$_amount' r' was credited to your account with transaction'), account: 'FamPay', party: ''),
  // "You were charged Rs. 49.0 for your new higher deposit limits on FamPay"
  _Pattern('fampay', 'DR', RegExp(
      r'You were charged ' '$_amount' r' for your new higher deposit limits'),
      account: 'FamPay', party: 'FamPay charges'),
];

final _otp = RegExp(r'\bOTP\b');
const _months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];

double? _num(String? s) => s == null ? null : double.parse(s.replaceAll(',', ''));
String _two(int n) => n.toString().padLeft(2, '0');

/// `dd/mm/yy`, `d-m-yy`, `dd/mm/yyyy` or `dd-Mon-yy` to ISO, with Python's %y
/// century rule. For month-first dates a first field above 12 means the bank
/// wrote day first after all.
String? _date(String s, {bool dayFirst = true}) {
  final parts = s.split(RegExp('[/-]'));
  if (parts.length != 3) return null;
  var a = int.tryParse(parts[0]);
  var b = int.tryParse(parts[1]) ?? _months.indexOf(parts[1].toLowerCase()) + 1;
  final y = int.tryParse(parts[2]);
  if (a == null || y == null) return null;
  if (!dayFirst && a <= 12) (a, b) = (b, a);
  final (day, month) = (a, b);
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final year = parts[2].length == 4 ? y : (y < 69 ? 2000 + y : 1900 + y);
  return '$year-${_two(month)}-${_two(day)}';
}

/// `13:05:09` or `7:05 PM` to `HH:MM:SS`.
String? _time(String? s) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?(?: ([AP])M)?$').firstMatch(s ?? '');
  if (m == null) return null;
  var h = int.parse(m.group(1)!);
  if (m.group(4) == 'P' && h < 12) h += 12;
  if (m.group(4) == 'A' && h == 12) h = 0;
  return '${_two(h)}:${m.group(2)}:${m.group(3) ?? '00'}';
}

SmsTxn? parseSms(String text) {
  if (_otp.hasMatch(text)) return null;
  for (final p in _patterns) {
    final m = p.regex.firstMatch(text);
    if (m == null) continue;
    String? group(String name) => m.groupNames.contains(name) ? m.namedGroup(name) : null;
    return SmsTxn(
      source: p.source,
      direction: p.direction ?? (group('dir')!.toUpperCase().startsWith('CREDIT') ? 'CR' : 'DR'),
      amount: _num(group('amount'))!,
      date: group('date') == null ? null : _date(group('date')!, dayFirst: p.dayFirst),
      time: _time(group('time')),
      account: group('acct') ?? p.account!,
      party: group('party')?.trim() ?? p.party ?? '',
      ref: group('ref'),
      balance: _num(group('bal')),
    );
  }
  return null;
}
