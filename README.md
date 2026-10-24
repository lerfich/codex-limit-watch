# CLW — Codex Limit Watch

A lightweight macOS app that monitors your OpenAI Codex usage limits and sends notifications when your custom conditions are met.

## Features

- **5-hour & weekly limits** — monitor remaining Codex quota.
- **macOS & Telegram notifications** — choose where to receive alerts.
- **TEST / PROD modes** — receive updates on every check or only when a condition is met.
- **Custom thresholds** — configure percentages from 5% to 100% using ≥ or ≤ conditions.
- **Flexible polling** — choose how often limits are checked.
- **Auto-save** — settings are applied automatically.
- **Lightweight** — background checks use macOS `launchd`.

## Installation

Clone the repository and run the installer:

```bash
git clone https://github.com/lerfich/codex-limit-watch.git
cd codex-limit-watch
bash Install.command
```

Once installed, open **CLW.app** from `~/Applications` or Spotlight.

For macOS notifications, enable **Allow Notifications** in:

**System Settings → Notifications → CLW**

CLW automatically attempts to use your existing Codex CLI authentication. No additional OpenAI API key is required.

If Codex cannot be found automatically, CLW allows you to specify the executable path.

## How to Use

1. Select **5-hour** or **Week**.
2. Choose **TEST** or **PROD**.
3. Set your preferred polling interval.
4. In PROD, configure a percentage threshold and condition (≥ or ≤).
5. Select macOS or Telegram as your notification destination.

**TEST:** Sends a notification on every successful check.

**PROD:** Sends a notification when the remaining quota crosses the configured threshold, without repeating alerts while the condition remains satisfied.

All settings are saved automatically.

### Telegram Setup

1. Create a bot using [@BotFather](https://t.me/BotFather).
2. Copy the bot token into CLW.
3. Send `/start` to your bot.
4. Use **Find Chat ID** or enter your Chat ID manually.
5. Click **Send Test** to verify delivery.

## Example

Configuration: `PROD · Week · ≥ 98%`

Notification:

`7-day limit: 98%`

CLW monitors your remaining quota and notifies you when the configured condition is met.

## Background Monitoring

CLW uses the built-in macOS `launchd` scheduler to perform periodic checks.

- Polling intervals are configurable.
- Background checks do not require keeping the settings window in focus.
- Monitoring stops when CLW is fully quit.
- Checks are suspended while your Mac is asleep and resume after waking.

## Privacy & Security

CLW runs locally and does not include third-party analytics or telemetry.

- Codex usage data is retrieved through your locally authenticated Codex CLI.
- Settings, usage snapshots, and logs are stored locally in `~/Library/Application Support/CodexLimitWatch/`.
- Telegram bot tokens are stored locally in `telegram-token.txt`, with file permissions restricted to the current user (`0600`).
- Telegram notifications are sent directly to the official Telegram Bot API over HTTPS.
- No Codex API key is required.

**Note:** Telegram tokens are currently stored in a local file, not macOS Keychain. Keep your bot token private and avoid sharing your application data directory.

## Requirements

- macOS (Apple Silicon)
- OpenAI Codex CLI with an authenticated account
- Internet connection
- Apple Command Line Tools (required to build the application)

CLW is an independent, unofficial open-source project and is not affiliated with or endorsed by OpenAI.
