# Klowop — App Store Release Plan

Turning Klowop from "runs on my phone" into a published, multi-user App Store app.
Chosen path: **hosted backend + subscription**, **Plaid in v1**, **freemium/subscription** pricing.

Legend: **[me]** = Claude builds it in this repo · **[you]** = needs your account/credentials/action.

---

## Phase 0 — Accounts & prerequisites  (you, ~1–2 hrs + waiting)

- [ ] **[you]** Apple Developer Program membership ($99/yr) — required to ship anything.
- [ ] **[you]** Create the app record in **App Store Connect** (bundle id `com.jaybznss.Klowop`).
- [ ] **[you]** **Plaid Production** access — submit their security/compliance questionnaire (financial-data review; can take days).
- [ ] **[you]** **Google OAuth verification** for the Calendar scope (privacy-policy URL + demo video), OR stay in "Testing" (capped at 100 users) for an early launch.
- [ ] **[you]** A place to **host the backend** (Railway, Render, Fly.io, or a small VPS) + a domain.
- [ ] **[you]** **Anthropic** production API key with a billing cap (the backend holds this, not the app).

## Phase 1 — Backend  (me, in progress)

The server in [`server/`](server) becomes a real multi-user backend:
- [x] **[me]** Sign in with Apple token verification → issues our own session JWT.
- [x] **[me]** Claude assistant **proxy** (holds the Anthropic key; the app never sees it).
- [x] **[me]** **StoreKit 2** subscription verification (signed-transaction JWS) → per-user entitlement.
- [x] **[me]** Subscription **gating** middleware on premium endpoints (AI + Plaid).
- [x] **[me]** Plaid endpoints, now **per-user** and auth-gated.
- [x] **[me]** Account + data **deletion** endpoint (App Store requirement).
- [ ] **[you]** Fill `server/.env` with real credentials; deploy; note the public URL.

## Phase 2 — iOS: accounts, paywall, routing  (me)

- [ ] **[me]** **Sign in with Apple** screen + capability.
- [ ] **[me]** **StoreKit 2** products, paywall, and entitlement state.
- [ ] **[me]** Route the **assistant** through the backend (remove the in-app API-key field).
- [ ] **[me]** Route **Plaid** through the authenticated backend.
- [ ] **[me]** Gate premium features behind the subscription; graceful free tier.
- [ ] **[you]** Create the **subscription product** in App Store Connect (price, free trial).

## Phase 3 — App Store requirements  (mostly me)

- [ ] **[me]** **Privacy Policy** (health + financial data) — text in repo; **[you]** host it at a URL.
- [ ] **[me]** **Account deletion + data export** UI in Settings.
- [ ] **[me]** Proper **launch screen** and finalized **app icon** (all appearances).
- [ ] **[me]** **Export-compliance** flag (`ITSAppUsesNonExemptEncryption`).
- [ ] **[me]** Accessibility pass (VoiceOver labels, Dynamic Type), empty-state + error polish.
- [ ] **[you]** **App Privacy "nutrition label"** answers in App Store Connect (I'll give you the exact answers).
- [ ] **[you]** Screenshots (I'll provide a shot list), description, keywords, category, age rating, support URL.

## Phase 4 — Submit

- [ ] **[you]** Archive in Xcode → upload → TestFlight → internal test.
- [ ] **[me]** Fix anything review flags.
- [ ] **[you]** Submit for review.

---

## Honest notes
- **Plaid + HealthKit + financial data** make App Review stricter than average. Everything must work or be cleanly gated — no half-features.
- The **backend is now a real service you operate**: uptime, cost (Anthropic + hosting), and security are yours. Keep the Anthropic key capped.
- Cheapest fast path if Plaid/Google reviews stall: ship v1 with manual finance + Google-in-testing, add them once approved. We can pivot without rework.
