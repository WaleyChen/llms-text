# README

## Prerequisites

- Ruby 3.2.2
- PostgreSQL (running locally)
- Chrome or Chromium (used by [Ferrum](https://github.com/rubycdp/ferrum) for JavaScript-rendered pages)

## Setup

```bash
git clone https://github.com/WaleyChen/llms-text.git
cd llms-text
bundle install
bin/rails db:create
bin/rails db:migrate
bin/dev
```

The app will be available at `http://localhost:3000`.

### Environment variables

LLM-powered generation is optional. Without API keys, the app falls back to a URL-based grouping algorithm.

| Variable | Required | Description |
|---|---|---|
| `OPENAI_API_KEY` | No | Enables GPT-powered section grouping and descriptions |
| `ANTHROPIC_API_KEY` | No | Enables Claude-powered section grouping and descriptions |
| `DATABASE_URL` | Production only | PostgreSQL connection string |
| `RAILS_MASTER_KEY` | Production only | Decrypts `config/credentials.yml.enc` |
| `ACTION_CABLE_ORIGIN` | Production only | Allowed WebSocket origin for real-time updates |

Set these in your shell or in a `.env` file (the app does not load `.env` automatically; use `export` or a tool like [direnv](https://direnv.net/)).
