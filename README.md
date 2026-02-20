# llms.txt Generator

A web app that crawls a website and generates an [llms.txt](https://llmstxt.org/) file -- a structured markdown file that helps LLMs understand and navigate site content.

**Live App:** https://llmstxt.dev/

<img width="797" height="387" alt="Screenshot 2026-02-19 at 7 40 55 PM" src="https://github.com/user-attachments/assets/7436fd72-af62-4583-adfe-23cdae080d52" />

## How It Works

1. **URL Validation** — The submitted URL is validated (format, DNS resolution, SSRF protection) and checked for reachability via Faraday with redirect following.
2. **Crawling** — A concurrent crawler (4 threads) traverses the site, respecting max pages and max depth limits. It extracts page titles, descriptions, and content using Nokogiri. JavaScript-rendered pages are detected and fetched via a headless Chrome browser (Ferrum). Crawl results are cached for 1 day.
3. **LLM Generation** — Two parallel LLM calls run simultaneously:
   - **Grouping** — Groups the crawled URLs into logical sections (e.g. Overview, Docs, Blog).
   - **Enrichment** — Generates clean titles and LLM-optimized descriptions for each URL. Results are cached per URL for 30 days.
4. **Output** — The grouped and enriched data is assembled into a Markdown file following the [llms.txt specification](https://llmstxt.org/). Results are streamed to the browser in real time via a WebSocket.

Supports Claude Sonnet 4.5 and GPT-5.2, or a no-model fallback that groups pages by URL path structure.

## Setup Prerequisites
1. Ruby 3.2.2 & Rails 8.0.4
   - Follow the install instructions at https://guides.rubyonrails.org/install_ruby_on_rails.html
2. PostgreSQL 15.14
   - Use Homebrew to install via `brew install postgresql@15`
3. Anthropic & OpenAI API Keys (Optional for LLM generation)
   - Sign up and get an Anthropic API Key at https://platform.claude.com/settings/keys
   - Sign up and get an OpenAI API Key at https://platform.openai.com/api-keys

## Setup Application

Ensure you have all the Prerequisites setup.

```bash
git clone https://github.com/WaleyChen/llms-text.git
cd llms-text
bundle install
bin/rails db:prepare
bin/dev
```

The app will be available at `http://localhost:3000`.

### Setup API keys

To enable LLM generation of llms.txt:
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
5. Provision a Database: https://devcenter.heroku.com/articles/getting-started-with-rails8#provision-a-database
6. Deploy the App to Heroku: https://devcenter.heroku.com/articles/getting-started-with-rails8#deploy-the-app-to-heroku
7. Migrate the Database: https://devcenter.heroku.com/articles/getting-started-with-rails8#migrate-the-database
8. Scale and Access the Application: https://devcenter.heroku.com/articles/getting-started-with-rails8#scale-and-access-the-application
