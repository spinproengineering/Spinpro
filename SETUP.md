# SpinPro Portal — Setup Guide

> SPINPRO ENGINEERING SDN. BHD.

This guide covers everything you need to go from a fresh clone to a fully running portal.

---

## 1. Prerequisites

- A **Supabase** project (free tier is fine to start)
- A **Google Gemini API key** (for AI receipt scanning in Staff Claim)
- An **EmailJS** account (for email notifications)
- A **Cloudflare** account for Workers hosting. A custom domain is optional — the portal runs on the generated `*.workers.dev` URL until you attach one. Netlify/Vercel/GitHub Pages also work as alternatives.

---

## 2. Brand Assets

The SpinPro artwork already ships in this repo — nothing to add to get started:

```
spinpro/
  logo.png             ← full lockup (swirl mark + "SpinPro Engineering Sdn Bhd")
  icon-192.png         ← PWA icon (swirl mark only)
  icon-512.png         ← PWA icon + maskable
  apple-touch-icon.png ← iOS home-screen icon
```

`logo.png` is referenced as `logo.png` (root pages) and `../logo.png` (module
pages); the icons are wired into every `manifest.json`. Replace the files
in place — keep the same names — to swap in higher-resolution artwork.

**Optional — PO letterhead.** `po/index.html` looks for `spinpro letterhead.jpg`
at the repo root and, when present, renders it as the full-width header of every
generated PO PDF. It is not included; without it the PDF falls back to a text
header built from the `CO` object (§4.2).

### Brand palette

| Token | Hex | Used for |
|---|---|---|
| Deep green | `#0d5339` | Primary dark — buttons, `theme_color`, nav bar |
| Ocean blue | `#0e6091` | Primary accent — focus rings, active tabs, links |
| Blue-teal | `#17798d` | Tile accent |
| Teal | `#1f9a8f` | Tile accent, hover states |
| Green | `#5aa84e` | Tile accent |
| Lime | `#8ab52a` | Highlight accent |
| Forest | `#062b1e` | Install-banner ground |

All seven are sampled from the SpinPro swirl mark.

---

## 3. Supabase Setup

### 3.1 Create a new Supabase project

