# Rails Template

A Rails 8 boilerplate with two fully Dockerized environments — **production**
and **staging** — deployed via **Kamal 2** to a local "server" (your own
machine over SSH). Designed to mirror a real Kamal deploy so the same
workflow moves untouched to a remote host later.

## What's in the box

- **Rails 8** with **Solid Queue / Solid Cache / Solid Cable** (Postgres-backed; no Redis)
- **PostgreSQL 16** as a Kamal accessory — one container per environment
- **Dockerized dev DB** at `localhost:5434` (no local Postgres install needed)
- **Local Docker registry** at `localhost:5555` (no external registry needed)
- **Two Kamal configs**: `config/deploy.yml` (prod) and `config/deploy.staging.yml`
- **JSON structured logging** in production and staging
- **`/up` health dashboard** — JSON status with version, git SHA, DB + Solid Queue checks
- **mkcert TLS helper** for local HTTPS
- **`bin/db-backup`** for one-command Postgres dumps
- **`Makefile`** with deploy/log/backup aliases
- **RuboCop**, **GitHub Actions CI**, **Brakeman** all preconfigured

## Prerequisites

| Tool          | Why                                    |
| ------------- | -------------------------------------- |
| Docker Desktop| Containers + buildx + image registry   |
| Ruby 3.4.5    | Matches `.ruby-version`                |
| Kamal 2       | `gem install kamal`                    |
| mkcert        | Local HTTPS (`brew install mkcert nss`)|

**macOS-only step**: enable **System Settings → General → Sharing → Remote
Login**. Kamal SSHes into `127.0.0.1` to deploy.

Verify SSH works first:

```bash
ssh roman@127.0.0.1 'echo ok'
```

Add the local hostnames to `/etc/hosts`:

```
127.0.0.1   myapp.local  myapp-staging.local
```

## Quickstart

```bash
make setup                  # bundle, db:prepare, copy .env files, start registry
edit .env.production        # set POSTGRES_PASSWORD
edit .env.staging           # set POSTGRES_PASSWORD
make deploy-production      # builds, pushes to localhost:5555, boots prod
make deploy-staging         # same for staging

curl http://myapp.local/up
curl http://myapp-staging.local/up
```

`make help` lists everything.

## Architecture

```
┌────────────────────────────── your laptop ──────────────────────────────┐
│                                                                         │
│  localhost:5434  ──────►  postgres:16 (development + test DB)           │
│  localhost:5555  ──────►  registry:2  (Docker image registry)           │
│                                                                         │
│  myapp.local           ─┐                                               │
│  myapp-staging.local   ─┴─►  kamal-proxy (host port 80, hostname-routed)│
│                              │                                          │
│                              ├─► myapp-web        (Rails 8 / prod)      │
│                              │     │                                    │
│                              │     └─► myapp-db    (postgres:16, :5432) │
│                              │                                          │
│                              └─► myapp-staging-web (Rails 8 / staging)  │
│                                    │                                    │
│                                    └─► myapp-staging-db (postgres:16, :5433)
└─────────────────────────────────────────────────────────────────────────┘
```

Both environments share the same kamal-proxy on host port 80 and are
routed by hostname. Each app container has its own Postgres accessory
with isolated data volumes.

## Common operations

```bash
make deploy-production           # release deploy
make deploy-staging              # development/staging deploy
make logs-production             # tail prod logs
make console-staging             # rails console against staging
make db-backup-production        # gzipped pg_dump -> backups/
make registry-up / registry-down # control local registry
make dev-up / dev-down           # control dev Postgres
make dev-psql                    # psql into dev DB
```

## Local HTTPS

By default both environments serve HTTP (kamal-proxy's built-in
Let's Encrypt can't issue certs for `*.local`). To enable HTTPS locally:

```bash
brew install mkcert nss
mkcert -install         # one-time: trust mkcert's CA
make local-certs        # generates certs in .kamal/certs/
```

Then follow the on-screen instructions from `local-certs` to enable
`ssl: true` in the deploy config and copy certs into the running
kamal-proxy container.

## Deploying to a real remote server

Three changes turn this from local Kamal into real-host Kamal:

1. **Hosts**: `servers.web` and accessory `host` → your server's IP
2. **SSH**: `ssh.user` → your remote user (often `root` or `deploy`)
3. **SSL**: `proxy.ssl: true` + `proxy.host: your-domain.com`
   (remove `ssl_certificate_path` / `ssl_certificate_key_path` — the
   proxy will provision via Let's Encrypt automatically)

## Migrating from local registry to ghcr.io

In **both** `config/deploy.yml` and `config/deploy.staging.yml`:

```yaml
registry:
  server: ghcr.io
  username: your-github-username
  password:
    - KAMAL_REGISTRY_PASSWORD
```

Set `KAMAL_REGISTRY_PASSWORD` in `.env.production` / `.env.staging` to a
GitHub PAT with `write:packages` scope. Then:

```bash
docker compose -f docker-compose.registry.yml down  # local registry gone
make deploy-production
```

Image names rebase from `localhost:5555/myapp` to `ghcr.io/your-user/myapp`
automatically based on the registry config.

## File map

```
.kamal/secrets             — Kamal secret wiring (sources .env.<dest>)
.env.production.example    — template for prod secrets
.env.staging.example       — template for staging secrets
config/deploy.yml          — Kamal production config
config/deploy.staging.yml  — Kamal staging config
docker-compose.dev.yml     — dev Postgres (localhost:5434)
docker-compose.registry.yml— local Docker registry (localhost:5555)
Dockerfile                 — multi-stage production image (Rails 8 default)
bin/setup                  — bootstrap script
bin/db-backup              — pg_dump from a running Kamal accessory
bin/generate-local-certs   — mkcert helper for *.local TLS
lib/json_log_formatter.rb  — JSON log formatter (prod + staging)
app/controllers/health_controller.rb — /up dashboard
Makefile                   — deploy/logs/backup aliases
```

## Notes

- The `myapp` name is a placeholder. To rename: grep-and-replace `myapp` /
  `MyApp` throughout `config/`, `Makefile`, `bin/`, and the accessory
  hostnames in `deploy.*.yml`.
- `.env.production` / `.env.staging` are gitignored. The `.example` files
  are committed.
- Solid Queue runs inside Puma by default (`SOLID_QUEUE_IN_PUMA: true`).
  Split it onto a `job:` host once load justifies it — see commented
  example in `config/deploy.yml`.
