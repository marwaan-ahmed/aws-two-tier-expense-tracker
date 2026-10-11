-- Expense tracker schema.
--
-- The app runs this file itself the first time it needs the database (see
-- ensure_schema() in app.py). Terraform never manages tables.
-- Every statement is idempotent, so running it again on every worker start is
-- harmless: IF NOT EXISTS skips what already exists and ON CONFLICT DO NOTHING
-- skips categories that are already there.

CREATE TABLE IF NOT EXISTS categories (
    id   INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS expenses (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    -- Money is NUMERIC (exact decimal), never float: 0.1 + 0.2 must equal 0.3.
    -- NUMERIC(10, 2) holds up to 99,999,999.99.
    amount      NUMERIC(10, 2) NOT NULL CHECK (amount > 0),
    category_id INTEGER NOT NULL REFERENCES categories (id),
    description VARCHAR(200) NOT NULL DEFAULT '',
    spent_on    DATE NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Both pages ask for "expenses between the 1st of this month and the 1st of
-- next month". An index on the date lets PostgreSQL jump straight to that range
-- instead of reading the whole table.
CREATE INDEX IF NOT EXISTS expenses_spent_on_idx ON expenses (spent_on);

INSERT INTO categories (name)
VALUES ('Food'), ('Transport'), ('Bills'), ('Entertainment'), ('Shopping'), ('Other')
ON CONFLICT (name) DO NOTHING;
