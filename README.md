# Wanderer

[Wanderer](https://wanderer.ltd/) is an #1 EVE Online mapper tool, light and fast alternative to Pathfinder.
You can self-host Wanderer Community Edition or have us manage Wanderer for you in the cloud. Made and hosted
in the EU 🇪🇺

![Wanderer](https://wanderer.ltd/images/news/09-10-map-features-guide/cover.png)

## About this fork

This is [temetvince/wanderer](https://github.com/temetvince/wanderer), a fork of
[wanderer-industries/wanderer](https://github.com/wanderer-industries/wanderer).
`main` is a pristine mirror of upstream; all changes live on the `custom` branch:

- **Server-side auto-labeling of jumped systems.** Chain labels (`A`, `A1`,
  `A21`, or the new letter-only format `A`, `AA`, `ABA`) are computed by the
  server when a signature is linked, for every user, configured per map in
  **Map Settings → General** (admins only). Occupied slots are derived from the
  labels currently on the map, so manual renames are respected: renaming `B` to
  `C` frees the `B` slot and blocks `C` at that depth. A named root such as a
  home system labeled `HTT` starts a fresh chain (`A`, `B`, `C` - not `HTTA`):
  a system's label only acts as a chain prefix when that system is itself a
  chain child. Existing labels are never
  overwritten, return holes never consume a slot, and the
  "Show linked signature ID as custom label part" display option is unaffected.
  No database schema changes: everything lives in existing JSON columns, so
  upstream migrations continue to apply cleanly.
- **Sidebar links** to [Astral Aide](https://astralaide.com) and
  [SeAT](https://seat.astralaide.com).
- **`Dockerfile.test`** for running the Elixir test suite in Docker (see below).

The companion fork [temetvince/eve-route-builder](https://github.com/temetvince/eve-route-builder)
fixes "safest" routing through mapped wormhole chains — deploy both together.

### Keeping up with upstream

```bash
git fetch upstream
git checkout custom
git rebase upstream/main
git push --force-with-lease origin custom
```

Remotes: `origin` → this fork, `upstream` → wanderer-industries. Because the
fork avoids schema changes and keeps new code in new files, rebases rarely
conflict.

### Build and deploy

```bash
docker build -t wanderer-custom:latest .
```

Rather than editing the [community-edition](https://github.com/wanderer-industries/community-edition)
`docker-compose.yml` (which would make its daily `git pull` conflict), drop
[`deploy/docker-compose.override.yml`](deploy/docker-compose.override.yml)
next to it — Compose merges it automatically and swaps in the two custom
images. [`deploy/update.sh`](deploy/update.sh) is a cron-ready daily updater:
it mirrors `custom` from GitHub, rebases onto the latest upstream (falling
back to the last good state on conflict), rebuilds both images, and restarts
the stack. One-time server setup instructions are at the top of the script.

After the first deploy, open **Map Settings → General** and set the auto-label
format(s) — they default to Disabled. Also note `WANDERER_RESTRICT_MAPS_CREATION=true`
hides the Create Map button for everyone (admins can still create maps once via
the admin panel).

### Running tests in Docker

```bash
docker build -f Dockerfile.test -t wanderer-test .
docker run -d --name wanderer-pg -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres postgres:16
docker run --rm --network container:wanderer-pg wanderer-test                      # full suite
docker run --rm --network container:wanderer-pg wanderer-test mix test test/unit/auto_label_test.exs
```

## Why Wanderer?

Here's what makes Wanderer a great Pathfinder alternative:

- **Clutter Free**: Wanderer provides simple interface and it cuts through the noise. No training necessary.
- **Lightweight, fast and secure**: Wanderer is lightweight and fast. It uses a self-hosted database and a self-hosted server.
- **See all your characaters on a single page**: Wanderer provides a simple interface to see all your
  characters on a single page.
- **SPA support**: Wanderer is built with modern web frameworks in core.
- **Active development**: Wanderer is actively developed and improved with new features and updates every week
  based on user feedback.

Interested to learn more? [Check more on our website](https://wanderer.ltd/news).

### Can Wanderer be self-hosted?

Wanderer is open source project and we have a free as in beer and self-hosted solution called
[Wanderer Community Edition (CE)](https://wanderer.ltd/news/community-edition). Here are the differences
between Wanderer and Wanderer CE:

| | Wanderer Cloud | Wanderer Community Edition |
| --- | --- | --- |
| **Infrastructure management** | Easy and convenient. It takes 2 minutes to register your character and create a map. We manage everything so you don’t have to worry about anything and can focus on gameplay. | You do it all yourself. You need to get a server and you need to manage your infrastructure. You are responsible for installation, maintenance, upgrades, server capacity, uptime, backup, security, stability, consistency, loading time and so on. |
| **Release schedule** | Continuously developed and improved with new features and updates multiple times per week. | Latest features and improvements won't be immediately available. |
| **Server location** | All visitor data is exclusively processed on EU-owned cloud infrastructure. We keep your site data on a secure, encrypted and green energy powered server in Germany. This ensures that your site data is protected by the strict European Union data privacy laws and ensures compliance with GDPR. Your website data never leaves the EU. | You have full control and can host your instance on any server in any country that you wish. Host it on a server in your basement or host it with any cloud provider wherever you want, even those that are not GDPR compliant. |

Interested in self-hosting Wanderer CE on your server? Take a look at our [Wanderer CE installation instructions](https://github.com/wanderer-industries/community-edition/).

Wanderer CE is a community supported project and there are no guarantees that you will get support from the
creators of Wanderer to troubleshoot your self-hosting issues. There is a
[community supported forum](https://github.com/orgs/wanderer-industries/discussions/4) where you can ask for
help.

Our only source of funding is your donations.

## Technology

Wanderer is a standard Elixir/Phoenix application backed by a PostgreSQL database for general data. On the
frontend we use [TailwindCSS](https://tailwindcss.com/) for styling and React to make the map interactive.

## Development

### Setup

- Copy `.env.example` to `.env` and fill in the values

- Run `mix setup` to install and setup dependencies
- (optional step) run `make yarn` to install client dependencies

### Run

- Start server with `make server` or `make s`

Now you can visit [`localhost:8000`](http://localhost:8000) from your browser.

#### Using .devcontainer

- Copy `.env.example` to `.env` and fill in the values
- Open the repository in the dev container ("Reopen in Container")

The image ships Erlang/Elixir pinned to `.tool-versions`, Node.js 18, yarn and
the usual CLI tooling, and runs as the non-root `developer` user. On first
create, `.devcontainer/setup.sh` fetches and compiles deps, creates and migrates
the database, seeds the EVE SDE reference data if it is missing, and installs
and builds the client assets — so there is nothing to install by hand.

- If your host user id is not `1000`, export `USER_UID`/`USER_GID` before
  building so files written through the bind mount stay host-owned. See
  `.devcontainer/docker-compose.override.yml.example` for this and other
  host-specific settings.

- See how to run server in #Run section

#### Using nix flakes

- Run `nix develop`
- Run local postgres server: `pg-setup` & `pg-start`
- See how to start server in #setup section

### Migrations

#### Reset database

`mix ecto.reset`

#### Run seed data

- `mix run priv/repo/seeds.exs`

#### Generate new migration

- `mix ash.codegen <name_of_migration>`
- `mix ash.migrate`

#### Generate cloak key

- `iex> 32 |> :crypto.strong_rand_bytes() |> Base.encode64()`
