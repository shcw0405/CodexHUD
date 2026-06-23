# CodexHUD

CodexHUD is a tiny macOS menu bar app that keeps real Codex usage visible without opening Codex or clicking through another utility.

For the main project overview and screenshots, see the repository root `README.md`.

## Data Source

CodexHUD uses the local Codex CLI app-server JSON-RPC interface:

```sh
codex -s read-only -a untrusted app-server
```

It calls `account/rateLimits/read` for the 5-hour and weekly windows, and `account/read` for account labels when available. It does not use mock usage data, browser cookies, prompt logs, or session files.

## Build In This Workspace

SwiftPM is included through `Package.swift`, but this machine's CommandLineTools manifest loader currently fails on even a temporary empty package. The Makefile builds directly with `swiftc`:

```sh
make test
make build
make run
```

The app binary is written to:

```text
.build/CodexHUD.app
```

## Real RPC Probe

To verify the installed Codex CLI returns usage windows:

```sh
make probe
```

## First Version

- Menu bar title: full, compact, or minimal.
- Used or remaining percentage display.
- 5-hour and weekly windows.
- Reset countdowns in the detail menu.
- Manual refresh.
- Refresh interval settings: 10s, 30s, 60s, 5m.
- Error state: `Cdx ?`.
- Stale state: `Cdx stale`.
