# SpinPro Portal

Internal operations portal for **SPINPRO ENGINEERING SDN. BHD.** — a static,
build-free web app (vanilla HTML/JS + Tailwind via CDN) backed by Supabase and
served by a Cloudflare Worker. Installable as a PWA on iOS and Android.

## Modules

| Module | Path | Table | Number format |
|---|---|---|---|
| Login + dashboard | `/` | — | — |
| Purchase Orders | `/po/` | `po_logs` | `SPN-PO-YYYYMMDD-XX` |
| Cash Claim | `/cashclaim/` | `cash_claims` | `SPN-CC-YYYYMMDD-XX` |
| Staff Claim (AI receipt scanning) | `/staffclaim/` | `staff_claims` | `SPN-SC-YYYYMMDD-XX` |
| Leave | `/leave/` | `logs` | integer id |
| Settings (admin) | `/settings/` | `staff` | — |

## Status — configuration required

The portal is fully rebranded but **not yet wired to a backend**. Every
credential ships as a literal placeholder, so nothing here talks to a live
database until you fill them in:

```bash
grep -rn "YOUR_" --include="*.html" --include="*.yml" . | grep -v vendor/
```

Work through **[SETUP.md](SETUP.md)** — §3 (Supabase project + SQL schema),
§4 (admin emails and company details), §5–6 (Gemini + EmailJS), §8 (deploy).
§12 is the full placeholder checklist.

## Brand

Palette sampled from the SpinPro swirl mark:

| Token | Hex | Role |
|---|---|---|
| Deep green | `#0d5339` | Primary dark — buttons, `theme_color` |
| Ocean blue | `#0e6091` | Primary accent — focus, active tabs |
| Blue-teal | `#17798d` | Tile accent |
| Teal | `#1f9a8f` | Tile accent, hover |
| Green | `#5aa84e` | Tile accent |
| Lime | `#8ab52a` | Highlight |
| Forest | `#062b1e` | Install-banner ground |

Artwork lives at the repo root: `logo.png` (full lockup), `icon-192.png`,
`icon-512.png`, `apple-touch-icon.png` (swirl mark).

## Development

No build step, no dependencies to install — edit the `index.html` files
directly and serve the repo root:

```bash
python3 -m http.server 8080    # then open http://localhost:8080
```

`supabase-js` and `emailjs` are vendored under `vendor/` on purpose: a CDN
failure would leave `supabase` undefined and break login. Keep them local.

## Deploy

Cloudflare Workers serves the repo root as static assets (`wrangler.toml`).
Custom domains are commented out until SpinPro's zone is on Cloudflare — until
then the Worker answers on its generated `*.workers.dev` URL.

```bash
wrangler deploy    # from repo root
```

See [`.github/SECRETS.md`](.github/SECRETS.md) for where every key lives and how
to rotate it. Never commit a Cloudflare token or the Supabase `service_role` key.
