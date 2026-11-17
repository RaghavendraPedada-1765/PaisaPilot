-- PaisaPilot local database (SQLite). All data stays on the device.
CREATE TABLE accounts (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,              -- e.g. "Canara savings"
  kind TEXT NOT NULL CHECK (kind IN ('bank','credit_card','wallet')),
  masked_number TEXT,              -- last digits only, as shown in alerts
  hidden INTEGER NOT NULL DEFAULT 0 -- excluded from shared reports/exports
);
CREATE TABLE categories (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  counts_as_spend INTEGER NOT NULL DEFAULT 1  -- 0 for self transfers, pass-through
);
CREATE TABLE payees (
  id INTEGER PRIMARY KEY,
  raw_name TEXT NOT NULL,          -- as it appears in statement/SMS
  vpa TEXT,
  display_name TEXT,               -- user's label
  default_category_id INTEGER REFERENCES categories(id),
  UNIQUE (raw_name, vpa)
);
CREATE TABLE transactions (
  id INTEGER PRIMARY KEY,
  account_id INTEGER NOT NULL REFERENCES accounts(id),
  txn_date TEXT NOT NULL,          -- ISO date
  txn_time TEXT,
  direction TEXT NOT NULL CHECK (direction IN ('CR','DR')),
  amount REAL NOT NULL,
  balance_after REAL,
  payee_id INTEGER REFERENCES payees(id),
  category_id INTEGER REFERENCES categories(id),
  category_source TEXT CHECK (category_source IN ('rule','model','user')),
  upi_ref TEXT,                    -- used to de-duplicate SMS vs statement
  source TEXT NOT NULL CHECK (source IN ('sms','statement','manual')),
  pass_through_group INTEGER,      -- links money received and forwarded on
  raw_text TEXT,
  UNIQUE (account_id, upi_ref, direction)
);
CREATE TABLE budgets (
  id INTEGER PRIMARY KEY,
  category_id INTEGER REFERENCES categories(id), -- NULL = overall
  month TEXT NOT NULL,             -- YYYY-MM
  limit_amount REAL NOT NULL
);
CREATE TABLE dues (
  id INTEGER PRIMARY KEY,
  account_id INTEGER NOT NULL REFERENCES accounts(id),
  outstanding REAL NOT NULL,
  due_date TEXT NOT NULL,
  fees_paid REAL NOT NULL DEFAULT 0
);
CREATE TABLE attachments (        -- photos the user keeps with a transaction
  id INTEGER PRIMARY KEY,
  txn_id INTEGER NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
  file_name TEXT NOT NULL,         -- inside the app's private photos folder
  added_at TEXT NOT NULL           -- ISO timestamp
);
CREATE INDEX idx_attachment_txn ON attachments(txn_id);
CREATE TABLE settings (           -- small app state, e.g. last SMS sync
  name TEXT NOT NULL PRIMARY KEY,
  value TEXT NOT NULL
);
CREATE INDEX idx_txn_date ON transactions(txn_date);
CREATE INDEX idx_txn_category ON transactions(category_id);
