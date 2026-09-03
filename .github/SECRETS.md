# SPINPRO Portal — Keys & Tokens Inventory

This file documents **where** every key/token lives and how to rotate it.
It deliberately contains **no actual secret values**. It is stored under
`.github/` which is excluded from the deployed site (`.assetsignore`).

---

## Deployment

Deploys are handled by **Cloudflare's Git integration (Workers Builds)** — the
`spinpro` Worker is connected to this GitHub repo and rebuilds automatically on
every push to `main`. **No GitHub Actions secret is required for deploys.**

(There is intentionally no `deploy.yml` GitHub Action: it would be a second,
duplicate deploy path and would need a `CLOUDFLARE_API_TOKEN` secret. Cloudflare's
native integration already covers it.)

Custom domains are pinned in `wrangler.toml` — Cloudflare reconciles the Worker's
domains to that file on each deploy, so add every hostname there (not only in the
dashboard, or it gets removed on the next deploy).

---

## GitHub Actions Secrets

| Secret name | Used by | Purpose |
|---|---|---|
| `SUPABASE_KEY` | `.github/workflows/prevent-supabase-pause.yml` | Anon key used to ping the DB so the free-tier project isn't paused |

**Rotate:** generate a new value in the provider dashboard, then update the
secret in GitHub. No code change needed.

---

## Golden rules

- ❌ Never put a Cloudflare token or the Supabase **service_role** key in any
  file that ships to the browser (anything not excluded by `.assetsignore`).
- ✅ The Supabase **anon** key is safe to be public (it's in the client code);
  data is protected by Row Level Security.
