"""Parse Canara e-passbook text (pdftotext -layout) into transactions CSV."""
import re, sys, csv, json

src, out = sys.argv[1], sys.argv[2]
lines = open(src, encoding="utf-8", errors="replace").read().splitlines()

date_re = re.compile(r"^\s*(\d{2}-\d{2}-\d{4})\s")
amt_re = re.compile(r"(?<![\w/.])(\d[\d,]*\.\d{2})(?![\w/])")
skip_re = re.compile(r"^\s*(Date\s+Particulars|page \d+|Statement for|Customer Id|Name\s|Phone\s|Address\s)", re.I)

opening = None
txns, block = [], []
for ln in lines:
    if "Opening Balance" in ln:
        opening = float(amt_re.findall(ln)[-1].replace(",", ""))
        block = []
        continue
    if opening is None:
        continue
    if "END OF STATEMENT" in ln or ln.strip() == "DISCLAIMER":
        break
    if "Closing Balance" in ln:
        continue
    if skip_re.match(ln) or not ln.strip():
        continue
    if ln.strip().startswith("Chq:"):
        if block:
            txns.append(block)
        block = []
        continue
    block.append(ln)
if block:
    txns.append(block)

rows, bad = [], []
prev = opening
for b in txns:
    date, amts, parts = None, [], []
    for ln in b:
        m = date_re.match(ln)
        text = ln
        if m:
            date = m.group(1)
            text = ln[m.end():]
        # amounts live in the right-hand columns (col >= 45 in layout)
        left, right = text, ""
        found = [(mm.start(), mm.group(1)) for mm in amt_re.finditer(ln)]
        cols = [f for f in found if f[0] >= 40]
        if m and cols:
            amts = [float(a.replace(",", "")) for _, a in cols]
            cut = cols[0][0]
            left = ln[m.end():cut]
        elif m:
            left = ln[m.end():]
        parts.append(left.strip())
    desc = "".join(p for p in parts if p)
    if date is None or len(amts) < 2:
        bad.append(b)
        continue
    amount, bal = amts[-2], amts[-1]
    # printed balance drops the minus sign, so track a signed running balance
    if "/CR/" in desc or desc.startswith("INET-IMPS-CR"):
        direction = "CR"
    elif "/DR/" in desc:
        direction = "DR"
    else:
        direction = "CR" if abs(abs(prev + amount) - bal) < 0.01 else "DR"
    prev = round(prev + amount if direction == "CR" else prev - amount, 2)
    ok = abs(abs(prev) - bal) < 0.01
    bal = prev
    rows.append(dict(date=date, desc=desc, amount=amount, dir=direction, balance=bal, ok=ok))

with open(out, "w", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(f, fieldnames=["date", "desc", "amount", "dir", "balance", "ok"])
    w.writeheader()
    w.writerows(rows)

print(json.dumps(dict(opening=opening, n=len(rows), bad=len(bad), mismatches=sum(not r["ok"] for r in rows),
                      closing=rows[-1]["balance"] if rows else None)))
for b in bad[:5]:
    print("BAD:", b)
for r in [r for r in rows if not r["ok"]][:8]:
    print("MISMATCH:", r)
