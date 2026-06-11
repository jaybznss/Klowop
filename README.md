# Klowop

A native iOS app that runs your whole life from one place, designed to look and feel like it shipped with the iPhone.

| Area | What it does |
|---|---|
| **Today** | Daily dashboard: schedule, to-dos, calories vs. goal, weekly spending |
| **Agenda** | Calendar with **two-way Google Calendar sync** (OAuth, no password stored) |
| **Food** | Meal logging with calories and macros, daily goal ring, history by day — plus **Apple Health**: Apple Watch activity (calories burned, steps, exercise) and body composition from smart scales like the Hume BodyPod, with net-calorie math. Logged meals write back to Health. |
| **Money** | Bank accounts and transactions via **Plaid**, automatic **subscription detection** with renewal reminders |
| **Assistant** | A secretary you can talk to, powered by **Claude** with streamed replies. It schedules events, manages to-do lists, logs what you eat, and answers questions about your money and health — by actually using the app's data, not guessing |
| **Widgets** | Small & medium home-screen widgets: calorie ring, next events, open to-dos |

## How it's built

- **SwiftUI + SwiftData**, iOS 26+ — built against the modern SDK so it adopts **Liquid Glass** (floating minimizing tab bar, glass input bar and buttons) and feels first-party on iOS 26/27.
- **Claude API** (`claude-opus-4-8`) with tool use: the assistant calls 8 tools (`add_calendar_event`, `log_meal`, `get_finance_overview`, …) that read/write the local database.
- **Google Calendar**: OAuth 2.0 + PKCE via `ASWebAuthenticationSession`, syncing against the Calendar v3 REST API.
- **Plaid**: bank linking through **Hosted Link** (browser-based — no native Plaid binary in the app). The Plaid secret never touches the phone — a tiny Node companion server in [`server/`](server) creates link sessions, exchanges tokens, and serves balances, transactions (`/transactions/sync`), and recurring-stream detection.
- All secrets (API keys, OAuth tokens) live in the iOS **Keychain**.

## Repository layout

```
Klowop/            iOS app source (SwiftUI)
  Models/          SwiftData models (meals, events, todos, accounts, …)
  Services/        Claude assistant, Google Calendar, Plaid, Keychain
  Views/           Today, Agenda, Nutrition, Finances, Assistant, Settings
project.yml        XcodeGen spec — generates Klowop.xcodeproj
server/            Node companion server for Plaid
SETUP.md           Step-by-step setup (Xcode, Anthropic, Google, Plaid)
```

## Quick start

```bash
brew install xcodegen
xcodegen generate
open Klowop.xcodeproj
```

Then follow **[SETUP.md](SETUP.md)** to wire up the three integrations (≈25 minutes total). The app runs fine before any of them are configured — integrations light up as you add keys in Settings.
