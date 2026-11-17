"""Reference SMS parser for bank / UPI / card alerts (to be ported to Dart).

Each pattern is built from real alert wording. parse(text) returns a dict
or None for non-transaction messages (OTPs, promos, recharges).
"""
import re
from datetime import datetime

def amt(name):
    return rf"(?:INR|Rs\.?)\s*(?P<{name}>[\d,]+(?:\.\d{{1,2}})?)"


AMT = amt("amount")
BAL = amt("bal")

PATTERNS = [
    # Canara credit
    ("canara", "CR", re.compile(
        rf"Acct (?P<acct>X+\d+) credited with {AMT} on (?P<date>\d{{2}}/\d{{2}}/\d{{2}}) "
        rf"from (?P<party>[^;]+); UPI:\s*(?P<ref>\d+); Bal {BAL}")),
    # Canara debit
    ("canara", "DR", re.compile(
        rf"Acct (?P<acct>X+\d+) Dr\. {AMT} on (?P<date>\d{{2}}/\d{{2}}/\d{{2}}) "
        rf"to (?P<party>[^;]+); UPI:\s*(?P<ref>\d+); Bal {BAL}")),
    # ICICI credit
    ("icici", "CR", re.compile(
        rf"Acct (?P<acct>X+\d+) is credited with {AMT} on (?P<date>\d{{2}}-[A-Za-z]{{3}}-\d{{2}}) "
        rf"from (?P<party>.+?)\. UPI:\s*(?P<ref>\d+)")),
    # ICICI debit (UPI / AutoPay)
    ("icici", "DR", re.compile(
        rf"{AMT} successfully debited from ICICI Bank (?P<acct>X+\d+) on "
        rf"(?P<date>\d{{2}}-[A-Za-z]{{3}}-\d{{2}}) towards (?P<party>.+?) via .*?RRN:\s*(?P<ref>\d+)")),
    # slice credit card spend
    ("slice", "DR", re.compile(
        rf"{AMT} spent on your credit card (?P<acct>x+\d+) at (?P<party>.+?) on "
        rf"(?P<date>\d{{2}}-[A-Za-z]{{3}}-\d{{2}})", re.I)),
]

DATE_FORMATS = ["%d/%m/%y", "%d-%b-%y"]


def _num(s):
    return float(s.replace(",", "")) if s else None


def _date(s):
    for f in DATE_FORMATS:
        try:
            return datetime.strptime(s, f).date().isoformat()
        except ValueError:
            pass
    return None


def parse(text):
    if re.search(r"\bOTP\b", text):
        return None
    for source, direction, rx in PATTERNS:
        m = rx.search(text)
        if not m:
            continue
        g = m.groupdict()
        return {
            "source": source,
            "dir": direction,
            "amount": _num(g["amount"]),
            "date": _date(g["date"]),
            "account": g["acct"],
            "party": g["party"].strip(),
            "ref": g.get("ref"),
            "balance": _num(g.get("bal")),
        }
    return None