1. Go to [supabase.com](https://supabase.com) → New Project
2. Note your **Project URL** and **anon public key** from Settings → API

### 3.2 Replace credentials in all files

Search for `YOUR_SUPABASE_URL` and `YOUR_SUPABASE_ANON_KEY` and replace in:

| File | Occurrences |
|------|-------------|
| `index.html` | 1 each |
| `po/index.html` | 1 each (as `GUARD_URL` / `GUARD_KEY`) |
| `cashclaim/index.html` | 1 each |
| `staffclaim/index.html` | 1 each |
| `leave/index.html` | 1 each |
| `settings/index.html` | 1 each |

`index.html` also builds the Supabase auth-token storage key from the project
ref — replace `YOUR_SUPABASE_PROJECT_REF` there with the ref from your project
URL (`https://<ref>.supabase.co`), or the stale-token cleanup on login silently
stops working.

### 3.3 Run the SQL schema

Go to Supabase → SQL Editor and run the following:

```sql
-- ============================================================
-- SPINPRO ENGINEERING SDN. BHD. — Database Schema
-- ============================================================

-- Staff directory (used by Leave & Staff Claim for auto-fill)
CREATE TABLE IF NOT EXISTS staff (
  id          BIGSERIAL PRIMARY KEY,
  email       TEXT UNIQUE NOT NULL,
  name        TEXT NOT NULL,
  department  TEXT,
  position    TEXT,
  phone       TEXT,
  join_date   DATE,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- Purchase Orders
CREATE TABLE IF NOT EXISTS po_logs (
  id              BIGSERIAL PRIMARY KEY,
  po_number       TEXT UNIQUE NOT NULL,   -- SPN-PO-YYYYMMDD-XX
  requester_email TEXT NOT NULL,
  requester_name  TEXT,
  vendor_name     TEXT,
  vendor_contact  TEXT,
  vendor_email    TEXT,
  category        TEXT,
  items           JSONB DEFAULT '[]',     -- [{desc, qty, unit, price}]
  subtotal        NUMERIC(12,2),
  tax             NUMERIC(12,2),
  total           NUMERIC(12,2),
  currency        TEXT DEFAULT 'MYR',
  notes           TEXT,
  status          TEXT DEFAULT 'Pending', -- Pending | Approved | Rejected | Ordered | Received
  approved_by     TEXT,
  approver_note   TEXT,
  approved_at     TIMESTAMPTZ,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Cash Claims
CREATE TABLE IF NOT EXISTS cash_claims (
  id              BIGSERIAL PRIMARY KEY,
  claim_number    TEXT UNIQUE NOT NULL,   -- SPN-CC-YYYYMMDD-XX
  claimant_email  TEXT NOT NULL,
  claimant_name   TEXT,
  department      TEXT,
  claim_date      DATE,
  items           JSONB DEFAULT '[]',     -- [{description, qty, unit_price}]
  total_amount    NUMERIC(12,2),
  currency        TEXT DEFAULT 'MYR',
  purpose         TEXT,
  notes           TEXT,
  status          TEXT DEFAULT 'Pending', -- Pending | Approved | Rejected | Paid
  approved_by     TEXT,
  approver_note   TEXT,
  approved_at     TIMESTAMPTZ,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Staff Claims (with AI receipt scanning)
CREATE TABLE IF NOT EXISTS staff_claims (
  id              BIGSERIAL PRIMARY KEY,
  claim_number    TEXT UNIQUE NOT NULL,   -- SPN-SC-YYYYMMDD-XX
  claimant_email  TEXT NOT NULL,
  claimant_name   TEXT,
  department      TEXT,
  items           JSONB DEFAULT '[]',     -- [{vendor, amount, project, remarks}]
  total_amount    NUMERIC(12,2),
  currency        TEXT DEFAULT 'MYR',
  notes           TEXT,
  status          TEXT DEFAULT 'Pending', -- Pending | Approved | Rejected | Paid
  approved_by     TEXT,
  approver_note   TEXT,
  approved_at     TIMESTAMPTZ,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Leave System
CREATE TABLE IF NOT EXISTS logs (
  id              BIGSERIAL PRIMARY KEY,
  email           TEXT NOT NULL,
  name            TEXT,
  leave_type      TEXT NOT NULL,          -- Annual | Sick | Hospitalization | Maternity | Paternity | Compassionate | Unpaid
  duration        TEXT DEFAULT 'full',    -- full | half_am | half_pm
  start_date      DATE NOT NULL,
  end_date        DATE NOT NULL,
  days            NUMERIC(4,1) NOT NULL,
  reason          TEXT,
  year            INT,
  status          TEXT DEFAULT 'Pending', -- Pending | Approved | Rejected | Cancelled
  approved_by     TEXT,
  approver_note   TEXT,
  applied_at      TIMESTAMPTZ DEFAULT NOW(),
  approved_at     TIMESTAMPTZ
);

-- Settings / configuration (optional)
CREATE TABLE IF NOT EXISTS settings (
  key   TEXT PRIMARY KEY,
  value TEXT
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_po_logs_email   ON po_logs(requester_email);
CREATE INDEX IF NOT EXISTS idx_po_logs_status  ON po_logs(status);
CREATE INDEX IF NOT EXISTS idx_cc_email        ON cash_claims(claimant_email);
CREATE INDEX IF NOT EXISTS idx_sc_email        ON staff_claims(claimant_email);
CREATE INDEX IF NOT EXISTS idx_logs_email      ON logs(email);
CREATE INDEX IF NOT EXISTS idx_logs_year       ON logs(year);
CREATE INDEX IF NOT EXISTS idx_logs_status     ON logs(status);
```

### 3.4 Row Level Security (RLS)

Enable RLS on all tables in Supabase → Authentication → Policies, then apply:

```sql
-- Enable RLS
ALTER TABLE staff       ENABLE ROW LEVEL SECURITY;
ALTER TABLE po_logs     ENABLE ROW LEVEL SECURITY;
ALTER TABLE cash_claims ENABLE ROW LEVEL SECURITY;
ALTER TABLE staff_claims ENABLE ROW LEVEL SECURITY;
ALTER TABLE logs        ENABLE ROW LEVEL SECURITY;
ALTER TABLE settings    ENABLE ROW LEVEL SECURITY;

-- Users can read/write their own records; admins can see all
-- Simple policy: authenticated users can access all (tighten as needed)
CREATE POLICY "auth_all" ON po_logs      FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "auth_all" ON cash_claims  FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "auth_all" ON staff_claims FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "auth_all" ON logs         FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "auth_all" ON staff        FOR ALL TO authenticated USING (true) WITH CHECK (true);
CREATE POLICY "auth_all" ON settings     FOR ALL TO authenticated USING (true) WITH CHECK (true);
```

### 3.5 Auth settings

In Supabase → Authentication → Settings:
- Enable **Email** provider
- Set **Site URL** to your deployed domain (`https://portal.spinproengineering.com`)
- Add redirect URLs if using magic links

---

## 4. Admin Emails

In each module's `index.html`, find and update the `ADMIN_EMAILS` array:

```javascript
const ADMIN_EMAILS = ['YOUR_ADMIN_EMAIL'];
```

Add all email addresses that should have admin/approval access.

### 4.1 PO Approver Map (po/index.html)

Update `APPROVER_MAP` with your approvers' initials:

```javascript
const APPROVER_MAP = {
  'YOUR_ADMIN_EMAIL': 'ADM',
  'manager@spinproengineering.com': 'MGR',
};
```

### 4.2 Company details (po/index.html)

Update the `CO` object:

```javascript
const CO = {
  name: 'SPINPRO ENGINEERING SDN. BHD.',
  reg:  '202X-XXXXXX (XXXXXXX-X)',   // SSM registration number
  email: 'YOUR_ADMIN_EMAIL',
  address: 'Your Full Address, Postcode, City, State',
  tel: '+60 X-XXXX XXXX'
};
```

---

## 5. Gemini API (AI Receipt Scanning)

In `staffclaim/index.html`, replace:

```javascript
const GEMINI_API_KEY = 'YOUR_GEMINI_API_KEY';
```

Get your key at [aistudio.google.com](https://aistudio.google.com) → Get API Key.
The free tier supports generous usage for receipt scanning.

---

## 6. EmailJS (Email Notifications)

EmailJS sends notifications when claims/POs are submitted or approved.

1. Create account at [emailjs.com](https://www.emailjs.com)
2. Add an **Email Service** (Gmail, Outlook, etc.)
3. Create **Email Templates** for:
   - Submission confirmation (to claimant)
   - Approval/rejection notification (to claimant)
   - New submission alert (to admin)
4. In each `index.html`, replace:

```javascript
const EMAILJS_SERVICE  = 'YOUR_EMAILJS_SERVICE_ID';
const EMAILJS_TEMPLATE = 'YOUR_EMAILJS_TEMPLATE_ID';
const EMAILJS_KEY      = 'YOUR_EMAILJS_PUBLIC_KEY';
```

---

## 7. Staff Records

Leave balance and Staff Claim auto-fill require a staff record in the `staff` table.
Insert records for each employee:

```sql
INSERT INTO staff (email, name, department, position, join_date)
VALUES
  ('alice@spinproengineering.com', 'Alice Tan', 'Operations', 'Manager', '2022-03-01'),
  ('bob@spinproengineering.com',   'Bob Lee',   'Sales',       'Executive', '2023-06-15');
```

Or build an admin UI entry form as a future enhancement.

---

## 8. Deployment

### Option A — Cloudflare Workers (recommended)

The portal ships as static assets served by a Cloudflare Worker. Configuration
lives in `wrangler.toml`:

| Key | Meaning |
|---|---|
| `name` | The Workers project name (`spinpro`) |
| `assets.directory` | Serves the entire repo root as static files |
| `[[routes]]` → `custom_domain` | **Commented out.** Uncomment once SpinPro owns a Cloudflare zone (see below) |

Out of the box there is **no custom domain**, so a first deploy is safe: the
portal comes up on the generated `spinpro.<your-subdomain>.workers.dev` URL.

**Manual deploy:**

```bash
npm install -g wrangler
wrangler login
wrangler deploy        # from repo root
```

**Automatic deploy (CI):** connect this repo under Cloudflare → **Workers &
Pages → Create → Connect to Git**. Workers Builds then redeploys on every push
to `main`, with no GitHub Actions secret required. See `.github/SECRETS.md`.

#### Custom domain — DNS setup

Skip this section until SpinPro's domain is on Cloudflare. The domain must be a
**zone in the same Cloudflare account** as the Worker:

1. Cloudflare dashboard → **Add a site** → your SpinPro domain, then update the
   registrar's nameservers to the two Cloudflare nameservers shown.
2. Uncomment the two `[[routes]]` blocks at the bottom of `wrangler.toml` and
   change the hostnames to your own. `wrangler deploy` then provisions each
   hostname and its TLS certificate automatically — no manual DNS record is
   required for a Workers custom domain.
3. Confirm under **Workers & Pages → spinpro → Settings → Domains & Routes**
   that the hostname is listed and Active.
4. Set the Supabase **Site URL** and redirect URLs to the same origin (§3.5),
   and search the repo for `portal.spinproengineering.com` — the placeholder
   domain is baked into the email notification links in `po/`, `cashclaim/`,
   `staffclaim/` and `leave/`.

> Every hostname the portal answers on must be listed in `wrangler.toml`: on each
> deploy Cloudflare reconciles the Worker's domains to exactly that list, so a
> domain added only in the dashboard is removed on the next deploy.

### Option B — Netlify

```bash
# Install Netlify CLI
npm install -g netlify-cli

# Deploy from repo root
netlify deploy --prod --dir .
```

Or connect the GitHub repo in Netlify UI → it auto-deploys on push.

### Option C — Vercel

```bash
npx vercel --prod
```

### Option D — GitHub Pages

1. Go to repo Settings → Pages
2. Set source to branch `main` (or your production branch), folder `/root`
3. Your site will be at `https://<your-github-user>.github.io/Spinpro/`

### Option E — Any static host / nginx

Copy all files to your web root. No build step needed — this is plain HTML/CSS/JS.

---

## 9. Module Summary

| Module | URL Path | DB Table | Number Format |
|--------|----------|----------|---------------|
| Portal Login | `/` | — | — |
| Purchase Orders | `/po/` | `po_logs` | `SPN-PO-YYYYMMDD-XX` |
| Cash Claim | `/cashclaim/` | `cash_claims` | `SPN-CC-YYYYMMDD-XX` |
| Staff Claim | `/staffclaim/` | `staff_claims` | `SPN-SC-YYYYMMDD-XX` |
| Leave System | `/leave/` | `logs` | Integer ID |

---

## 10. Leave Entitlements (Malaysian Employment Act)

| Years of Service | Annual Leave | Medical Leave |
|-----------------|-------------|---------------|
| < 2 years | 12 days | 14 days |
| 2–4 years | 16 days | 18 days |
| ≥ 5 years | 18 days | 18 days |

Hospitalisation leave: 60 days/year (in addition to medical leave).
Carry-forward: max 5 days from previous year (enabled from 2025 cycle onwards).

---

## 11. Security Notes

- Never commit real API keys or Supabase credentials to git
- Use environment variables or a `.env` file (excluded from git) if using a build tool
- For production, restrict Supabase RLS policies to enforce per-user data access
- The `ADMIN_EMAILS` array is client-side only — use Supabase RLS for true server-side authorization

---

## 12. Credentials Checklist

Every value below ships as a literal placeholder — grep for the token to find
each occurrence.

| Placeholder | Files |
|---|---|
| `YOUR_SUPABASE_URL` | `index.html`, `po/`, `cashclaim/`, `staffclaim/`, `leave/`, `settings/` |
| `YOUR_SUPABASE_ANON_KEY` | same six files |
| `YOUR_SUPABASE_PROJECT_REF` | `index.html` (auth-token storage key), `.github/workflows/prevent-supabase-pause.yml` |
| `YOUR_GEMINI` + `_API_KEY` | `staffclaim/index.html` (`K1`/`K2`) |
| `YOUR_EMAILJS_SERVICE_ID` | `po/`, `cashclaim/`, `staffclaim/`, `leave/` |
| `YOUR_EMAILJS_TEMPLATE_ID` | same four files |
| `YOUR_EMAILJS_PUBLIC_KEY` | same four files |
| `YOUR_ADMIN_EMAIL` | `index.html`, `po/`, `cashclaim/`, `staffclaim/`, `leave/` |
| `YOUR_FINANCE_EMAIL` | `po/`, `cashclaim/`, `staffclaim/`, `leave/` |
| `YOUR_COMPANY_EMAIL`, `YOUR_COMPANY_ADDRESS`, `YOUR_COMPANY_TEL`, `YOUR_SSM_REG_NUMBER` | `CO` object in `po/`, `cashclaim/`, `staffclaim/` |
| `portal.spinproengineering.com` | email notification links in `po/`, `cashclaim/`, `staffclaim/`, `leave/`; `robots.txt`; `sitemap.xml` |

Then:

- [ ] SQL schema run in Supabase
- [ ] Staff records inserted in the `staff` table
- [ ] Supabase Auth Site URL set to the deployed origin
- [ ] `SUPABASE_KEY` GitHub Actions secret set (keep-alive workflow)
- [ ] Custom domain uncommented in `wrangler.toml` (only once the zone exists)

A quick sweep for anything still unset:

```bash
grep -rn "YOUR_" --include="*.html" --include="*.yml" . | grep -v vendor/
```
