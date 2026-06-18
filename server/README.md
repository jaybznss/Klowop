# Klowop backend

Holds every secret so the iOS app never does: the **Anthropic key** (assistant
proxy), the **Plaid secret** (bank data), and the logic that verifies **Sign in
with Apple** and **StoreKit subscriptions**. Each user's data is isolated by
their Apple account. State lives in a local SQLite file (`klowop.db`).

## Run locally

```bash
cd server
cp .env.example .env      # fill in the values
npm install
npm start                 # http://localhost:8484
```

## Endpoints

| Method | Path | Auth | Purpose |
|---|---|---|---|
| `POST` | `/auth/apple` | — | Verify Sign in with Apple token → returns a session token |
| `POST` | `/api/assistant/messages` | session + sub | Streams Claude (server's key) |
| `POST` | `/api/subscription/verify` | session | Verify a StoreKit signed transaction → store entitlement |
| `POST` | `/api/plaid/create_link_token` | session + sub | Start Plaid Hosted Link |
| `POST` | `/api/plaid/complete_hosted_link` | session + sub | Finish linking, store the item |
| `GET` | `/api/plaid/accounts` | session + sub | Balances |
| `GET` | `/api/plaid/transactions` | session + sub | Transactions (`/transactions/sync`) |
| `GET` | `/api/plaid/recurring` | session + sub | Detected subscriptions |
| `DELETE` | `/api/account` | session | Delete the user + all their data |

"sub" = active subscription required (bypassed while `ALLOW_FREE_PREMIUM=true`).

## Deploy

Any Node 18+ host works (Railway, Render, Fly.io, a VPS). Set the `.env`
variables as the host's environment variables, ensure the working directory is
writable (for `klowop.db` — or mount a volume), and point the app's
**Settings → Backend URL** at the deployed HTTPS URL.

## Production hardening

- [x] **StoreKit chain validation** — implemented via Apple's official
  `@apple/app-store-server-library`. To enable in production:
  1. Download **AppleRootCA-G3.cer** from <https://www.apple.com/certificateauthority/>.
  2. Set `APPLE_ROOT_CA_BASE64` to its base64 (`base64 -i AppleRootCA-G3.cer | tr -d '\n'`),
     or drop the file at `server/certs/AppleRootCA-G3.cer`.
  3. Set `STOREKIT_STRICT=true`, `APPLE_ENVIRONMENT=Production`, and
     `APPLE_APP_APPLE_ID=<your numeric App Store ID>`.
  Leave `STOREKIT_STRICT=false` for local Xcode StoreKit testing (those
  transactions aren't signed by Apple and would fail strict validation).
- [x] **Persistent storage** — set `DATABASE_PATH` to a path on a persistent
  volume. On Railway: add a **Volume** mounted at `/data`, then set
  `DATABASE_PATH=/data/klowop.db` so accounts survive redeploys.
- [ ] **Rate-limit** `/api/assistant/messages` per user; keep a hard Anthropic
  billing cap (Anthropic console → Usage limits).
- [ ] HTTPS (the host provides it) and a strong `SESSION_SECRET`.
- [ ] Move to **Postgres** if you outgrow SQLite.

## Going live checklist

1. Add a Railway Volume + `DATABASE_PATH=/data/klowop.db`.
2. Enable strict StoreKit (`STOREKIT_STRICT=true` + Apple root cert + app id).
3. Switch Plaid to production (`PLAID_ENV=production`, production secret).
4. Set `ALLOW_FREE_PREMIUM=false` so only subscribers get premium.
