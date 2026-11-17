"""Rule-based first-pass categoriser for parsed Canara transactions.

Usage: python categorize.py txns.csv categorised.csv
Rules are keyword matches on the UPI payee name / handle. Anything that
matches nothing is left as 'Unsorted' for the user to label in the app.
"""
import csv, sys, re, json, collections, pathlib

# Personal keywords (own and family names, account numbers) stay out of the
# repository, in the git-ignored data/personal_rules.json (format:
# personal_rules.example.json). The Flutter app reads the same file.
_personal_file = pathlib.Path(__file__).resolve().parent.parent / "data" / "personal_rules.json"
PERSONAL = json.loads(_personal_file.read_text(encoding="utf-8")) if _personal_file.exists() else {}


def _any(*parts):
    """Joins rule parts, skipping empty ones; (?!) never matches."""
    return "|".join(p for p in parts if p) or r"(?!)"


RULES = [
    # (category, direction or None, regex on "NAME|VPA")
    ("Self transfer", None, _any(PERSONAL.get("PP_SELF_TRANSFER"), "SUPERMONEY")),
    ("Family", None, _any(PERSONAL.get("PP_FAMILY"))),
    ("Bank charges and interest", None, r"SMS CHARGES|REV:EXCESS|SBINT|INET-IMPS"),
    ("Trip bookings", None, r"MAKEMYT|REDBUS|ABHIBUS|IXIGO"),
    ("Local transport", None, r"^BMTC|^BANGALORE\|.*PAYU"),
    ("Food and cafes", "DR", r"CAFETERIA|CAFE|SWIGGY|ZOMATO|KITCHEN|HOTEL|AKASHHOT|BAKERY|GOTHAM BI|MSBONDA|TIFFIN|JUICE|TEA"),
    ("Subscriptions", "DR", r"SPOTIFY|NETFLIX|JIOSTAR|JIOHOTSTAR|GOOGLEPL"),
    ("Recharge and bills", "DR", r"JIOPREPA|AIRTEL(?!.*PAYU)|RECHARGE"),
    ("Shopping", "DR", r"AMAZON|ZUDIO|FLIPKART|MYNTRA|MEESHO"),
    ("Entertainment", "DR", r"BIGTREE|BOOKMYSHOW|PVR"),
    ("College", "DR", _any(PERSONAL.get("PP_COLLEGE"))),
]


def party(desc):
    p = desc.split("/")
    if p[0] == "UPI" and len(p) > 5:
        return p[3].strip(), p[5].strip()
    return desc[:40], ""


def categorise(desc, direction):
    name, vpa = party(desc)
    key = f"{name}|{vpa}".upper()
    for cat, d, rx in RULES:
        if d and d != direction:
            continue
        if re.search(rx, key):
            return cat
    return "Unsorted"


if __name__ == "__main__":
    src, out = sys.argv[1], sys.argv[2]
    rows = list(csv.DictReader(open(src, encoding="utf-8")))
    for r in rows:
        r["payee"], r["vpa"] = party(r["desc"])
        r["category"] = categorise(r["desc"], r["dir"])
    fields = ["date", "dir", "amount", "balance", "payee", "vpa", "category", "desc"]
    with open(out, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)
    agg = collections.defaultdict(lambda: [0.0, 0])
    for r in rows:
        k = (r["category"], r["dir"])
        agg[k][0] += float(r["amount"])
        agg[k][1] += 1
    for k, v in sorted(agg.items(), key=lambda kv: -kv[1][0]):
        print(f"{v[0]:>10.2f} {v[1]:>4}  {k[1]}  {k[0]}")
