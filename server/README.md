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

## Before production — security hardening

- [ ] **StoreKit chain validation:** `/api/subscription/verify` currently checks
  the signed-transaction JWS against its embedded leaf certificate. Add full
  `x5c` chain validation against **AppleRootCA-G3** (or call the App Store
  Server API) before trusting entitlements — without it, a forged leaf could
  grant a subscription.
- [ ] **Rate-limit** `/api/assistant/messages` per user; keep a hard Anthropic
  billing cap.
- [ ] Put it behind **HTTPS** (the host usually provides this) and set a strong
  `SESSION_SECRET`.
- [ ] Move `klowop.db` to a managed database (Postgres) if you expect scale.
