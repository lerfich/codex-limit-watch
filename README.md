# CLW — Codex Limit Watch

A lightweight macOS app that monitors your OpenAI Codex usage limits and sends notifications when your custom conditions are met.

## Features

- **5-hour & weekly limits** — track remaining Codex quota.
- **macOS & Telegram** — choose where to receive notifications.
- **TEST / PROD modes** — notify on every check or only when a condition is met.
- **Custom thresholds** — set any value from 5% to 100% with ≥ or ≤ conditions.
- **Flexible polling** — choose how often limits are checked.
- **Auto-save** — settings apply instantly.
- **Lightweight** — designed for minimal background resource usage.

## Installation

1. Download and extract the ZIP archive.
2. Run `Install.command`.
3. Open `CLW.app` from `~/Applications`.
4. Enable notifications in **System Settings → Notifications → CLW**.

CLW automatically attempts to use your existing Codex authentication. No additional OpenAI API key is required.

## How to use

1. Select **5-hour** or **Week**.
2. Choose **TEST** or **PROD**.
3. Set the polling interval.
4. In PROD, configure a threshold and condition (≥ or ≤).
5. Choose macOS or Telegram for notifications.

**TEST:** Sends a notification on every successful check.

**PROD:** Notifies when the selected limit crosses your threshold, without repeated alerts while the condition remains true.

For Telegram, create a bot using [@BotFather](https://t.me/BotFather), enter your Bot Token and Chat ID, then use **Send Test**.

## Example

Settings: `PROD · Week · ≥ 98%`

Notification:

`7-day limit: 98%`

CLW checks your quota automatically and notifies you when the condition is reached.

## Requirements

- macOS (Apple Silicon)
- OpenAI Codex with an authenticated CLI
- Internet connection

CLW is an independent, unofficial project and is not affiliated with OpenAI.
