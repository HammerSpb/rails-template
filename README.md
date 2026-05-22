# Rails Template

A Rails 8 boilerplate with two fully Dockerized environments — **production**
and **staging** — deployed via **Kamal 2** to a Linux deploy-target container
running locally. Designed to mirror a real Kamal deploy so the same workflow
moves untouched to a remote VPS later.

## What's in the box

- **Rails 8** with **Solid Queue / Solid Cache / Solid Cable** (Postgres-backed; no Redis)
- **PostgreSQL 18** as a Kamal accessory — one container per environment
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

4. **SSH key auth to the kamal-host container** — `docker-compose.kamal-host.yml`
   bind-mounts your `~/.ssh/id_ed25519.pub` into the container at
   `/etc/ssh/authorized_keys.d/$USER` (the container user matches your
   host username). If you only have `id_rsa`, edit the compose file to
   point at the right pub key. (Nothing needs to be added to your local
   `~/.ssh/authorized_keys`.)

## Quickstart

```bash
make setup                                  # bundle, db:prepare, start dev DB + registry + kamal-host
cp .kamal/secrets.example          .kamal/secrets          # then edit (production)
cp .kamal/secrets.staging.example  .kamal/secrets.staging  # then edit (staging)

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
│   localhost:5434 ─►  postgres:18  (dev + test DB)                                       │
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
│                              │     └─► myapp-db    (postgres:18, host :5432)            │
│                              │                                                          │
│                              └─► myapp-staging-web (Rails 8 / staging)                  │
│                                    └─► myapp-staging-db (postgres:18, host :5433)       │
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
inside the container as on the host (`$PWD`), because Kamal builds
`docker run -v $PWD/...` commands and the host daemon (shared via socket)
needs the path to resolve. The container user is created to match your
host `$USER` and uid/gid (`make kamal-host-up` passes `id -u` / `id -g`)
so created files keep proper ownership.

## Daily workflow

### Local development

Rails runs natively on your Mac and talks to a Dockerized dev Postgres.
No Kamal involved.

```bash
make setup           # idempotent: bundle, start dev DB + registry + kamal-host, prepare DB
make dev             # boot Rails on http://127.0.0.1:3000
make dev-down        # stop dev Postgres (data persists in volume)
make dev-psql        # psql into dev DB
bin/rails test       # tests run against the dev Postgres test database
make lint            # RuboCop + ERB Lint
make lint-fix        # auto-fix
```

### Staging

```bash
bin/kamal accessory boot db -d staging   # first-time only: bring up Postgres
make deploy-staging                       # build, push, swap-in new container
make logs-staging                         # tail
make console-staging                      # rails c
make ssh-staging                          # bash inside the app container
make db-backup-staging                    # gzipped pg_dump -> backups/

bin/kamal app stop    -d staging          # stop the app (keep image + DB)
bin/kamal app start   -d staging          # start it again
bin/kamal app boot    -d staging          # restart
bin/kamal remove      -d staging          # tear down everything: app + accessory + volumes
```

Visit: **http://myapp-staging.local**

### Production

Same as staging, but production is Kamal's **default destination** — no
`-d` flag.

```bash
bin/kamal accessory boot db               # first-time only
make deploy-production
make logs-production
make console-production
make ssh-production
make db-backup-production

bin/kamal app stop                        # stop
bin/kamal app start                       # start
bin/kamal app boot                        # restart
bin/kamal remove                          # tear down
```

Visit: **http://myapp.local**

### Other handy targets

```bash
make registry-up / registry-down          # local image registry
make kamal-host-up / kamal-host-down      # the Linux SSH target
make kamal-host-shell                     # shell into kamal-host as your user
make local-certs                          # mkcert HTTPS certs
make help                                 # list everything
```

## Secrets

Kamal 2 reads secrets via **dotenv parsing** of these files:

```
.kamal/secrets-common              # committed; common to all destinations
.kamal/secrets                     # gitignored; production (default destination, no -d flag)
.kamal/secrets.staging             # gitignored; staging (loaded by -d staging)
```

Production maps to the no-suffix file because Kamal treats the
"no -d flag" case as a destination whose secrets file is `.kamal/secrets`.

Templates ending in `.example` are committed. `bin/setup` copies them
for you on first run; or do it by hand:

```bash
cp .kamal/secrets.example          .kamal/secrets
cp .kamal/secrets.staging.example  .kamal/secrets.staging
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

