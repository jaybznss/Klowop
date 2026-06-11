# Klowop Setup Guide

Four steps. You need a Mac with Xcode 15+ for step 1. Each integration is independent — the app works before any keys are added, and features light up as you configure them in the app's **Settings** (gear icon in the Assistant tab).

---

## 1. Build the app (~5 min)

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
cd Klowop          # repo root
xcodegen generate
open Klowop.xcodeproj
```

In Xcode: select the **Klowop** scheme, pick your iPhone or a simulator, set your signing team (Signing & Capabilities → Team), and press **Run**. Xcode resolves the Plaid LinkKit Swift package automatically on first build.

> If the LinkKit version pinned in `project.yml` ever fails to resolve, bump the `from:` version — Plaid occasionally retires old majors.

---

## 2. Claude assistant (~3 min)

1. Go to [console.anthropic.com](https://console.anthropic.com) → **API Keys** → **Create Key**.
2. Add a small amount of credit (Billing). Personal use is typically a few dollars per month.
3. In the app: **Assistant tab → gear icon → Assistant → paste the key** (`sk-ant-…`).

That's it — ask it to schedule something. The key is stored in the iOS Keychain and requests go directly from your phone to Anthropic.

---

## 3. Google Calendar sync (~10 min)

1. Go to [console.cloud.google.com](https://console.cloud.google.com) and create a project (e.g. "Klowop").
2. **APIs & Services → Library** → search **Google Calendar API** → **Enable**.
3. **APIs & Services → OAuth consent screen**: choose **External**, fill in the app name and your email, and add yourself as a **test user** (that's enough — no verification needed for personal use).
4. **APIs & Services → Credentials → Create Credentials → OAuth client ID**:
   - Application type: **iOS**
   - Bundle ID: `com.jaybznss.Klowop` (or whatever bundle id you build with)
5. Copy the **Client ID** (looks like `1234567890-abc123.apps.googleusercontent.com`).
6. Register the redirect URL scheme: in `project.yml`, replace
   `com.googleusercontent.apps.YOUR_GOOGLE_CLIENT_ID` with the **reversed** client id —
   everything before `.apps.googleusercontent.com`, prefixed:
   `com.googleusercontent.apps.1234567890-abc123` — then re-run `xcodegen generate`.
7. In the app: **Settings → Google Calendar → paste the Client ID → Connect Google Calendar**, and sign in.

Sync is two-way against your primary calendar: local events push to Google, Google events (30 days back, 1 year ahead) pull in. Use the sync button in the Agenda tab, or it syncs automatically when the tab opens.

---

## 4. Bank linking with Plaid (~10 min)

Plaid requires a server-side secret, so a small companion server (in `server/`) does the token exchange. Run it on your Mac (simulator) or any always-on machine (Raspberry Pi, cheap VPS) for use on the go.

1. Create a free account at [dashboard.plaid.com](https://dashboard.plaid.com) and get your **client_id** and **sandbox secret** (Team Settings → Keys).
2. Start the server:

   ```bash
   cd server
   cp .env.example .env    # fill in PLAID_CLIENT_ID and PLAID_SECRET
   npm install
   npm start               # listens on http://localhost:8484
   ```

3. In the app: **Settings → Bank linking** — the default `http://localhost:8484` works in the simulator. On a physical iPhone, use your Mac's LAN address (e.g. `http://192.168.1.20:8484`).
4. **Money tab → Link a bank account**. In sandbox mode, log in with Plaid's test credentials: username `user_good`, password `pass_good`.

Balances, transactions, and detected subscriptions then sync into the Money tab (and the assistant can see them). To connect **real** banks, request Production access in the Plaid dashboard and switch `PLAID_ENV=production` in `.env`.

> **Note on countries:** set `PLAID_COUNTRY_CODES` in `.env` (e.g. `US,CA` or `FR,ES,NL`) to match where your banks are.

---

## 5. Apple Health (~1 min)

No developer setup needed — the HealthKit capability is already in `project.yml`.

1. Run the app on a **physical iPhone** (the simulator has no Watch or scale data).
2. **Settings → Apple Health → Connect Apple Health** and allow all categories.

What you get:

- **Activity card** in the Food tab: active calories burned, steps, and exercise minutes from your Apple Watch, plus net intake (eaten − burned).
- **Body card**: latest weight, body fat %, and lean mass. The **Hume BodyPod** (and most smart scales) sync these to Apple Health automatically — make sure Health sync is enabled in the Hume/Eufy app, and they'll flow straight into Klowop.
- Every meal you log (manually or via the assistant) is written to Apple Health as dietary energy/protein/carbs/fat, and removed from Health if you delete it in the app.
- The assistant can answer "how much did I burn today?" or "what's my weight trend?" via its `get_health_summary` tool.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| Assistant says "Add your Anthropic API key" | Settings → Assistant → paste key |
| Google sign-in window closes immediately | The URL scheme in `project.yml` doesn't match your client ID — redo step 3.6 and `xcodegen generate` |
| "Plaid server: request failed" | Server not running, or wrong URL in Settings (use LAN IP on a real device) |
| Bank link succeeds but no transactions | Sandbox data can take a few seconds; pull-to-refresh or tap the sync arrows in the Money tab |
| Build error in `PlaidService.swift` | LinkKit package didn't resolve — File → Packages → Resolve Package Versions |
