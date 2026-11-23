# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

`import-demo` is an API-only Rails 8.1 base project (PostgreSQL, Redis cache, Solid Queue/Cable, RSpec, Kamal) used as the starting point for new apps.

## Stack

API-only Rails 8.1 on Ruby 3.4.13 (rbenv, `.ruby-version`). PostgreSQL 17 (`pg`), Redis for `Rails.cache`, Solid Queue (Active Job) and Solid Cable (Action Cable) on the database. No asset pipeline, views or JS (`config.api_only = true`, controllers inherit `ActionController::API`). RSpec (no Minitest). Deploy via Kamal (`config/deploy.yml`, production `Dockerfile`).

## Commands

```bash
docker compose up -d db redis        # start Postgres + Redis (required for dev and specs)
bin/rails db:prepare                 # create/migrate dev + test DBs
bin/dev                              # Rails server on $PORT (23000 with the sample .env)
docker compose up                    # alternative: run Rails in the `web` container too

bin/rspec                            # all specs
bin/rspec spec/requests/health_check_spec.rb:3   # single example by line
bin/rspec --only-failures            # rerun failures (state in tmp/rspec_examples.txt)

bin/rubocop                          # lint (CI uses `bin/rubocop -f github`)
bin/rubocop -a                       # safe autocorrect
bin/ci                               # local CI: setup, rubocop, bundler-audit, brakeman, rspec, seeds

```

## Environment and ports

- `.env` (git-ignored, copy from `.env.example`) is read both by `docker compose` (interpolation) and by Rails in development/test via the `dotenv` gem. Real ENV wins.
- Port convention: defaults in code/compose are the standard ports (3000 / 5432 / 6379); `.env` publishes them on the host with a per-project prefix (`IMPORT_DEMO_RAILS_PORT=23000`, `IMPORT_DEMO_DB_PORT=25432`, `IMPORT_DEMO_REDIS_PORT=26379`) so several projects run side by side. Keep this pattern for any new service.
- Rails on the host reaches services via `DB_HOST/DB_PORT/DB_USERNAME/DB_PASSWORD` and `REDIS_URL` from `.env`; inside the `web` container compose overrides them to the `db:5432` / `redis:6379` service names. CI uses `DATABASE_URL`.
- Rails listens on the same port inside and outside the container (`PORT`), and mailer `default_url_options` follows `PORT`.

## Architecture notes

- **Cache**: `redis_cache_store` is configured once in `config/application.rb` (URL from `REDIS_CACHE_URL` → `REDIS_URL`, namespace `import_demo:cache`, short timeouts, errors reported via `Rails.error` and treated as misses). Test env overrides with `:null_store`. There is no Solid Cache.
- **Databases**: development/test use a single DB each (`import_demo_development`, `import_demo_test`). Production has `primary`, `queue` and `cable` databases (`config/database.yml`); queue/cable schemas live in `db/queue_schema.rb` and `db/cable_schema.rb`.
- **Error handling**: `ApplicationError < StandardError` (`code`, `status`, `details`, `origin_error:` wrapping a Rails/library error and reusing its message; subclasses `ClientError`, `ForbiddenError`, `UnexpectedError`), concerns `ApiResponse` (`render_success`, `render_error`) and `ErrorHandling` (`rescue_from`; every non-`ApplicationError` exception shares one handler: status from `config.action_dispatch.rescue_responses`, code from the class name; unmapped/5xx errors become a generic 500 and are reported; 5xx `ApplicationError`s are reported too and `UnexpectedError` never exposes its origin message). Errors raised outside actions (unknown route, body parse) render the same envelope via `config.exceptions_app` → `ErrorsController`. Files: `app/errors/`, `app/controllers/concerns/`. `rescue_from StandardError` must stay declared first (handlers are matched bottom-up). JSON health: `GET /health`.
- **Dev container**: `Dockerfile.dev` + `bin/docker-dev-entrypoint` (bundle sync into the `bundle` volume, `db:prepare` before the server, stale pid cleanup). The production `Dockerfile` is separate and untouched by dev setup.

## Code style (RuboCop)

- `.rubocop.yml` only wires layers: `rubocop-rails-omakase` → `standard` / `standard-performance` / `standard-rails` → plugins `rubocop-rails`, `rubocop-rspec`, `rubocop-performance`. **All project rules go in `.rubocop.custom.yml`**, one section per department with separate Enabled / Disabled groups.
- Gem-inheritance precedence between Omakase and Standard is not reliable, so every conflict is decided explicitly in `.rubocop.custom.yml`. Result: Omakase spacing (`[ a ]`, `{ a: 1 }`, `foo { }`), double quotes, Standard indentation/semicolon/return rules, Metrics enabled with RuboCop default thresholds.
- Omakase disables whole departments; `.rubocop.custom.yml` re-enables them. Removing that block breaks RuboCop with a `Lint/Syntax` error.
- `standard` pins RuboCop to 1.91.x; `ruby-lsp-rspec` is pinned `~> 0.1.29` (which keeps `prism` at 1.x) so Bundler doesn't fall back to an ancient `ruby-lsp`. Update these together.
- Editors (VSCode/Cursor, `.vscode/`) format and lint through Ruby LSP with the `rubocop` formatter, i.e. the same `.rubocop.yml`. Do not switch it to `standard` — that addon ignores `.rubocop.yml` and fights the Omakase spacing.

## Testing conventions

- `.rspec` requires `rails_helper`, so spec files need no `require` line. Spec type is inferred from the directory; `spec/support/**/*.rb` is auto-loaded.
- Random order (`--seed` to reproduce), `disable_monkey_patching!` (use `RSpec.describe`), `focus: true` filtering, transactional fixtures in `spec/fixtures`.

## Claude Code setup

- `.claude/settings.json` registers the `dotclaude` marketplace (github `phantien133/dotclaude`) and enables the `rails-api@dotclaude` plugin (skills such as `rails-best-practices-core`, `rails-testing`, `postgres-patterns`; explicit-invoke skills `/rails-migrations`, `/rails-security-multitenancy`, `/rails-jobs`, `/rails-webhooks`, `/dhh`; commands `/feature-dev`, `/prp-plan`).
- Hooks are copied into `.claude/hooks/` (version-stable, wired via `${CLAUDE_PROJECT_DIR}`): `suggest-compact`, `pre-bash-commit-quality` (conventional-commit check; does not lint `.rb`), `block-no-verify` (blocks `git commit --no-verify`), `pre-compact`, `desktop-notify`, `cost-tracker`. After upgrading the plugin, run `/setup-dotclaude-preset-hooks` to refresh the copies or toggle hooks.
- Commit messages use Conventional Commits (`chore:`, `feat:`, `fix:` ...).