## Moving to real remote servers

The whole point of the local-Kamal setup is that the same configuration
runs unmodified against real VPSes. This section walks through what
changes when you flip from local → remote, broken down by the four
pieces of infrastructure: **app server**, **registry**, **database**,
**SSL/DNS**.

### 1. Real app/web server (production or staging)

Provision a Linux box (any cloud — Hetzner, DigitalOcean, Fly.io machines,
a friend's bare metal). Requirements: Ubuntu/Debian, ssh access, port 22
reachable, ports 80 + 443 open. Kamal installs docker for you on first
deploy.

In `config/deploy.yml` (production) / `config/deploy.staging.yml`:

```yaml
servers:
  web:
    - 203.0.113.10           # <-- your real server IP (or hostname)

ssh:
  user: deploy               # <-- the user Kamal SSHes as on the remote
  port: 22                   # <-- drop :2222
```

Add the SSH key you want Kamal to use to that user's `~/.ssh/authorized_keys`
on the remote, then verify: `ssh deploy@203.0.113.10 'echo ok'`.

Once a real server is in play, **the `kamal-host` container is no longer
needed**. Stop it: `make kamal-host-down`. Remove `kamal-host/` and
`docker-compose.kamal-host.yml` from the repo when you're confident
you've moved.

### 2. Real registry (GitHub Container Registry)

The local registry (`127.0.0.1:5555`) only made sense because the build
host and deploy host were the same machine. A real remote server can't
reach `127.0.0.1` on your laptop. Use a real registry; ghcr.io is the
zero-friction choice if your code is on GitHub.

In both `config/deploy.yml` and `config/deploy.staging.yml`:

```yaml
registry:
  server: ghcr.io
  username: your-github-username
  password:
    - KAMAL_REGISTRY_PASSWORD

builder:
  arch: amd64
  # remove `driver: docker` — Kamal's default docker-container builder
  # works fine when pushing to a real registry (it was only a problem
  # for the local 127.0.0.1 registry because of network namespaces)
```

Create a GitHub PAT with `write:packages` (classic token) or use a
fine-grained token scoped to the repo. Set it in both `.kamal/secrets`
(production) and `.kamal/secrets.staging`:

```
KAMAL_REGISTRY_PASSWORD=ghp_xxxxxxxxxxxxxxxxxxxx
```

Image names automatically rebase from `127.0.0.1:5555/myapp` to
`ghcr.io/your-github-username/myapp`. Then tear down the local registry:

```bash
make registry-down
docker volume rm rails-template-registry_registry_data   # optional, drops cached images
```

Remove `docker-compose.registry.yml` and the `registry-*` targets in the
Makefile once you're sure.

Also revert the `~/.docker/config.json` workaround we added for local
deploys (delete the `credHelpers."127.0.0.1:5555"` block) — it's no
longer needed.

### 3. Real database server

You have two paths.

**Option A: Postgres on the same host as the app (simplest).**
Keep the existing `accessories.db` block. Kamal will boot the Postgres
container next to your app container on the remote server.

```yaml
accessories:
  db:
    image: postgres:18-alpine
    host: 203.0.113.10        # <-- same server IP as servers.web
    port: "127.0.0.1:5432:5432"   # bind to loopback only; not exposed publicly
    env:
      clear:
        POSTGRES_USER: myapp
        POSTGRES_DB: myapp_production
      secret:
        - POSTGRES_PASSWORD
    directories:
      - data:/var/lib/postgresql/data
```

Boot it once: `bin/kamal accessory boot db`. The data volume persists
across `kamal deploy` runs.

**Option B: Dedicated DB server (or managed Postgres).**
Spin up Postgres on a separate VPS, RDS, Crunchy, Supabase, etc. Then:

```yaml
# Drop the accessories.db block entirely.
env:
  secret:
    - RAILS_MASTER_KEY
    - POSTGRES_PASSWORD
  clear:
    DB_HOST: db.internal.example.com   # <-- managed DB hostname or private IP
    DB_PORT: 5432
    RAILS_ENV: production
```

If your managed Postgres uses a different username/database name, update
`config/database.yml` accordingly. For SSL-required connections (RDS,
Supabase), set `sslmode: require` in the database config:

```yaml
production:
  primary:
    <<: *default
    ...
    sslmode: require
```

`bin/db-backup` needs adjusting if the DB no longer runs as a Kamal
accessory on the same host — point it at the managed instance via
`pg_dump postgresql://user:pass@db.internal.example.com/myapp_production`.

### 4. SSL/DNS

For real domains, kamal-proxy's built-in Let's Encrypt does everything.
In your deploy config:

```yaml
proxy:
  ssl: true
  host: app.example.com         # <-- your real domain
  app_port: 3000
  healthcheck:
    path: /up
    interval: 3
    timeout: 3
  # Delete ssl_certificate_path and ssl_certificate_key_path — those are
  # only used for the local mkcert flow.
```

Requirements for LE to succeed:
- DNS A/AAAA record points at the server's public IP
- Port 80 reachable from the internet (LE uses HTTP-01 by default)
- Port 443 reachable

For staging, you'll want a separate hostname (`staging.example.com`) on
the same server, same kamal-proxy. Kamal handles SNI-style routing
between them automatically.

Now you can also remove `bin/generate-local-certs` and the
`local-certs` Makefile target if you don't deploy locally any more.

### 5. Required changes summary

| What | Local | Real remote |
|---|---|---|
| `servers.web` | `127.0.0.1` | server's public IP / hostname |
| `ssh.port` | `2222` | `22` |
| `ssh.user` | `$USER` (via ERB) | the remote user (often `root` or `deploy`) |
| `registry.server` | `127.0.0.1:5555` | `ghcr.io` (or another remote registry) |
| `registry.username` | `kamal` (stub) | your GitHub username |
| `builder.driver` | `docker` | omit (use Kamal's default) |
| `proxy.ssl` | `false` | `true` |
| `proxy.host` | `myapp.local` | `app.example.com` |
| `proxy.ssl_certificate_*` | configured for mkcert | omit |
| `accessories.db.host` | `127.0.0.1` | server IP, or remove for managed DB |
| `kamal-host` container | needed | **delete entirely** |
| Local registry container | needed | **delete entirely** |
| `~/.zshenv` PATH hack | needed | not needed |
| `~/.docker/config.json` credHelpers override | needed | not needed |
| `/etc/hosts` entries | needed | not needed (real DNS) |

### 6. Suggested rollout order

1. Get a real registry first (ghcr.io). Verify `make deploy-staging`
   builds and pushes there. Locally everything still works.
2. Provision the staging server. Switch `config/deploy.staging.yml`
   `servers.web` and `ssh.*` to point at it. Deploy. Verify.
3. Repeat for production.
4. Remove `kamal-host/`, `docker-compose.kamal-host.yml`,
   `docker-compose.registry.yml`, and the corresponding Makefile
   targets. Trim the host-side workarounds from this README.

## File map

```
.kamal/secrets-common              — common Kamal secrets (committed)
.kamal/secrets.example             — production secrets template (committed)
.kamal/secrets.staging.example     — staging secrets template (committed)
.kamal/secrets                     — real production secrets (gitignored)
.kamal/secrets.staging             — real staging secrets (gitignored)
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

- The `myapp` name is a placeholder for your service. It drives the service
  name, image name, database names, accessory hostnames, and volume names.
  To rename, grep-and-replace it across every tracked file that mentions it
  (skip this README so the example below stays intact):

  ```bash
  # macOS / BSD sed
  git grep -l myapp -- ':!README.md' | xargs sed -i '' 's/myapp/your-app/g'

  # Linux / GNU sed — drop the empty '' after -i:
  # git grep -l myapp -- ':!README.md' | xargs sed -i 's/myapp/your-app/g'
  ```

  This touches `config/` (deploy + database), `bin/`, `Dockerfile`,
  `.gitignore`, and `lib/json_log_formatter.rb`. Plain substring replace
  also handles `myapp_development`, `myapp-db`, etc. Afterward, recreate
  the dev DB so the new name takes effect:

  ```bash
  make dev-down && make dev-up && bin/rails db:prepare
  ```
- `.kamal/secrets` and `.kamal/secrets.staging` are gitignored. The
  `.example` templates are committed.
- Solid Queue runs inside Puma by default (`SOLID_QUEUE_IN_PUMA: true`).
  Split onto a `job:` host once load justifies it.
- Accessories (Postgres) aren't auto-booted on `kamal deploy` — run
  `bin/kamal accessory boot db [-d staging]` once after first setup.
