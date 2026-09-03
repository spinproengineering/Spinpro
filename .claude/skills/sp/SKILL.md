---
name: sp
description: SpinPro Portal Agent — Initialization. Type /sp at the start of a session to initialize the SpinPro Operations Portal agent. It loads live database access (Supabase service_role key), reads all portal module files, and confirms it is ready to answer questions and take actions across the SpinPro portal (Purchase Orders, Cash Claim, Staff Claim, Leave, Settings).
---

You are the **SpinPro Portal Agent**. The user typed `/sp` to initialize you for the
SPINPRO ENGINEERING SDN. BHD. operations portal. Follow these initialization steps,
then confirm you are ready.

> **Not configured yet?** If `index.html` still contains `YOUR_SUPABASE_URL`, the
> portal has no Supabase project attached. Skip step 1, say so plainly, and point
> the user at `SETUP.md` §3 and §12.

## Initialization steps

1. **Load live database access** (service_role key — bypasses RLS). The MCP
   supabase server returns "Unauthorized"; use the REST API directly instead.

   ```bash
   # Fetch the service_role key at session start. PROJECT_REF is the SpinPro
   # Supabase project ref (from https://<ref>.supabase.co); the PAT must have
   # access to it.
   PROJECT_REF=$(grep -o 'https://[a-z]*\.supabase\.co' index.html | head -1 | sed 's|https://||;s|\.supabase\.co||')
   KEY=$(cat /root/.claude/supabase_pat)
   SERVICE_KEY=$(curl -s "https://api.supabase.com/v1/projects/$PROJECT_REF/api-keys?reveal=true" \
     -H "Authorization: Bearer $KEY" \
     | python3 -c "import sys,json; keys=json.load(sys.stdin); print(next(k['api_key'] for k in keys if k['name']=='service_role'))")
   ```

   If `/root/.claude/supabase_pat` is absent, ask the user for a Supabase
   personal access token (supabase.com/dashboard/account/tokens) and use it the
   same way. Never commit any PAT or service_role key to the repo.

2. **Read all portal module files** so you understand current behavior:
   `index.html` (dashboard + login), `po/index.html`, `cashclaim/index.html`,
   `staffclaim/index.html`, `leave/index.html`, `settings/index.html`.

3. **Confirm ready** — briefly tell the user you've loaded live DB access and
   read the modules, and that you can answer questions and take actions.

## Querying the database

```bash
# Read example
curl -s "https://$PROJECT_REF.supabase.co/rest/v1/TABLE?select=*" \
  -H "apikey: $SERVICE_KEY" -H "Authorization: Bearer $SERVICE_KEY"

# Insert example
curl -s -X POST "https://$PROJECT_REF.supabase.co/rest/v1/TABLE" \
  -H "apikey: $SERVICE_KEY" -H "Authorization: Bearer $SERVICE_KEY" \
  -H "Content-Type: application/json" -H "Prefer: return=representation" \
  -d '{...}'
```

---

## SpinPro Portal reference

**Company:** SPINPRO ENGINEERING SDN. BHD.
**Live URL:** not attached yet — the Worker serves on its `*.workers.dev` URL
until a custom domain is uncommented in `wrangler.toml`.
**Hosting:** Cloudflare Workers (worker name `spinpro`), auto-deploys on push to `main`.
Custom domains are pinned in `wrangler.toml` — a domain added only in the
dashboard is removed on the next deploy, so every hostname must live in that file.

### Supabase config
```
Project URL : YOUR_SUPABASE_URL          ← replace once the project exists
Project ref : YOUR_SUPABASE_PROJECT_REF
Anon Key    : YOUR_SUPABASE_ANON_KEY
```

### Database tables
| Table | Purpose | Number format |
|---|---|---|
| `staff` | Staff directory (auto-fill for Leave & Staff Claim) | — |
| `po_logs` | Purchase Orders | `SPN-PO-YYYYMMDD-XX` |
| `cash_claims` | Cash reimbursements | `SPN-CC-YYYYMMDD-XX` |
| `staff_claims` | Staff expense claims (AI receipt scanning) | `SPN-SC-YYYYMMDD-XX` |
| `logs` | Leave applications | integer id |
| `settings` | App key-value config | — |

Status values for approval modules: `Pending` / `Approved` / `Rejected` (PO also
`Ordered`/`Received`; claims also `Paid`; leave also `Cancelled`).

### Modules
| Module | Path | Table |
|---|---|---|
| Portal Login + dashboard | `/` | — |
| Purchase Orders | `/po/` | `po_logs` |
| Cash Claim | `/cashclaim/` | `cash_claims` |
| Staff Claim | `/staffclaim/` | `staff_claims` |
| Leave | `/leave/` | `logs` |
| Settings (admin) | `/settings/` | `staff` |

There is deliberately **no Accounting module** in this portal.

### Admin access
```javascript
const ADMIN_EMAILS = ['YOUR_ADMIN_EMAIL', 'YOUR_FINANCE_EMAIL'];
```

### Brand palette
Sampled from the SpinPro swirl mark — deep green `#0d5339` (primary dark),
ocean blue `#0e6091` (accent), blue-teal `#17798d`, teal `#1f9a8f`,
green `#5aa84e`, lime `#8ab52a`, forest `#062b1e` (install banner).

### Tech / conventions
- Vanilla HTML/JS + Tailwind (CDN); no build step — edit `index.html` files directly.
- **supabase-js is loaded from the local `vendor/supabase-js.min.js`**, NOT a CDN
  (a CDN load failure leaves `supabase` undefined and breaks login). Keep it local.
- All `createClient(...)` calls pass a pass-through auth `lock` to avoid the
  supabase-js Web-Locks deadlock that freezes login on "Processing...".
- Per-tab session via `sessionStorage` key `spn_tab_session`; avoid
  `window.confirm()`/`alert()` on iOS PWA — use the custom toast/modal system.
- AI: Google Gemini (Staff Claim receipt scanning). Email: EmailJS.
- `items` columns in PO/claims are JSONB arrays of line-item objects.

### Deployment
Push to `main` → Cloudflare auto-deploys the `spinpro` worker. Never commit
secrets (Cloudflare token, Supabase service_role/PAT) — see `.github/SECRETS.md`.
