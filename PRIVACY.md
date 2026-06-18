# Klowop Privacy Policy

_Last updated: [DATE]_

Klowop ("the app," "we," "us") is a personal life-management app for iPhone. This
policy explains what data Klowop handles, where it lives, and the choices you have.
We designed Klowop to keep your data on your device wherever possible.

**Contact:** [your support email]

---

## The short version

- Most of your data — meals, events, to-dos, budgets, manually entered finances —
  is stored **only on your iPhone** (and in your private iCloud, if enabled).
- Some features require a server (these are part of the optional paid tier):
  the **AI assistant** and **automatic bank-linking**. For those, data is sent to
  our backend and to the providers that power them.
- We **never sell your data**, never use it for advertising, and never use Apple
  Health data for anything other than showing it to you inside the app.
- You can **delete your account and all server-side data** at any time from
  Settings, and deleting the app removes the on-device data.

---

## What we collect and why

### Stored on your device only
Meals and nutrition, calendar events you create, to-do lists, budgets, manually
entered accounts and transactions, subscriptions, and your assistant chat history
are stored locally on your device using Apple's SwiftData. We do not receive or
store this data on our servers.

### Apple Health (HealthKit) — read and write, on device
If you connect Apple Health, Klowop **reads** activity (active energy, steps,
exercise minutes) and body composition (weight, body fat, lean mass) to display
alongside your food log, and **writes** the meals you log back to Health. This
data is used solely to provide app features, is processed on your device, and is
**never transmitted to our servers, sold, shared, or used for advertising**, in
accordance with Apple's HealthKit requirements. You control access in the iOS
Health app at any time.

### Account (Sign in with Apple)
To use the paid features, you sign in with Apple. We receive a stable, anonymized
Apple user identifier and (if you choose to share it) your email, which we store on
our backend to identify your account and your subscription. We do not receive your
name or Apple password.

### AI assistant (paid feature)
When you use the assistant, the messages you send and the relevant data the
assistant reads to answer (e.g. today's events or your budget totals) are sent to
our backend, which forwards them to **Anthropic** (the Claude API) to generate a
response. We do not use your conversations to train models. See Anthropic's
privacy terms at anthropic.com.

### Automatic bank-linking (paid feature)
If you link a bank account, the connection is handled by **Plaid**. Plaid
authenticates with your bank and returns account balances, transactions, and
recurring-payment information to our backend, which relays it to your app. We store
Plaid access tokens and the returned financial data on our backend, isolated to
your account. We never see or store your bank login credentials — those go directly
to Plaid. See Plaid's privacy policy at plaid.com/legal.

### Google Calendar (optional)
If you connect Google Calendar, the app reads and writes events using credentials
that stay on your device. Calendar data syncs directly between your device and
Google; it does not pass through our servers.

### Diagnostics
Our backend keeps minimal operational logs (timestamps, error messages) to keep the
service running. These are not used to profile you and are not shared.

---

## Third parties we use

| Provider | Purpose | What they receive |
|---|---|---|
| **Apple** | Sign in with Apple, subscriptions, HealthKit | Account identifier; purchase records |
| **Anthropic** | AI assistant responses | Your assistant messages and the context needed to answer |
| **Plaid** | Bank-linking | Your bank authentication (directly) and returned financial data |
| **Google** | Calendar sync (optional) | Calendar events (directly from your device) |

We share data with these providers only to deliver the feature you requested, and
only the data needed for it.

---

## Your choices and rights

- **Use the app without an account:** tracking, calendar, and manual finance work
  with no sign-in.
- **Delete your account:** Settings → Account → Delete account removes your account
  and all server-side data (bank links, subscription records).
- **Delete on-device data:** delete the app, or remove items individually.
- **Revoke Health access:** in the iOS Health app, anytime.
- **Disconnect Google or a bank:** in the app's Settings / Money tab.

Depending on where you live, you may have rights to access, correct, or delete your
personal data. Contact us at the email above to exercise them.

---

## Data retention & security

On-device data persists until you delete it. Server-side data persists until you
delete your account. We use industry-standard encryption in transit (HTTPS) and
restrict access to our backend. No method of transmission or storage is 100%
secure, but we take reasonable measures to protect your data.

## Children

Klowop is not directed to children under 13 and we do not knowingly collect data
from them.

## Changes

We may update this policy; material changes will be reflected by the "Last updated"
date above.
