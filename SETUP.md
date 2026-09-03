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

## 2b. Preview mode (login bypass)

While Supabase is unconfigured the portal **bypasses login** so you can click
through the UI. A lime banner reads *"Preview mode — login bypassed, no database
connected"* on every page.

It is controlled by one line, repeated in each page:

```javascript
const PREVIEW_MODE = String(SUPABASE_URL || '').indexOf('http') !== 0;
```

So it is on only while `SUPABASE_URL` is the `YOUR_SUPABASE_URL` placeholder.
**The moment you paste a real Supabase URL in §3.2, `PREVIEW_MODE` becomes
false, the banner disappears, and every module enforces the session guard
again** — it redirects to the login page when there is no session. There is
nothing to remember to turn off, and no way for the bypass to reach a
configured deployment.

What preview mode does *not* do: there is no database behind it, so lists are
empty and nothing saves. It is for looking at layout and navigation.

> If you ever want the portal reachable **only** by staff, note that a static
> site cannot enforce that — the guard is client-side. Real access control is
> Supabase Auth plus the RLS policies in §3.4.

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
- Set **Site URL** to your deployed domain (`https://spinproengineering.github.io/Spinpro`)
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

## 5. AI Receipt Scanning (Gemini) — disabled

The Smart Scanner in Staff Claim is **off**, and there is no Gemini key in this
repo. `staffclaim/index.html` has:

```javascript
const GEMINI_API_KEY = '';
```

While that is empty the scanner panel hides itself and the handler refuses to
run, so Staff Claim works normally with items entered by hand. Nothing else in
the portal touches Gemini.

### Do not just paste a key here

This repository is **public** (§11). A key in this file is world-readable and
will be scraped and billed against, usually within minutes. GitHub's secret
scanning will not save you either — that is why the original two-variable
`K1 + K2` split was removed rather than kept with a placeholder.

### To turn scanning back on, safely

**Recommended — proxy it.** Put the key in a Supabase Edge Function and call
that from the browser instead of `generativelanguage.googleapis.com`:

```bash
supabase secrets set GEMINI_API_KEY=your-real-key
supabase functions deploy scan-receipt
```

Then point the two `fetch` calls in `handleAIProcessing()` at your function's
URL, passing the user's Supabase JWT. The key never reaches the browser, and
only signed-in staff can spend your quota.

**Weaker fallback — restrict the key.** If you do put it client-side, first go to
Google Cloud Console → Credentials and restrict the key to the Generative
Language API with an HTTP-referrer restriction for `https://spinproengineering.github.io/*`.
That limits, but does not prevent, abuse. Set a billing budget and alert either
way. A client-side key is visible to anyone who opens DevTools regardless of
whether the repo is public.

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

### Option A — GitHub Pages (current setup)

This is how the portal is published today. The site is served straight from the
`main` branch of the public `spinproengineering/Spinpro` repo:

1. Repo **Settings → Pages**
2. **Source:** *GitHub Actions*

`.github/workflows/deploy-pages.yml` does the rest — it uploads the repo root
verbatim (no build step) and deploys it on every push to `main`. Progress and
failures are visible in the **Actions** tab, which a branch deploy does not give
you.

Live at **https://spinproengineering.github.io/Spinpro/**; the first run takes a minute
or two.

> A 404 saying *"There isn't a GitHub Pages site here"* while Pages is enabled
> almost always means the source is set to *GitHub Actions* but no workflow has
> published anything yet — check the Actions tab. The other cause is a run that
> failed.

Notes specific to Pages hosting:

- The site lives under the `/Spinpro/` **subpath**, not a domain root. Every
  link, script and icon reference in this repo is relative, and the four module
  `manifest.json` files use `"start_url": "./"` for the same reason. **Do not
  change any of these to absolute `/...` paths** — that would break the
  installed PWA and every module page.
- `.nojekyll` at the repo root tells Pages to serve the tree verbatim instead of
  running it through Jekyll.
- The repo is **public**, which free GitHub Pages requires. Everything in it is
  world-readable, so treat every value you paste into a source file as published
  — see §11.

### Option B — Cloudflare Workers

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
4. Set the Supabase **Site URL** and redirect URLs to the same origin (§3.5).
   The module email links need no change — they derive the origin at runtime
   (see below) — but `robots.txt` and `sitemap.xml` carry a literal URL.

