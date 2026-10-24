# CLW v2.4 — Codex Limit Watch

1. Extract the archive, double-click `Install.command` once, and then open **CLW** from Applications or Spotlight.
2. Opening CLW starts the monitoring agent. Closing its only window or choosing Quit CLW removes the launch agent and stops future checks. CLW does **not** monitor while closed.
3. In System Settings → Notifications, allow notifications for **CLW**. If the worker appears separately in the list, allow notifications for it as well.
4. Set TEST/PROD, 5-hour/Week, ≥/≤, threshold, interval, and macOS/Telegram destination. Settings save automatically.
5. If CLW reports "Codex executable not found", a hidden path field appears automatically under Check limits. In Terminal run `command -v codex`, paste the resulting executable path and click **Save path & retry**. Normal automatic discovery remains the default.
6. Telegram requires a bot token and Chat ID. For the chat ID, send `/start` to your bot and press Find Chat ID.

In TEST mode a message is sent after every successful check. In PROD it is sent when remaining quota crosses the threshold in the selected direction. Errors on scheduled checks produce a short error notification and are retried at the next interval.

A lightweight background worker is installed at `/Applications/CLWWorker.app` (hidden from Dock). launchd only starts it while CLW is running. During sleep polling pauses; resume may be delayed.

No API key required if the Codex CLI can access the local ChatGPT login.


## Automatic setup
Install.command places CLW.app and its background worker in ~/Applications without sudo or administrator password. The Codex path field remains hidden unless Check limits reports that the executable could not be found. If no CLI exists, Codex.app being open does not guarantee access to the App Server. The system may independently request access to the macOS Keychain for a stored Telegram bot token.


## Dock icon duplicates (v2.5)
Only the settings window should appear in Dock. Scheduled checks and the Send test / Check limits actions run through CLWWorker.app, an agent-only (LSUIElement) helper. If older versions are installed in both `/Applications/CLW.app` and `~/Applications/CLW.app`, remove the older copy and remove old Dock shortcuts, then start `~/Applications/CLW.app`.


### v2.7 changes
- Background worker is a command-line executable inside `CLW.app/Contents/Helpers`, not a second application. It does not create Dock icons.
- Settings and clicks do not write the Telegram token repeatedly. To avoid ad-hoc code-signing Keychain password prompts, the token is now stored at `~/Library/Application Support/CodexLimitWatch/telegram-token.txt` with owner-only permissions (0600); the directory is 0700. Re-enter your token once after updating. Other processes running as your macOS user can potentially read it.
- Codex is automatically searched in `fnm` installs before showing an optional executable-path field.
- The executable path field stays hidden unless **Check limits** reports that Codex was not found.
- Old `~/Applications/CLWWorker.app` is removed by the installer. You may also have an older `/Applications/CLW.app`; remove it manually if unwanted.
- No administrator password should be required; macOS may ask for first-launch security consent.

## Window sizing
The settings window has increased vertical space. When the Codex executable is not found, the fallback path section expands the window by an additional 215 pt to keep its instructions, text field, and retry button visible.

### Window layout (v2.8)
The settings window adjusts its height to visible content automatically, including Telegram controls and the optional Codex executable field.


## macOS notification delivery (v2.9)
CLW uses the native `UNUserNotificationCenter` API from the main CLW.app process.
The background CLI worker only queues macOS messages on disk. CLW reads that queue while open and delivers notifications under its application identity. Closing CLW stops the launchd schedule.
A new notification bundle identifier (`app.clw.notifications`) is used to let macOS request CLW permission again. Allow the prompt, or use System Settings → Notifications → CLW.
macOS and Telegram settings and existing Codex authentication stay unchanged.
