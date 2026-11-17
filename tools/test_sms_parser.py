"""Run: python test_sms_parser.py  (samples use the real alert wording)."""
from sms_parser import parse

CASES = [
    ("Dear Customer, Acct XXX321 credited with INR 6,600.00 on 22/10/26 from ANITA KUMAR; UPI:512300000001; Bal INR 6,665.12-CanaraBank",
     dict(source="canara", dir="CR", amount=6600.0, date="2026-10-22", party="ANITA KUMAR", balance=6665.12)),
    ("Dear Customer, Acct XXX321 Dr. INR 6,516.00 on 22/10/26 to MAKEMYTRIP I; UPI: 512300000002; Bal INR 149.12.Not you?SMS BLOCKUPI to 9901771222-CanaraBank",
     dict(source="canara", dir="DR", amount=6516.0, date="2026-10-22", party="MAKEMYTRIP I", balance=149.12)),
    ("Dear Customer, Acct XX456 is credited with Rs 300.00 on 14-Nov-26 from RAVI KUMARR. UPI:512300000003-ICICI Bank.",
     dict(source="icici", dir="CR", amount=300.0, date="2026-11-14", party="RAVI KUMARR")),
    ("Rs 1999.00 successfully debited from ICICI Bank XX456 on 14-Nov-26 towards Google Play via UPI AutoPay mandate . RRN: 512300000004",
     dict(source="icici", dir="DR", amount=1999.0, date="2026-11-14", party="Google Play")),
    ("Rs. 300 spent on your credit card xx7890 at Ravi Kumar on 14-Nov-26. Not you? Call 080-4832-9999 - slice",
     dict(source="slice", dir="DR", amount=300.0, date="2026-11-14", party="Ravi Kumar")),
    ("Hi, 0000 is the OTP for completing your bank transfer on slice. - slice", None),
    ("Recharge Successful ! Plan Name : 899.00 Jio Number : 0000000000", None),
]

fails = 0
for text, want in CASES:
    got = parse(text)
    ok = (got is None) if want is None else (got is not None and all(got[k] == v for k, v in want.items()))
    fails += not ok
    print("PASS" if ok else "FAIL", "-", text[:60], "" if ok else got)
print(f"{len(CASES) - fails}/{len(CASES)} passed")
raise SystemExit(1 if fails else 0)
