// Port of tools/test_sms_parser.py (samples use the real alert wording).
import 'package:flutter_test/flutter_test.dart';
import 'package:paisapilot/import/sms_parser.dart';

void main() {
  test('Canara credit', () {
    final t = parseSms('Dear Customer, Acct XXX321 credited with INR 6,600.00 on 22/10/26 '
        'from ANITA KUMAR; UPI:512300000001; Bal INR 6,665.12-CanaraBank')!;
    expect((t.source, t.direction, t.amount, t.date, t.party, t.balance),
        ('canara', 'CR', 6600.0, '2026-10-22', 'ANITA KUMAR', 6665.12));
    expect((t.account, t.ref), ('XXX321', '512300000001'));
  });

  test('Canara debit', () {
    final t = parseSms('Dear Customer, Acct XXX321 Dr. INR 6,516.00 on 22/10/26 to MAKEMYTRIP I; '
        'UPI: 512300000002; Bal INR 149.12.Not you?SMS BLOCKUPI to 9901771222-CanaraBank')!;
    expect((t.source, t.direction, t.amount, t.date, t.party, t.balance),
        ('canara', 'DR', 6516.0, '2026-10-22', 'MAKEMYTRIP I', 149.12));
  });

  test('ICICI credit', () {
    final t = parseSms('Dear Customer, Acct XX456 is credited with Rs 300.00 on 14-Nov-26 '
        'from RAVI KUMARR. UPI:512300000003-ICICI Bank.')!;
    expect((t.source, t.direction, t.amount, t.date, t.party),
        ('icici', 'CR', 300.0, '2026-11-14', 'RAVI KUMARR'));
  });

  group('more Canara wordings', () {
    test('lowercase "credited" after "Rs INR"', () {
      final t = parseSms('Rs INR 2,500.00 has been credited to your account XXX321 on 14/11/2026 towards '
          'IMPS Ref No: 51230000- 14/11/26 10:15:00. Total Avail.bal INR 3,100.00 - Canara Bank')!;
      expect((t.direction, t.amount, t.date, t.account, t.balance), ('CR', 2500.0, '2026-11-14', 'XXX321', 3100.0));
    });

    test('NEFT credit to the account number, "Total Avail. Bal"', () {
      final t = parseSms('An amount of INR 1.00 has been credited to XXX321 on 12/11/2026 towards NEFT by '
          'ACME LTD, Sender HDFC0000001, A/c XX9876, HDFC BANK, Ref N1234, Total Avail. Bal INR 51.00- Canara Bank')!;
      expect((t.direction, t.amount, t.date, t.account, t.balance), ('CR', 1.0, '2026-11-12', 'XXX321', 51.0));
      expect(t.party, startsWith('NEFT by ACME LTD'));
    });

    test('"Your a/c ... CREDITED with"', () {
      final t = parseSms('Your a/c XXX321 CREDITED with INR 75.00 on 03/11/2026. Avl.Bal INR 420.00. - Canara Bank')!;
      expect((t.direction, t.amount, t.date, t.balance), ('CR', 75.0, '2026-11-03', 420.0));
    });

    test('UPI reversal credit keeps the failed payment\'s ref', () {
      final t = parseSms('Your a/c no. XX4321is credited for Rs.250.00 on 9/14/26 7:05 PM for reversal of '
          'transaction (UPI Ref no 512300000009)-Canara Bank')!;
      expect((t.direction, t.amount, t.date, t.time, t.party, t.ref),
          ('CR', 250.0, '2026-09-14', '19:05:00', 'UPI reversal', '512300000009'));
    });

    test('debit card, "A/c", no shop name, "Avl Bal INR", double spaces', () {
      final t = parseSms('A/c XXX321  linked to card debited INR 1,250.00 on 14/11/26 POS txn. Avl Bal INR '
          '2,000.00. To stop further debit SMS BLOCK to 9999999999, call 1930 for cyber fraud. -Canara Bank')!;
      expect((t.direction, t.amount, t.date, t.party, t.balance), ('DR', 1250.0, '2026-11-14', 'POS', 2000.0));
    });

    test('debit card without the card number, "Rs INR" and a short year', () {
      final t = parseSms('A/C XXX321 linked to card debited Rs INR 1,250.00 on 14/11/26 POS TEA STALL Bal is Rs '
          'INR 2,000.00.To report fraud & stop further debit SMS BLOCK to 9999999999 - Canara Bank')!;
      expect((t.direction, t.amount, t.date, t.party, t.balance), ('DR', 1250.0, '2026-11-14', 'POS TEA STALL', 2000.0));
    });
  });

  test('slice credit card used for UPI (email)', () {
    final t = parseSms('Hi Ravi, ₹45 spent on your slice credit card xx7890 via UPI. Transaction date 18-Nov-26 '
        'To TEA STALL RRN 512300000010 Stay safe, slice safety tips')!;
    expect((t.source, t.direction, t.amount, t.date, t.account, t.party, t.ref),
        ('slice', 'DR', 45.0, '2026-11-18', 'xx7890', 'TEA STALL', '512300000010'));
  });

  test('India Post savings credit', () {
    final t = parseSms('Account No. XXXX4321 CREDIT with amount Rs. 500.00 on 14-11-2026. Bal: Rs.1234.00. [S12345]')!;
    final spaced = parseSms('Account No.  XXXX4321  CREDIT with amount  Rs. 500.00 on 14-11-2026. Bal: Rs.1234.00.')!;
    expect((spaced.amount, spaced.account), (500.0, 'XXXX4321'));
    expect((t.source, t.direction, t.amount, t.date, t.account, t.balance),
        ('indiapost', 'CR', 500.0, '2026-11-14', 'XXXX4321', 1234.0));
  });

  test('FamPay credit and deposit-limit charge', () {
    final cr = parseSms('Rs 150.0 was credited to your account with transaction ID ABC1234567. '
        'Now, your account balance is Rs 900.00 on FamPay')!;
    expect((cr.source, cr.direction, cr.amount, cr.account), ('fampay', 'CR', 150.0, 'FamPay'));
    final fee = parseSms('You were charged Rs. 49.0 for your new higher deposit limits on FamPay')!;
    expect((fee.direction, fee.amount, fee.party), ('DR', 49.0, 'FamPay charges'));
  });

  test('ICICI salary credit', () {
    final t = parseSms('ICICI Bank Acc XX456 is credited with salary of Rs. 25,000.00 on 06-Nov-26. '
        'Info: NEFT*ACME TECH PVT-. The Avl Bal Rs. 25,300.00.')!;
    expect((t.source, t.direction, t.amount, t.date, t.party, t.balance),
        ('icici', 'CR', 25000.0, '2026-11-06', 'NEFT*ACME TECH PVT-', 25300.0));
    expect((t.account, t.ref), ('XX456', null));
  });

  test('ICICI AutoPay debit', () {
    final t = parseSms('Rs 1999.00 successfully debited from ICICI Bank XX456 on 14-Nov-26 '
        'towards Google Play via UPI AutoPay mandate . RRN: 512300000004')!;
    expect((t.source, t.direction, t.amount, t.date, t.party, t.ref),
        ('icici', 'DR', 1999.0, '2026-11-14', 'Google Play', '512300000004'));
  });

  test('slice card spend', () {
    final t = parseSms('Rs. 300 spent on your credit card xx7890 at Ravi Kumar on 14-Nov-26. '
        'Not you? Call 080-4832-9999 - slice')!;
    expect((t.source, t.direction, t.amount, t.date, t.party, t.ref),
        ('slice', 'DR', 300.0, '2026-11-14', 'Ravi Kumar', null));
  });

  // Formats found in the inbox scan; names and numbers are made up.
  test('Canara UPI payment (paid thru)', () {
    final t = parseSms('Rs.40.00 paid thru A/C XX4321 on 22-1-26 13:05:09 to TEA STALL, UPI Ref 512345678901. '
        'If not done, SMS BLOCKUPI to 9901771222.-Canara Bank')!;
    expect((t.source, t.direction, t.amount, t.date, t.time, t.account, t.party, t.ref),
        ('canara', 'DR', 40.0, '2026-01-22', '13:05:09', 'XX4321', 'TEA STALL', '512345678901'));
  });

  test('Canara UPI payment without the comma before UPI Ref', () {
    final t = parseSms('Rs.120.50 paid thru A/C XX4321 on 03-11-26 09:00:01 to Some Person UPI Ref 512345678902. '
        'If not done, SMS BLOCKUPI to 9901771222.-Canara Bank')!;
    expect((t.party, t.amount, t.date), ('Some Person', 120.5, '2026-11-03'));
  });

  test('Canara UPI credit uses month-first dates and 12-hour time', () {
    final t = parseSms('Your a/c no. XX4321 has been credited with Rs.300.00 on 9/14/26 7:05 PM from a/c no. '
        'XX9876 (UPI Ref no 612345678901)-Canara Bank')!;
    expect((t.direction, t.amount, t.date, t.time, t.party, t.ref),
        ('CR', 300.0, '2026-09-14', '19:05:00', 'a/c no. XX9876', '612345678901'));
  });

  test('a month-first date whose first field is over 12 is read day first', () {
    final t = parseSms('Your a/c no. XX4321 has been credited with Rs.10.00 on 14/9/26 12:15 AM from a/c no. '
        'XX9876 (UPI Ref no 612345678902)-Canara Bank')!;
    expect((t.date, t.time), ('2026-09-14', '00:15:00'));
  });

  test('Canara balance-only alerts', () {
    final dr = parseSms('An amount of INR 1,250.00 has been DEBITED to your account XXX321 on 22/10/2026. '
        'Total Avail.bal INR 3,415.12.Dial 1930 to report cyber fraud - Canara Bank')!;
    expect((dr.direction, dr.amount, dr.date, dr.balance, dr.party, dr.ref),
        ('DR', 1250.0, '2026-10-22', 3415.12, '', null));
    final cr = parseSms('An amount of INR 500.00 has been CREDITED to your account XXX321 on 23/10/2026.'
        'Total Avail.bal INR 3,915.12.- Canara Bank')!;
    expect((cr.direction, cr.balance), ('CR', 3915.12));
    final rs = parseSms('Rs. INR 2,000.00 has been CREDITED to your A/c XXX321 on 01/11/2026. '
        'Avl Bal INR 5,915.12.-Canara Bank')!;
    expect((rs.direction, rs.amount), ('CR', 2000.0));
  });

  test('Canara balance alert with a purpose and a negative balance', () {
    final t = parseSms('An amount of INR 17.70 has been DEBITED to your account XXX321 on 20/09/2026 towards '
        'SMS service charges. Total Avail. bal INR -12.30. - Canara Bank')!;
    expect((t.party, t.amount, t.balance), ('SMS service charges', 17.7, -12.3));
    final atm = parseSms('An amount of INR 500.00 has been DEBITED to your account XXX321 on 20/09/2026 towards '
        'ATM / IMPS SOME REF Total Avail.bal INR 1,000.00. - Canara Bank')!;
    expect((atm.party, atm.balance), ('ATM / IMPS SOME REF', 1000.0));
  });

  test('Canara debit card at a shop', () {
    final t = parseSms('A/C XXX321 linked to card XXXX4321 debited Rs INR 1,299.00 on 05/11/2026 POS txn.'
        'Avl Bal is Rs INR 12,345.67.To report fraud & stop further debit SMS BLOCK to 56161- Canara Bank')!;
    expect((t.direction, t.amount, t.date, t.party, t.balance), ('DR', 1299.0, '2026-11-05', 'POS', 12345.67));
  });

  test('ICICI UPI debit', () {
    final t = parseSms('ICICI Bank Acct XX456 debited for Rs 249.00 on 10-Nov-26; SOME SHOP credited. '
        'UPI:712345678901. Call 18002662 for dispute. SMS BLOCK 118 to 9215676766.')!;
    expect((t.source, t.direction, t.amount, t.date, t.party, t.ref),
        ('icici', 'DR', 249.0, '2026-11-10', 'SOME SHOP', '712345678901'));
  });

  test('CGG Bank credit and debit', () {
    final cr = parseSms('Dear Customer, An amount of Rs.5000 is Credited in Acct XXX1234 on 14-11-2026. '
        'Available Balance Rs.7500.00 -CGGBank')!;
    expect((cr.source, cr.direction, cr.amount, cr.date, cr.account, cr.balance),
        ('cgg', 'CR', 5000.0, '2026-11-14', 'XXX1234', 7500.0));
    expect(parseSms('Dear Customer, An amount of Rs.250 is Debited in Acct XXX1234 on 15-11-2026. '
            'Available Balance Rs.7250.00 -CGGBank')!.direction, 'DR');
  });

  test('FamPay wallet credit has no account number or date', () {
    final t = parseSms('You received Rs.150.0 from Some Friend with txn ABC123. Your FamPay a/c balance is Rs.900.00')!;
    expect((t.source, t.direction, t.amount, t.account, t.party, t.date), ('fampay', 'CR', 150.0, 'FamPay', 'Some Friend', null));
  });

  // slice savings account alerts arrive by email; text is whitespace-collapsed.
  test('slice account UPI debit (email)', () {
    final t = parseSms('Hi Someone ₹40 debited from your slice account xx1234 via UPI. Transaction date 14-Nov-26 '
        'To Tea Stall RRN 812345678901 Regards Team slice Banking safety tips To talk to us, drop an email')!;
    expect((t.source, t.direction, t.amount, t.date, t.account, t.party, t.ref),
        ('slicebank', 'DR', 40.0, '2026-11-14', 'xx1234', 'Tea Stall', '812345678901'));
    final newer = parseSms('Hi Someone ₹40 debited from your slice bank account xx1234 via UPI. '
        'Transaction date 9-Oct-26 To Tea Stall 2 RRN 812345678903 Regards Team slice')!;
    expect((newer.date, newer.party, newer.ref), ('2026-10-09', 'Tea Stall 2', '812345678903'));
  });

  test('slice account credits (email)', () {
    final upi = parseSms('Hi Someone You have received ₹300 via UPI in your slice bank account xx1234. '
        'Balance ₹1,340.50 Transaction date 2-Nov-26 From Some Friend RRN 812345678902 Regards Team slice')!;
    expect((upi.direction, upi.amount, upi.date, upi.party, upi.ref), ('CR', 300.0, '2026-11-02', 'Some Friend', '812345678902'));
    final other = parseSms('Hi Someone You have received ₹25 in your slice bank a/c xx1234. Woohoo Rs. 25.0! '
        'Transaction Date 5-Nov-26 Interest borrowkyc surplus Ref No. 912345 Reach out to our customer support')!;
    expect((other.direction, other.amount, other.party, other.ref), ('CR', 25.0, 'Interest borrowkyc surplus', '912345'));
  });

  test('slice card repayment by email and by SMS', () {
    final email = parseSms('Hi Someone We received your repayment of ₹1,500 for the slice credit card. '
        'The amount has been successfully credited to your card account.')!;
    expect((email.source, email.direction, email.amount, email.account, email.party, email.date),
        ('slice', 'CR', 1500.0, '', 'slice credit card repayment', null));
    final sms = parseSms('Payment of Rs.999 received for the slice credit card. The amount has been credited to your card account - slice')!;
    expect((sms.direction, sms.amount, sms.party), ('CR', 999.0, 'slice credit card repayment'));
  });

  test('money requests and mandate reminders are ignored', () {
    expect(parseSms('Some Person has requested money on supermoney. On approving the request, Rs.50 will be debited '
        'from your account : https://example.com'), isNull);
    expect(parseSms('For the upcoming mandate set for 20-11-26, your account will be debited with Rs. 199.00 '
        'towards Some App for the subscription.'), isNull);
  });

  test('OTP is ignored', () {
    expect(parseSms('Hi, 0000 is the OTP for completing your bank transfer on slice. - slice'), isNull);
  });

  test('recharge confirmation is ignored', () {
    expect(parseSms('Recharge Successful ! Plan Name : 899.00 Jio Number : 0000000000'), isNull);
  });
}
