# Rails Template

A Rails 8 boilerplate with two fully Dockerized environments — **production**
and **staging** — deployed via **Kamal 2** to a Linux deploy-target container
running locally. Designed to mirror a real Kamal deploy so the same workflow
moves untouched to a remote VPS later.

## What's in the box

- **Rails 8** with **Solid Queue / Solid Cache / Solid Cable** (Postgres-backed; no Redis)
- **PostgreSQL 16** as a Kamal accessory — one container per environment
- **Dockerized dev DB** at `localhost:5434` (no local Postgres install needed)
- **Local Docker registry** at `127.0.0.1:5555`
- **`kamal-host` container** — Ubuntu 24.04 with sshd + docker CLI; acts as
  Kamal's Linux deploy target so Kamal's GNU-userland assumptions hold
- **Two Kamal configs**: `config/deploy.yml` (prod) and `config/deploy.staging.yml`
- **JSON structured logging** in production and staging
- **`/up` health dashboard** — JSON status with version, git SHA, DB + Solid Queue checks
- **mkcert TLS helper** for local HTTPS
- **`bin/db-backup`** for one-command Postgres dumps
- **`Makefile`** with deploy/log/backup aliases
- **RuboCop**, **ERB Lint**, **Brakeman**, **bundler-audit**, **GitHub Actions CI** all preconfigured

## Prerequisites

| Tool          | Why                                    |
| ------------- | -------------------------------------- |
| Docker Desktop / OrbStack | Containers, buildx, daemon shared with `kamal-host` |
| Ruby 3.4.5    | Matches `.ruby-version`                |
| Kamal 2       | `gem install kamal`                    |
| mkcert        | Local HTTPS (`brew install mkcert nss`) |

### One-time host setup (macOS)

These changes are outside the project but required for the local Kamal flow:

1. **`~/.zshenv`** — non-interactive SSH (used by Kamal) doesn't load `.zshrc`,
   so `/usr/local/bin` (where Docker Desktop / OrbStack puts `docker`) is missing
   from `PATH`. Create `~/.zshenv` with:

   ```sh
   export PATH="/usr/local/bin:/opt/homebrew/bin:$PATH"
   ```

2. **`~/.docker/config.json`** — the macOS Keychain credential helper can't
   unlock from a non-interactive SSH session. Add a per-registry override so
   only the local registry skips the keychain:

   ```json
   "credHelpers": {
     "127.0.0.1:5555": ""
   }
   ```

3. **`/etc/hosts`** (sudo) — kamal-proxy routes by hostname:

   ```
   127.0.0.1   myapp.local  myapp-staging.local
   ```

4. **SSH key auth to the kamal-host container** — your `~/.ssh/id_ed25519.pub`
   is bind-mounted into the container as `authorized_keys` automatically.
   If you only have `id_rsa`, edit `docker-compose.kamal-host.yml`.

## Quickstart

```bash
make setup                  # bundle, db:prepare, start dev DB + registry + kamal-host
cp .kamal/secrets.staging.example  .kamal/secrets.staging      # then edit
cp .kamal/secrets.production.example  .kamal/secrets.production # then edit

bin/kamal accessory boot db                # first-time only: bring up prod DB
bin/kamal accessory boot db -d staging     # first-time only: bring up staging DB
make deploy-production
make deploy-staging

curl -H 'Host: myapp.local'         http://127.0.0.1/up
curl -H 'Host: myapp-staging.local' http://127.0.0.1/up
```

`make help` lists every target.

## Architecture

