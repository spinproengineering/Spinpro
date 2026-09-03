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

## Live site

**https://hiufsitake.github.io/Spinpro/** — served by GitHub Pages from `main`,
redeployed on every push.

The site lives under the `/Spinpro/` subpath, so every path in this repo is
relative and the module manifests use `"start_url": "./"`. Keep it that way —
absolute `/...` paths break under Pages.

## Preview mode

Until Supabase is configured the portal **bypasses login** and opens straight to
the dashboard, with a lime "Preview mode" banner on every page. It is gated on
`PREVIEW_MODE = String(SUPABASE_URL || '').indexOf('http') !== 0`, so setting a
real Supabase URL turns it off automatically and restores the session guard on
every module. Nothing to remember to disable. See SETUP.md §2b.

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

GitHub Pages, from `main` at the repo root — Settings → Pages → *Deploy from a
branch*. Push to `main` and it redeploys. `.nojekyll` keeps Pages from running
the tree through Jekyll.

`wrangler.toml` is kept for the Cloudflare Workers route (SETUP.md §8 Option B)
if you later move to a private repo and a custom domain.

## Security — this repo is public

Free Pages hosting requires it, so everything committed here is world-readable
and permanent in git history.

There is **no Gemini API key in this repo** and AI receipt scanning is disabled
(`GEMINI_API_KEY = ''` in `staffclaim/index.html`); the scanner panel hides
itself and claims are entered by hand. Don't paste a key there — it would be
scraped within minutes. To re-enable scanning, proxy the call through a Supabase
Edge Function so the key stays server-side: [SETUP.md §5](SETUP.md).

The Supabase **anon** key is safe to publish (it ships to every browser); your
data is protected by Row Level Security instead, which makes §3.4 load-bearing.
Never commit the **service_role** key or a Cloudflare token — see
[`.github/SECRETS.md`](.github/SECRETS.md).
