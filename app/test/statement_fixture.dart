// Synthetic Canara e-passbook in `pdftotext -layout` shape. Names are made up.

String _row(String date, String particulars, String amount, String balance) =>
    '${'$date  $particulars'.padRight(48)}${amount.padLeft(14)}${balance.padLeft(16)}';

String _total(String label, String amount) => '${'                         $label'.padRight(78)}$amount';

String _more(String text) => '            $text';

final statementFixture = [
  'Statement for A/c XXXXXXXX321 for the period 01-10-2026 to 31-10-2026',
  'Customer Id   123',
  _total('Opening Balance', '1,000.00'),
  'Date        Particulars                           Deposits   Withdrawals         Balance',
  _row('01-10-2026', 'UPI/CR/111111111111/ALICE', '500.00', '1,500.00'),
  _more('/SBIN/alice@okaxis/Payment//ref1/01/10/202610:15:00'),
  'Chq: ',
  // balance goes negative from here; printed figures have no minus sign
  _row('02-10-2026', 'UPI/DR/222222222222/SWIGGY', '1,700.00', '200.00'),
  _more('/YESB/swiggy@yes/UPI//ref2/02/10/202612:00:00'),
  'Chq: ',
  '\fpage 2',
  _row('03-10-2026', 'UPI/DR/333333333333/ZUDIO', '300.00', '500.00'),
  _more('/HDFC/zudio@hdfc/UPI//ref3/03/10/202618:30:00'),
  'Chq: ',
  // no /CR/ or /DR/ marker: direction comes from the balance
  _row('04-10-2026', 'SBINT FOR THE PERIOD', '5.00', '495.00'),
  'Chq: ',
  _total('Closing Balance', '495.00'),
  'END OF STATEMENT',
].join('\n');
