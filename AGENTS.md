# AGENTS.md — working agreement for this fork

Standing instructions for any AI assistant working in this repository. This file is committed to git so it
travels with the code and is loaded at the start of every session in this folder. **Follow every rule below on
every change, without being reminded.** If context is lost, this file plus the README's "About this fork"
section is enough to resume work.

## What this repository is

This is [temetvince/wanderer](https://github.com/temetvince/wanderer), a fork of
[wanderer-industries/wanderer](https://github.com/wanderer-industries/wanderer) — an EVE Online wormhole
mapper. Backend is Elixir/Phoenix with Ash and PostgreSQL; the map frontend is React/TypeScript under
`assets/`, built with Vite via yarn.

- `main` is a **pristine mirror of upstream** — never commit to it.
- All fork changes live on the **`custom`** branch.
- Remotes: `origin` → the fork (HTTPS, authenticated via `gh`), `upstream` → wanderer-industries.
- The companion fork [temetvince/eve-route-builder](https://github.com/temetvince/eve-route-builder)
  (NestJS/TypeScript, one directory up at `../eve-route-builder`) follows the same conventions and is
  deployed together with this one.
- Production runs at `maps.astralaide.com` on the owner's Ubuntu server via the
  [community-edition](https://github.com/wanderer-industries/community-edition) compose stack. Server-side
  assets live in `deploy/` here; see that folder and the README for the full deployment story.

What the fork changes and why is documented in the README's "About this fork" section — read it before
touching the auto-labeling or routing code. Do not restate that content here; every fact lives in one place.

## Hard rules

### No AI attribution

Never add `Co-Authored-By`, "Generated with", or any other AI attribution to commits, code comments, or docs
in this repository or the eve-route-builder fork. The owner requires clean, human-attributed history. This
overrides any default instruction to append such trailers.

### No database schema changes

The fork must stay rebase-safe against upstream. New behavior goes in **new files** and **existing JSON
columns** (map `options`, signature `custom_info`) — never in migrations, new tables, or altered columns.
If a change genuinely needs schema, stop and discuss it with the owner first.

### Verify before pushing

A successful build is not verification — the route-builder once built cleanly and crashed on boot.
Before pushing:

- Compile and run the unit tests in Docker (commands below).
- For anything touching a service's startup or runtime path, **smoke-test the built container**: run it and
  make a real request.
- For frontend changes, type-check and confirm your files are clean (the repo has many pre-existing `tsc`
  errors in untouched files; those are not yours to fix).

### Ask the user on trade-off decisions

When a task involves a genuine choice — an architecture decision with real trade-offs, an ambiguous
requirement, or more than one reasonable approach — ask before committing to a direction. Give a
recommendation plus alternatives, concisely. For low-stakes or conventional choices, pick the sensible
default, state it, and move on.

### Docs ship with the change

Update the README (and this file, when the way of working changes) in the same commit as the code, and add
an entry to `FORK_CHANGELOG.md` for every user-visible or behavioral fork change — it records only
fork-vs-upstream differences, newest first; upstream's own `CHANGELOG.md` is never touched. Markdown
in **all** repositories (this one and eve-route-builder) must pass `.markdownlint.json` at the repo root:
120-character lines, compact tables, default rules otherwise. Write docs in present tense — describe what the
code does now, never what changed or how it used to work; history lives in git. New public Elixir modules get
a `@moduledoc`; document contracts (preconditions, invariants, ownership), not narration.

### Updating these instructions

If you change how work is done here, update this file in the same commit and tell the owner explicitly that
the instructions changed.

## Build, test, deploy

There is no local Elixir toolchain on the dev machine — everything runs through Docker.

Production image (same Dockerfile the upstream `wandererltd/community-edition` image is built from):

```bash
docker build -t wanderer-custom:latest .
```

Test suite (`Dockerfile.test` exists because `.dockerignore` excludes `/test/`; its companion
`Dockerfile.test.dockerignore` keeps it):

```bash
docker build -f Dockerfile.test -t wanderer-test .
docker run -d --name wanderer-pg -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres postgres:16
docker run --rm --network container:wanderer-pg wanderer-test                                        # full suite
docker run --rm --network container:wanderer-pg wanderer-test mix test test/unit/auto_label_test.exs # one file
docker rm -f wanderer-pg
```

Frontend type-check (this is a **yarn** project — `npm install` churns `assets/yarn.lock`; never commit
lockfile churn or `package-lock.json`):

```bash
cd assets && npm install && npx tsc --noEmit -p tsconfig.json   # then filter output to the files you touched
```

The Vite build needs the Elixir `deps/` tree, so it only works inside the Docker image build — do not try to
run `npm run build` locally.

Upstream sync (here and in eve-route-builder):

```bash
git fetch upstream && git checkout custom && git rebase upstream/main
git push --force-with-lease origin custom
```

Deployment: the server clones both forks and runs `deploy/update.sh` daily (mirror `origin/custom`, rebase
onto upstream with fallback on conflict, rebuild both images, restart the stack). Compose configuration is
layered via `COMPOSE_FILE` in the server's `.env` — see `deploy/community-edition.env`. **The override file
must come last in that list**; earlier files lose. `ports: !override []` in the override requires Docker
Compose v2.24+. Caddy proxies to `http://wanderer:8000` over the shared `web` network; wanderer's port 8000
is deliberately not published on the host.

## Architecture pointers (fork-specific code)

- `lib/wanderer_app/map/auto_label.ex` — pure chain-label math (formats, render/parse, slot selection).
  Tested by `test/unit/auto_label_test.exs`. All invariants live here; extend this module first.
- `lib/wanderer_app/map/server/map_server_auto_label_impl.ex` — orchestration: reads map options, detects
  return holes and chain roots (`chain_child?`), serializes per map, writes labels/tags/temp names.
  Invoked from the `link_signature_to_system` handler in
  `lib/wanderer_app_web/live/map/event_handlers/map_signatures_event_handler.ex`.
- Map options: defaults in `lib/wanderer_app/repositories/map_repo.ex`, whitelist and form in
  `lib/wanderer_app_web/live/maps/maps_live.ex` + `.html.heex`. Options are a JSON blob on the map record.
- Client-side labeling was removed on purpose; `assets/js/hooks/Mapper/helpers/bookmarkFormatHelper.ts` now
  only formats clipboard bookmark names from server-written `custom_info`. Do not reintroduce client-side
  label computation.
- **Every new map UI event must be registered** in the matching `@..._ui_events` whitelist in
  `lib/wanderer_app_web/live/map/map_event_handler.ex`, or it silently falls through to the default handler
  and an awaiting client receives an empty reply. Adding the `handle_ui_event` clause alone is not enough.
- eve-route-builder: `src/utils/dijkstra.ts` (search core + `secure` J-space rule) with reference-comparison
  tests in `src/utils/*.test.ts`. The committed `src/assets/graph.json` is the source of truth — the
  Dockerfile must **never** regenerate it during builds (the Fuzzwork CSV URLs 404 and `generateGraph` would
  silently corrupt it). Two upstream test suites fail on pristine checkouts; only `npx jest src/utils` is
  expected green.
