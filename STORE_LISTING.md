# App Store Connect — listing & privacy answers

Everything you'll paste into App Store Connect. **[you]** fills these in; this is
the reference so the answers match what the app actually does (reviewers check).

---

## App Privacy ("nutrition label")

App Store Connect → your app → **App Privacy**. Declare these data types. For each,
the honest answers for Klowop:

| Data type | Collected? | Linked to user? | Used for tracking? | Purpose |
|---|---|---|---|---|
| **Health & Fitness** | Yes (HealthKit) | **No** — stays on device | No | App Functionality |
| **Financial Info** (Plaid) | Yes | Yes | No | App Functionality |
| **Contact Info — Email** | Yes (Sign in with Apple, optional) | Yes | No | App Functionality |
| **User ID** (Apple identifier) | Yes | Yes | No | App Functionality |
| **User Content** (assistant messages, notes) | Yes | Yes | No | App Functionality |
| **Identifiers / Usage / Diagnostics** | Diagnostics only (logs) | No | No | App Functionality |

Key declarations to get right:
- **Tracking: NO** for everything (we don't track across apps/companies → no App
  Tracking Transparency prompt needed, so no `NSUserTrackingUsageDescription`).
- **Health data is NOT linked and NOT shared** — it never leaves the device.
- "Data Used to Track You": **none**.

---

## HealthKit review note

In **App Review notes**, include: _"Klowop reads Apple Watch activity and body
composition to display alongside the user's food log, and writes logged meals back
to Health. Health data is processed on-device only, never transmitted off the
device, never sold or shared, and never used for advertising."_ This pre-empts the
standard HealthKit review question.

---

## Listing copy

**Name:** Klowop (or "Klowop: Life Manager" if the name is taken)

**Subtitle (30 chars):** Your whole life, one app

**Promotional text:**
> Track what you eat, sync your calendar, watch your money, and just talk to an
> assistant that handles your schedule and lists for you.

**Description (draft):**
> Klowop brings every part of your life into one beautifully simple app.
>
> • TODAY — your day at a glance: schedule, to-dos, calories, and spending.
> • HEALTH — log meals with a real food database and barcode scanning; see your
>   Apple Watch activity and body composition in one place.
> • AGENDA — a clean calendar with two-way Google Calendar sync.
> • MONEY — balances, transactions, budgets, and automatic subscription tracking.
> • ASSISTANT — a secretary you can talk to. It schedules events, keeps your lists,
>   logs your meals, and answers questions about your money.
>
> Tracking, calendar, and manual finance are free. Klowop Pro unlocks the AI
> assistant and automatic bank-linking.
>
> Klowop Pro is an auto-renewing subscription. [price] per month or [price] per
> year after any free trial. Cancel anytime.

**Keywords (100 chars):**
> life,planner,calendar,budget,finance,nutrition,calorie,assistant,ai,todo,health,tracker

**Category:** Primary: Productivity · Secondary: Lifestyle (or Health & Fitness)

**Age rating:** 4+ (no objectionable content)

**Support URL:** [your support page]
**Marketing URL:** [optional]
**Privacy Policy URL:** [where you host PRIVACY.md]

---

## Subscription product setup

App Store Connect → **Subscriptions** → create group "Klowop Pro" with:

| Reference name | Product ID | Duration | Price | Intro offer |
|---|---|---|---|---|
| Klowop Pro Monthly | `com.jaybznss.Klowop.pro.monthly` | 1 month | $4.99 | 1 week free |
| Klowop Pro Yearly | `com.jaybznss.Klowop.pro.yearly` | 1 year | $39.99 | — |

The product IDs **must match exactly** — they're hard-coded in `StoreKitService.swift`.

---

## Screenshots (shot list)

Required: 6.9" (iPhone 16 Pro Max) and 6.5". Take these on-device or in the
simulator (⌘S). Use real-looking data.

1. **Today** — dashboard with the daily briefing card glowing.
2. **Health** — calorie ring + activity + weight trend chart.
3. **Agenda** — the month view or schedule with colorful events.
4. **Money** — accounts + spending chart + budgets.
5. **Assistant** — a chat where it schedules something ("Done! Booked…").
6. **Paywall** — Klowop Pro (optional but converts well).

Add a one-line caption to each in App Store Connect.

---

## Pre-submission checklist

- [ ] Privacy Policy hosted at a public URL; pasted into App Store Connect.
- [ ] App Privacy answers entered (table above).
- [ ] HealthKit review note added.
- [ ] Subscription products created + "Ready to Submit".
- [ ] Screenshots uploaded.
- [ ] `ALLOW_FREE_PREMIUM=false` on the backend (so review tests the real gate),
      OR a demo account provided in review notes.
- [ ] Backend hardened: StoreKit cert-chain validation + persistent storage.
- [ ] Build archived, uploaded, passes TestFlight.
