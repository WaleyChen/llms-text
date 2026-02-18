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

### Setting API keys

To enable LLM-powered generation:
1. Get an API key from https://platform.claude.com/settings/keys and https://platform.openai.com/api-keys.
2. Export the keys to your shell:
```bash
export ANTHROPIC_API_KEY=sk-ant-...
export OPENAI_API_KEY=sk-...
```

## Deployment
1. Finish Setup instructions.
2. Sign up for Heroku: https://signup.heroku.com/
3. Create a Heroku app: https://devcenter.heroku.com/articles/getting-started-with-rails8#create-a-heroku-app
4. Setup LLM API keys: https://devcenter.heroku.com/articles/config-vars#using-the-heroku-dashboard
4. Provision a Database: https://devcenter.heroku.com/articles/getting-started-with-rails8#provision-a-database
5. Deploy the App to Heroku: https://devcenter.heroku.com/articles/getting-started-with-rails8#deploy-the-app-to-heroku
6. Migrate the Database: https://devcenter.heroku.com/articles/getting-started-with-rails8#migrate-the-database
7. Scale and Access the Application: https://devcenter.heroku.com/articles/getting-started-with-rails8#scale-and-access-the-application