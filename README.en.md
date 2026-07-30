# SNUHAI CLI

**Run [OpenAI Codex CLI](https://github.com/openai/codex) against your own internal
LLM server — on air-gapped machines with no internet access.**

[한국어](README.md) · **English** · [中文](README.zh-CN.md) · [Español](README.es.md)

Built for the intranet of Seoul National University Hospital (SNUH), but it works
with **any internal LLM server that exposes an OpenAI-compatible API**.

---

## Quickstart

**① On a machine with internet — once.** Build the bundle.

```bat
git clone https://github.com/vitaldb/snuhai-cli.git
cd snuhai-cli
make_snuhai.bat
```

```bash
./make_snuhai.sh          # building from Linux/macOS
```

This produces a single `snuhai-cli.zip` (~180 MB).

**② Copy that ZIP to the air-gapped machine**, unzip it, and double-click `snuhai.bat`.

```
snuhai-cli/
├── snuhai.bat        ← the only thing you run (Windows)
├── snuhai.sh         ← Linux
└── .snuhai/          ← everything it needs (don't delete)
```

**Nothing needs to be pre-installed** on the target machine — not even Node.js.

---

## First run

It asks three things once, then starts straight away every time after that.

```console
============================================================
  snuhai first-time setup
============================================================

 [1] Internal LLM server URL
     Press Enter to use the Seoul National University Hospital default.
     default: https://llm.snuh.org/llm
Server URL (Enter = default):

 [2] How to get an API key (from the intranet)
     1. Open  https://ai.snuh.org  in your browser
     2. Sign in with your SNUHUB account
     3. Left menu:  MY > My Key Management   (ai.snuh.org/setting/my-key)
     4. Click  + Add  (top right)
     5. Choose type LLM, give it a name such as snuhai-cli, and issue it
     6. Copy the key value (starts with sk-) and paste it below
        (right-click in this window = paste)

API key:

 Fetching available models...
Model name:
```

*(The bundle speaks Korean by default; the flow is identical.)*

Settings are stored in `%USERPROFILE%\.snuhai` (Linux: `~/.snuhai`).

## Usage

Arguments are passed straight through to codex.

```bat
snuhai.bat                                 :: interactive
snuhai.bat exec "explain what this repo does"
```

---

## How it works

Recent Codex CLI versions only speak the **Responses API** — `wire_api = "chat"` was
removed in February 2026. But vLLM and litellm, the usual internal deployments, often
only offer **Chat Completions**.

On startup `snuhai` **probes whether your server supports the Responses API**:

- if it does → connect **directly**
- if it doesn't → start the **gateway** automatically

The gateway (`.snuhai/gateway.js`) is a single dependency-free Node file. It **stores no
keys** — it forwards your `Authorization` header upstream as-is, binds to `127.0.0.1`
only, and exits together with codex. It also normalizes the **system message to the
front**, which avoids the `System message must be at the beginning` error some models return.

## Changing settings

| Goal | How |
|---|---|
| Reconfigure server / key / model | Delete `%USERPROFILE%\.snuhai\conf.bat` (Linux: `~/.snuhai/conf.sh`) and run again |
| Change only the model | Edit `MODEL=` in that same file |
| Reinstall | Delete `.snuhai\installed.flag` and run again |

## Troubleshooting

| Symptom | Fix |
|---|---|
| `401` | Wrong key — delete the config file and run again |
| `400 System message must be at the beginning` | Set `GW=1` in the config file and rerun |
| `Model metadata ... not found` | **Harmless.** Ignore it |
| No model list appears | Check the server URL and key |
| "`.snuhai` folder is missing" | You didn't copy the whole folder |
| `Permission denied` on Linux | Run `bash snuhai.sh` (permissions repair themselves afterwards) |
| Prompts skipped when scripting input | Run with `set SNUHAI_NO_UTF8=1` — under a UTF-8 console, `set /p` cannot read redirected stdin (a cmd defect) |

## Security

- **Never commit API keys.** Settings live only in `~/.snuhai` on each machine.
- The gateway listens on `127.0.0.1` only. Do not expose it.
- Point it at an **internal** LLM server so internal data does not leave your network.

## What gets bundled · License

`make_snuhai` downloads everything **verbatim from public sources** and verifies each
artifact against the hash published by npm, writing the evidence to
`.snuhai/packages/PROVENANCE.txt`.

- Code in this repository (`gateway.js`, scripts, docs): **Apache-2.0** (`LICENSE`)
- **OpenAI Codex CLI is not included in this repository** — Apache-2.0, see `NOTICE`
- Node.js is not included either; it is downloaded from nodejs.org (MIT and others)
- "OpenAI" and "Codex" are trademarks of OpenAI. This project is not affiliated with,
  nor endorsed by, OpenAI.