```
┌────────────────────────────────────── your laptop ──────────────────────────────────────┐
│                                                                                         │
│   localhost:5434 ─►  postgres:16  (dev + test DB)                                       │
│   127.0.0.1:5555 ─►  registry:2   (image registry)                                      │
│                                                                                         │
│   127.0.0.1:2222 ─►  kamal-host   (Ubuntu 24.04 + sshd + docker CLI                    │
│                       │              │  + docker.sock bind-mounted from host            │
│                       │              └─ project dir bind-mounted at SAME path)          │
│                       │                                                                 │
│                       │  Kamal SSHes here, runs `docker run …`, which actually          │
│                       │  executes on the HOST's docker daemon via the socket mount.     │
│                       │                                                                 │
│                       ▼     (all containers below run on host's docker, on `kamal` net) │
│                                                                                         │
│   myapp.local         ─┐                                                                │
│   myapp-staging.local ─┴─►  kamal-proxy (host :80 / :443, hostname routing)             │
│                              │                                                          │
│                              ├─► myapp-web         (Rails 8 / prod)                     │
│                              │     └─► myapp-db    (postgres:16, host :5432)            │
│                              │                                                          │
│                              └─► myapp-staging-web (Rails 8 / staging)                  │
│                                    └─► myapp-staging-db (postgres:16, host :5433)       │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

### Why a `kamal-host` container?

Kamal targets Linux. Trying to deploy to macOS over SSH (the "easy" path)
breaks on a stack of incompatibilities: BSD `cp` doesn't accept `-T`, the
macOS Keychain credential helper can't service non-interactive SSH, the
default Mac SSH `PATH` doesn't include `/usr/local/bin`, etc. Spinning up
a small Ubuntu container with sshd + docker CLI and pointing Kamal at it
sidesteps all of that, and behaves identically to a real remote VPS.

The container has the project directory bind-mounted at the **same path**
inside the container as on the host (`/Users/roman/work/rails-template`),
because Kamal builds `docker run -v $PWD/...` commands and the host
daemon (shared via socket) needs the path to resolve. The container's
`roman` user matches macOS uid 502 / gid 20 so created files keep proper
ownership.

## Common operations

```bash
make deploy-production           # release deploy
make deploy-staging              # staging deploy
make logs-production             # tail prod logs
make console-staging             # rails console against staging
make db-backup-production        # gzipped pg_dump -> backups/
make registry-up / registry-down
make dev-up / dev-down / dev-psql
make kamal-host-up / kamal-host-down / kamal-host-shell
make lint / lint-fix             # RuboCop + ERB Lint
```

## Secrets

Kamal 2 reads secrets via **dotenv parsing** of these files (in order):

```
.kamal/secrets-common              # committed; common to all envs
.kamal/secrets.production          # gitignored; prod-only
.kamal/secrets.staging             # gitignored; staging-only (loaded by -d staging)
```

Templates ending in `.example` are committed. `make setup` doesn't copy
them — do it once by hand:

```bash
cp .kamal/secrets.production.example .kamal/secrets.production
cp .kamal/secrets.staging.example .kamal/secrets.staging
# then edit and put real POSTGRES_PASSWORD etc.
```

## Local HTTPS

By default both environments serve HTTP (kamal-proxy's built-in
Let's Encrypt can't issue certs for `*.local`). To enable HTTPS locally:

```bash
brew install mkcert nss
mkcert -install         # one-time: trust mkcert's CA
make local-certs        # generates certs in .kamal/certs/
```

Then follow the on-screen instructions to enable `ssl: true` in the deploy
config and copy certs into the running kamal-proxy container.

## Deploying to a real remote server

Three changes turn this from local-Kamal into real-host Kamal:

1. **Hosts**: `servers.web` and accessory `host` → your server's IP
2. **SSH**: `ssh.user` → your remote user; `ssh.port` → 22 (drop the `:2222`)
3. **SSL**: `proxy.ssl: true` + `proxy.host: your-domain.com`
   (remove `ssl_certificate_path` / `ssl_certificate_key_path` — the
   proxy will provision via Let's Encrypt automatically)

You'd also stop the `kamal-host` container and tear down the local registry,
and switch `registry.server` to `ghcr.io` (or whatever).

## Migrating from local registry to ghcr.io

In **both** `config/deploy.yml` and `config/deploy.staging.yml`:

```yaml
registry:
  server: ghcr.io
  username: your-github-username
  password:
    - KAMAL_REGISTRY_PASSWORD
```

Set `KAMAL_REGISTRY_PASSWORD` in `.kamal/secrets.production` /
`.kamal/secrets.staging` to a GitHub PAT with `write:packages` scope.

Image names rebase from `127.0.0.1:5555/myapp` to `ghcr.io/your-user/myapp`
automatically.

## File map

```
.kamal/secrets-common              — common Kamal secrets (committed)
.kamal/secrets.{production,staging}.example — templates (committed)
.kamal/secrets.{production,staging}— real values (gitignored)
config/deploy.yml                  — Kamal production config
config/deploy.staging.yml          — Kamal staging config
docker-compose.dev.yml             — dev Postgres (localhost:5434)
docker-compose.registry.yml        — local Docker registry (127.0.0.1:5555)
docker-compose.kamal-host.yml      — Linux deploy target (127.0.0.1:2222)
kamal-host/Dockerfile              — Ubuntu + sshd + docker CLI
Dockerfile                         — multi-stage production image
bin/setup                          — bootstrap script
bin/db-backup                      — pg_dump from a running Kamal accessory
bin/generate-local-certs           — mkcert helper for *.local TLS
lib/json_log_formatter.rb          — JSON log formatter (prod + staging)
app/controllers/health_controller.rb — /up dashboard
Makefile                           — deploy/logs/backup aliases
```

## Notes

- The `myapp` name is a placeholder. To rename, grep-and-replace `myapp` /
  `MyApp` across `config/`, `Makefile`, `bin/`, and accessory hostnames.
- `.kamal/secrets.{production,staging}` are gitignored. The `.example`
  files are committed.
- Solid Queue runs inside Puma by default (`SOLID_QUEUE_IN_PUMA: true`).
  Split onto a `job:` host once load justifies it.
- Accessories (Postgres) aren't auto-booted on `kamal deploy` — run
  `bin/kamal accessory boot db [-d staging]` once after first setup.
