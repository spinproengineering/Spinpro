-- ============================================================
-- SPINPRO ENGINEERING SDN. BHD. — Portal database schema
--
-- Derived from the columns the portal actually reads and writes,
-- NOT from the older schema in SETUP.md (which was inherited and
-- disagreed with the code: po_logs.req_email vs requester_email,
-- staff_claims.staff_email vs claimant_email, supplier_* vs vendor_*).
--
-- Safe to re-run: every statement is idempotent.
-- Run in Supabase -> SQL Editor -> New query -> Run.
-- ============================================================

-- ---------- 1. Tables --------------------------------------

-- Staff directory. settings/ inserts an explicit id (Date.now()),
-- so this is a plain BIGINT, not a BIGSERIAL.
CREATE TABLE IF NOT EXISTS staff (
  id          BIGINT PRIMARY KEY,
  name        TEXT NOT NULL,
  email       TEXT UNIQUE NOT NULL,
  join_date   DATE,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- Purchase Orders (SPN-PO-YYYYMMDD-XX)
CREATE TABLE IF NOT EXISTS po_logs (
  id               BIGSERIAL PRIMARY KEY,
  po_number        TEXT UNIQUE NOT NULL,
  date             DATE,
  category         TEXT,
  supplier_name    TEXT,
  supplier_contact TEXT,
  supplier_tel     TEXT,
  project_ref      TEXT,
  delivery_address TEXT,
  remarks          TEXT,
  items            JSONB DEFAULT '[]'::jsonb,
  total            NUMERIC(12,2),
  status           TEXT DEFAULT 'Pending',
  req_email        TEXT,
  req_name         TEXT,
  approved_by      TEXT,
  approved_at      TIMESTAMPTZ,
  created_at       TIMESTAMPTZ DEFAULT NOW()
);

-- Cash Claims (SPN-CC-YYYYMMDD-XX)
CREATE TABLE IF NOT EXISTS cash_claims (
  id              BIGSERIAL PRIMARY KEY,
  claim_number    TEXT UNIQUE NOT NULL,
  submission_date DATE,
  claimant_name   TEXT,
  claimant_email  TEXT,
  claimant_nric   TEXT,
  claimant_phone  TEXT,
  payable_name    TEXT,
  bank_details    TEXT,
  project         TEXT,
  items           JSONB DEFAULT '[]'::jsonb,
  total_amount    NUMERIC(12,2),
  status          TEXT DEFAULT 'Pending',
  approved_by     TEXT,
  approved_at     TIMESTAMPTZ,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Staff Claims (SPN-SC-YYYYMMDD-XX).
-- submitted_at is a display string the app builds with
-- toLocaleString('en-GB'), so it is TEXT, not a timestamp.
CREATE TABLE IF NOT EXISTS staff_claims (
  id              BIGSERIAL PRIMARY KEY,
  claim_number    TEXT UNIQUE NOT NULL,
  staff_name      TEXT,
  staff_email     TEXT,
  submission_date DATE,
  submitted_at    TEXT,
  items           JSONB DEFAULT '[]'::jsonb,
  total_amount    NUMERIC(12,2),
  status          TEXT DEFAULT 'Pending',
  approved_by     TEXT,
  approved_at     TIMESTAMPTZ,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Leave applications (the Leave module calls this table "logs")
CREATE TABLE IF NOT EXISTS logs (
  id            BIGSERIAL PRIMARY KEY,
  email         TEXT NOT NULL,
  name          TEXT,
  leave_type    TEXT NOT NULL,
  duration      TEXT DEFAULT 'full',
  start_date    DATE NOT NULL,
  end_date      DATE NOT NULL,
  days          NUMERIC(4,1),
  reason        TEXT,
  year          INT,
  status        TEXT DEFAULT 'Pending',
  applied_at    TIMESTAMPTZ DEFAULT NOW(),
  approved_by   TEXT,
  approver_note TEXT,
  approved_at   TIMESTAMPTZ
);

-- Key/value config. Also the target of the portal keep-alive ping.
CREATE TABLE IF NOT EXISTS settings (
  key   TEXT PRIMARY KEY,
  value TEXT
);
INSERT INTO settings (key, value) VALUES ('portal', 'spinpro')
  ON CONFLICT (key) DO NOTHING;

-- Who may approve and see everything. Add rows here to grant admin;
-- this must stay in step with ADMIN_EMAILS in the HTML files, which
-- only control what the UI shows.
CREATE TABLE IF NOT EXISTS admins (
  email TEXT PRIMARY KEY
);
INSERT INTO admins (email) VALUES ('spinproengineering@gmail.com')
  ON CONFLICT (email) DO NOTHING;

-- ---------- 2. Indexes -------------------------------------

CREATE INDEX IF NOT EXISTS idx_po_req_email  ON po_logs(req_email);
CREATE INDEX IF NOT EXISTS idx_po_status     ON po_logs(status);
CREATE INDEX IF NOT EXISTS idx_cc_email      ON cash_claims(claimant_email);
CREATE INDEX IF NOT EXISTS idx_cc_status     ON cash_claims(status);
CREATE INDEX IF NOT EXISTS idx_sc_email      ON staff_claims(staff_email);
CREATE INDEX IF NOT EXISTS idx_sc_status     ON staff_claims(status);
CREATE INDEX IF NOT EXISTS idx_logs_email    ON logs(email);
CREATE INDEX IF NOT EXISTS idx_logs_year     ON logs(year);
CREATE INDEX IF NOT EXISTS idx_logs_status   ON logs(status);

-- ---------- 3. Helpers -------------------------------------

-- The signed-in user's email, straight from the verified JWT.
CREATE OR REPLACE FUNCTION portal_email() RETURNS TEXT
LANGUAGE sql STABLE AS $$
  SELECT lower(coalesce(auth.jwt() ->> 'email', ''));
$$;

CREATE OR REPLACE FUNCTION is_portal_admin() RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM admins WHERE lower(email) = portal_email());
$$;

-- ---------- 4. Row Level Security --------------------------
-- The repository is PUBLIC and the anon key ships to every browser,
-- so these policies -- not the key -- are what protect the data.

ALTER TABLE staff        ENABLE ROW LEVEL SECURITY;
ALTER TABLE po_logs      ENABLE ROW LEVEL SECURITY;
ALTER TABLE cash_claims  ENABLE ROW LEVEL SECURITY;
ALTER TABLE staff_claims ENABLE ROW LEVEL SECURITY;
ALTER TABLE logs         ENABLE ROW LEVEL SECURITY;
ALTER TABLE settings     ENABLE ROW LEVEL SECURITY;
ALTER TABLE admins       ENABLE ROW LEVEL SECURITY;

-- settings: readable without a session, because index.html pings it
-- before login (keepAlive) and so does the hourly GitHub Action.
-- Keep non-sensitive values only. Writes are admin-only.
DROP POLICY IF EXISTS settings_read   ON settings;
DROP POLICY IF EXISTS settings_write  ON settings;
CREATE POLICY settings_read  ON settings FOR SELECT USING (true);
CREATE POLICY settings_write ON settings FOR ALL
  USING (is_portal_admin()) WITH CHECK (is_portal_admin());

-- admins: a signed-in user may read the list (the UI needs to know
-- whether to show approve buttons); only an admin may change it.
DROP POLICY IF EXISTS admins_read  ON admins;
DROP POLICY IF EXISTS admins_write ON admins;
CREATE POLICY admins_read  ON admins FOR SELECT TO authenticated USING (true);
CREATE POLICY admins_write ON admins FOR ALL
  USING (is_portal_admin()) WITH CHECK (is_portal_admin());

-- staff: every signed-in user reads the directory (Leave and Staff
-- Claim auto-fill from it); only admins may modify it.
DROP POLICY IF EXISTS staff_read  ON staff;
DROP POLICY IF EXISTS staff_write ON staff;
CREATE POLICY staff_read  ON staff FOR SELECT TO authenticated USING (true);
CREATE POLICY staff_write ON staff FOR ALL
  USING (is_portal_admin()) WITH CHECK (is_portal_admin());

-- Purchase Orders: submitters see and file their own; admins see all
-- and are the only ones who may approve or delete.
DROP POLICY IF EXISTS po_select ON po_logs;
DROP POLICY IF EXISTS po_insert ON po_logs;
DROP POLICY IF EXISTS po_update ON po_logs;
DROP POLICY IF EXISTS po_delete ON po_logs;
CREATE POLICY po_select ON po_logs FOR SELECT TO authenticated
  USING (is_portal_admin() OR lower(req_email) = portal_email());
CREATE POLICY po_insert ON po_logs FOR INSERT TO authenticated
  WITH CHECK (is_portal_admin() OR lower(req_email) = portal_email());
CREATE POLICY po_update ON po_logs FOR UPDATE TO authenticated
  USING (is_portal_admin()
         OR (lower(req_email) = portal_email() AND status IN ('Pending','Draft','Rejected')))
  WITH CHECK (is_portal_admin() OR lower(req_email) = portal_email());
CREATE POLICY po_delete ON po_logs FOR DELETE TO authenticated
  USING (is_portal_admin());

-- Cash Claims
DROP POLICY IF EXISTS cc_select ON cash_claims;
DROP POLICY IF EXISTS cc_insert ON cash_claims;
DROP POLICY IF EXISTS cc_update ON cash_claims;
DROP POLICY IF EXISTS cc_delete ON cash_claims;
CREATE POLICY cc_select ON cash_claims FOR SELECT TO authenticated
  USING (is_portal_admin() OR lower(claimant_email) = portal_email());
CREATE POLICY cc_insert ON cash_claims FOR INSERT TO authenticated
  WITH CHECK (is_portal_admin() OR lower(claimant_email) = portal_email());
CREATE POLICY cc_update ON cash_claims FOR UPDATE TO authenticated
  USING (is_portal_admin()
         OR (lower(claimant_email) = portal_email() AND status IN ('Pending','Draft','Rejected')))
  WITH CHECK (is_portal_admin() OR lower(claimant_email) = portal_email());
CREATE POLICY cc_delete ON cash_claims FOR DELETE TO authenticated
  USING (is_portal_admin());

-- Staff Claims
DROP POLICY IF EXISTS sc_select ON staff_claims;
DROP POLICY IF EXISTS sc_insert ON staff_claims;
DROP POLICY IF EXISTS sc_update ON staff_claims;
DROP POLICY IF EXISTS sc_delete ON staff_claims;
CREATE POLICY sc_select ON staff_claims FOR SELECT TO authenticated
  USING (is_portal_admin() OR lower(staff_email) = portal_email());
CREATE POLICY sc_insert ON staff_claims FOR INSERT TO authenticated
  WITH CHECK (is_portal_admin() OR lower(staff_email) = portal_email());
CREATE POLICY sc_update ON staff_claims FOR UPDATE TO authenticated
  USING (is_portal_admin()
         OR (lower(staff_email) = portal_email() AND status IN ('Pending','Draft','Rejected')))
  WITH CHECK (is_portal_admin() OR lower(staff_email) = portal_email());
CREATE POLICY sc_delete ON staff_claims FOR DELETE TO authenticated
  USING (is_portal_admin());

-- Leave
DROP POLICY IF EXISTS leave_select ON logs;
DROP POLICY IF EXISTS leave_insert ON logs;
DROP POLICY IF EXISTS leave_update ON logs;
DROP POLICY IF EXISTS leave_delete ON logs;
-- Everyone signed in can read leave rows: the Calendar tab shows who is
-- away. Narrow this to the admin-or-own pattern above if that is not wanted.
CREATE POLICY leave_select ON logs FOR SELECT TO authenticated USING (true);
CREATE POLICY leave_insert ON logs FOR INSERT TO authenticated
  WITH CHECK (is_portal_admin() OR lower(email) = portal_email());
CREATE POLICY leave_update ON logs FOR UPDATE TO authenticated
  USING (is_portal_admin()
         OR (lower(email) = portal_email() AND status IN ('Pending','Cancelled')))
  WITH CHECK (is_portal_admin() OR lower(email) = portal_email());
CREATE POLICY leave_delete ON logs FOR DELETE TO authenticated
  USING (is_portal_admin());
