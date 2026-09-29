# BillionTokens

A macOS menu bar app that shows how much of your AI coding limits you have used. It tracks OpenAI Codex, Anthropic Claude and Google Antigravity in one place, with reset times for each.

**macOS only.** It is a native AppKit app and will not build or run on Linux or Windows.

## What it shows

| Provider | Short window | Long window | Extra |
|---|---|---|---|
| OpenAI Codex | 5-hour usage and reset time | Weekly usage | Reset credits, plan |
| Anthropic Claude | Current session usage and reset time | Weekly usage (all models) | Account, rate-limit tier |
| Google Antigravity (opt-in) | 5-hour usage | Weekly usage | Last active time |

The numbers appear in three places:

- **Menu bar:** each provider's icon with its current short-window percentage.
- **Notch display:** on MacBooks with a notch, a black strip sits flush around the notch. Click it to cycle through providers; double-click to open the full panel. It cannot be dragged.
- **Full panel:** press `Fn + Control`, or click the menu bar icon, to open a panel with every bar, reset time and account detail. `Esc` closes it. The footer has a `Notch: On/Off` toggle and a Copy button that puts a plain-text summary on the clipboard.

Data refreshes every 3 minutes, or when you press Refresh.

## Requirements

- macOS 13 Ventura or later. The notch display needs a Mac with a notch; on other Macs the menu bar and panel still work.
- Xcode Command Line Tools, for `swiftc` (`xcode-select --install`).
- Python 3 at `/usr/bin/python3` (installed with the Command Line Tools).
- The CLIs for the providers you want to track, already signed in:
  - Codex: the `codex` CLI on your `PATH`.
  - Claude: the `claude` CLI (Claude Code) on your `PATH`.
  - Antigravity: the Antigravity app, signed in.

You only need one of them. A provider that isn't installed shows "Not installed" in the panel and is left out of the menu bar and notch display. Install it later and it appears on the next refresh.

## Install

```bash
git clone https://github.com/410n3/billiontokens.git
cd billiontokens
./build.sh
open ~/Applications/BillionTokens.app
```

`build.sh` compiles `main.swift`, builds `BillionTokens.app` and copies it to `~/Applications`. The app is not signed or notarized. If you move it somewhere macOS quarantines it, right-click the app and choose Open the first time.

If `Fn + Control` does nothing, allow BillionTokens under System Settings > Privacy & Security > Accessibility.

To start it at login, add it under System Settings > General > Login Items.

## Configuration

Settings live in `~/Library/Application Support/BillionTokens/config.json`. Without that file, Codex and Claude are on and Antigravity is off.

```json
{
  "providers": {
    "codex": true,
    "claude": true,
    "antigravity": true
  }
}
```

## How it gets the numbers

`collector.py` does the fetching and prints one JSON object. You can run it on its own to see exactly what the app sees:

```bash
python3 collector.py --force
```

- **Codex:** starts `codex app-server --listen stdio://` and calls `account/rateLimits/read` over JSON-RPC.
- **Claude:** reads account details from `~/.claude.json` and parses the output of `claude -p --no-session-persistence /cost`. `/cost` runs locally and does not send a prompt to the model, so polling does not use your Claude quota. The most recent token counts come from session files in `~/.claude/projects/`.
- **Antigravity:** reads the Antigravity sign-in token from the macOS Keychain and calls `cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary`. That endpoint is internal and undocumented. Google can change or block it at any time, which is why this provider is off by default. The token is used for that one request and is never written to disk or logs. When the token expires, the panel says "Token expired"; opening Antigravity refreshes it.

## Privacy

Everything runs on your Mac. BillionTokens has no server, no analytics and no network calls of its own apart from the Antigravity quota request above. Codex and Claude data comes from their own CLIs.

It reads these local files:

- `~/.claude.json` and `~/.claude/projects/*/*.jsonl` (Claude account and token counts)
- `~/.gemini/antigravity-cli/` history and logs (Antigravity last-active time and email)
- One Keychain entry, for Antigravity, only when that provider is on

Results are cached for 45 seconds in `~/Library/Caches/BillionTokens/cache.json`, readable only by your user. The cache includes account emails. Screenshots of the panel will show them too.

## Project layout

```
main.swift     AppKit app: menu bar item, notch display, panel
collector.py   Fetches limits from each provider, prints JSON
build.sh       Compiles and installs to ~/Applications
assets/        Provider icons
```

## Contributing

Issues and pull requests are welcome. After changing `main.swift`, run `./build.sh` and relaunch:

```bash
killall BillionTokens 2>/dev/null; open ~/Applications/BillionTokens.app
```

Adding a provider means adding a `get_<name>_limits()` function to `collector.py` that returns the same shape as the existing ones, then a section in the panel.

## License

MIT. See [LICENSE](LICENSE).

OpenAI, Codex, Anthropic, Claude, Google and Antigravity are trademarks of their owners. This project is not affiliated with or endorsed by any of them.
