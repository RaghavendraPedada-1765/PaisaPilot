/// Masked outlines of alerts the parser did not recognise, for diagnosing
/// new formats without exposing the message: digits become 9, and words that
/// could be names or ids become Xx. Banking words and short lowercase words
/// stay, so the shape of the alert is still readable.
library;

const _keep = {
  'acct', 'acc', 'a/c', 'ac', 'dr', 'cr', 'inr', 'rs', 'upi', 'ref', 'bal', 'avl', 'avail', 'total', 'dear',
  'customer', 'credited', 'debited', 'from', 'to', 'on', 'your', 'account', 'via', 'rrn', 'no', 'canara',
  'canarabank', 'bank', 'icici', 'slice', 'sbi', 'hdfc', 'axis', 'kotak', 'card', 'debit', 'credit', 'pos', 'atm',
  'imps', 'neft', 'txn', 'transaction', 'amount', 'paid', 'thru', 'sms', 'otp', 'emi', 'mandate', 'autopay',
  'refund', 'reversed', 'failed', 'declined', 'spent', 'sent', 'received', 'withdrawn', 'deposited', 'transferred',
  'info', 'date', 'salary', 'payment', 'repayment', 'savings', 'wallet', 'lite',
};

final _money = RegExp(r'(?:rs\.?|inr|₹)\s*[\d,]+', caseSensitive: false);
final _moves = RegExp(r'debit|credit|paid|sent|received|spent|withdraw|deposit|transfer|refund', caseSensitive: false);

/// Mentions an amount and a movement of money.
bool looksLikeMoney(String text) => _money.hasMatch(text) && _moves.hasMatch(text);

String outline(String text) => text
    .replaceAll(RegExp(r'\d'), '9')
    .replaceAllMapped(RegExp(r'[A-Za-z][A-Za-z@._/*-]*'), (m) {
      final w = m[0]!;
      if (w.contains('@')) return 'x@x';
      if (_keep.contains(w.toLowerCase().replaceAll(RegExp(r'[.:*-]+$'), ''))) return w;
      if (w == w.toLowerCase() && w.length <= 12) return w;
      return 'Xx';
    })
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
