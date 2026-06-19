# Hermes on Railway

Deploy [Hermes Agent](https://hermes-agent.nousresearch.com/) on [Railway](https://railway.com) with a Telegram gateway — no extra databases or queues.

## Architecture

```
┌─────────────────────────────────────┐
│         Railway Service             │
│                                     │
│  ┌─────────────┐   ┌────────────┐  │
│  │  Dockerfile  │──▶│ entrypoint │  │
│  │  (install)   │   │  (.env)    │  │
│  └─────────────┘   └─────┬──────┘  │
│                          │         │
│                   ┌──────▼──────┐  │
│                   │ hermes      │  │
│                   │ gateway run │  │
│                   │ (polling)   │  │
│                   └─────────────┘  │
└─────────────────────────────────────┘
         │
         ▼ Telegram (polling)
```

## Required Railway Variables

Set these in your Railway service's **Variables** tab:

| Variable | Required | Description |
|---|---|---|
| `TELEGRAM_BOT_TOKEN` | ✅ **Yes** | Bot token from [@BotFather](https://t.me/BotFather) |
| `TELEGRAM_ALLOWED_USERS` | ✅ Recommended | Comma-separated Telegram user IDs (e.g., `123456789,987654321`) |
| `STEPFUN_API_KEY` | ⚠️ One provider key | StepFun API key |
| `ANTHROPIC_API_KEY` | ⚠️ One provider key | Anthropic API key |
| `OPENROUTER_API_KEY` | ⚠️ One provider key | OpenRouter API key |
| `OPENAI_API_KEY` | ⚠️ One provider key | OpenAI API key |

At least one provider API key must be set so the model can generate responses.

## Deploy

```bash
# If you haven't linked the project yet
railway login
railway init

# Deploy from current directory
railway up
```

Railway auto-detects the `Dockerfile` at the repo root.

## Verify

Send `/status` to your Telegram bot. A healthy response means the gateway is running and the model provider is configured.

## Persistence

- **Ephemeral storage:** `~/.hermes/` (skills, sessions, memories) is wiped on every redeploy.
- **Config regeneration:** The entrypoint recreates `.env` from Railway Variables each start — always fresh.
- **Railway Volumes:** Mount a volume at `/root/.hermes/` to persist data across redeploys.

## Model Configuration

After first deploy, configure your model via `railway ssh`:

```bash
hermes model
```

Or set a default model via `~/.hermes/config.yaml` if needed.
# deployed via GitHub