> **Moving the portal between accounts, repos or domains.** The approval emails
> sent by `po/`, `cashclaim/`, `staffclaim/` and `leave/` build their links from
> `PORTAL_URL`, computed at load time from `window.location`:
>
> ```javascript
> const PORTAL_URL = window.location.origin +
>     window.location.pathname.replace(/[^/]*$/, '');
> ```
>
> So a GitHub account transfer, a repo rename or a custom domain needs no code
> change — links always point back at wherever the page was actually served
> from. Only `robots.txt` and `sitemap.xml` hold a literal origin.

> Every hostname the portal answers on must be listed in `wrangler.toml`: on each
> deploy Cloudflare reconciles the Worker's domains to exactly that list, so a
> domain added only in the dashboard is removed on the next deploy.

### Option C — Netlify

```bash
# Install Netlify CLI
npm install -g netlify-cli

# Deploy from repo root
netlify deploy --prod --dir .
```

Or connect the GitHub repo in Netlify UI → it auto-deploys on push.

### Option D — Vercel

```bash
npx vercel --prod
```

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

**This repository is public.** Everything committed here is world-readable and
permanently in the git history — deleting a file later does not unpublish it.
That is a deliberate trade for free GitHub Pages hosting, but it changes what is
safe to paste into a source file.

### The Gemini API key is the one real hazard

`staffclaim/index.html` splits the key across two variables:

```javascript
const K1 = 'YOUR_GEMINI'; const K2 = '_API_KEY';
const GEMINI_API_KEY = K1 + K2;
```

That split defeats **GitHub's own secret scanning**, so if you paste a live key
here GitHub will not warn you and push protection will not stop you. Meanwhile
bots continuously scrape public repos for `AIza...` strings and abuse what they
find, usually within minutes, billed to your Google Cloud project.

Before putting a real key in, do one of these:

- **Restrict the key** in Google Cloud Console → Credentials → API restrictions:
  limit it to the Generative Language API, and add an HTTP-referrer restriction
  for `https://spinproengineering.github.io/*`. A restricted key is far less useful to a
  scraper. This is the minimum.
- **Proxy it** — move the Gemini call behind a Supabase Edge Function that holds
  the key server-side. The browser never sees it. This is the only approach that
  genuinely protects the key.
- **Make the repo private** and host on Cloudflare Workers (§8 Option B) instead.

Set a billing budget and alert on the Google Cloud project either way.

### The rest

- The Supabase **anon** key is safe to publish — it ships to every browser by
  design. Your data is protected by Row Level Security, not by that key's
  secrecy. This makes §3.4 load-bearing: get the RLS policies right.
- Never commit the Supabase **service_role** key or a Cloudflare API token. Those
  bypass RLS and control your account.
- The `ADMIN_EMAILS` array is client-side only — anyone can read it and edit
  their local copy. Use Supabase RLS for real server-side authorization.
- Staff names, emails and company details in this repo are public once committed.

---

## 12. Credentials Checklist

Every value below ships as a literal placeholder — grep for the token to find
each occurrence.

| Placeholder | Files |
|---|---|
| `YOUR_SUPABASE_URL` | `index.html`, `po/`, `cashclaim/`, `staffclaim/`, `leave/`, `settings/` |
| `YOUR_SUPABASE_ANON_KEY` | same six files |
| `YOUR_SUPABASE_PROJECT_REF` | `index.html` (auth-token storage key), `.github/workflows/prevent-supabase-pause.yml` |
| *(none — Gemini key removed; see §5)* | — |
| `YOUR_EMAILJS_SERVICE_ID` | `po/`, `cashclaim/`, `staffclaim/`, `leave/` |
| `YOUR_EMAILJS_TEMPLATE_ID` | same four files |
| `YOUR_EMAILJS_PUBLIC_KEY` | same four files |
| `YOUR_ADMIN_EMAIL` | `index.html`, `po/`, `cashclaim/`, `staffclaim/`, `leave/` |
| `YOUR_FINANCE_EMAIL` | `po/`, `cashclaim/`, `staffclaim/`, `leave/` |
| `YOUR_COMPANY_EMAIL`, `YOUR_COMPANY_ADDRESS`, `YOUR_COMPANY_TEL`, `YOUR_SSM_REG_NUMBER` | `CO` object in `po/`, `cashclaim/`, `staffclaim/` |
| *(none — module email links derive the origin at runtime)* | `robots.txt` and `sitemap.xml` still carry a literal origin; update those two if you move hosts |

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
