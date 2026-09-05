# Fork changelog

Differences between [temetvince/wanderer](https://github.com/temetvince/wanderer) (branch `custom`) and
upstream [wanderer-industries/wanderer](https://github.com/wanderer-industries/wanderer). Only fork changes
are recorded here; upstream's own `CHANGELOG.md` is never modified. Newest first.

## 2026-09-05

### Fixed

- Auto-labeling: a chain child whose entrance has closed (the signature from its parent was removed, or the
  link never carried chain metadata) keeps chaining off its own label as long as that label is chain-shaped -
  a one- or two-letter root, or a root followed by numeric slots. Previously such a system was treated as a
  named root, so jumps from `B` restarted root letters and reissued `B` itself instead of `BD`.

## 2026-09-02

### Fixed

- Auto-labeling root detection is label-consistent and recursive: a system only acts as a chain prefix when
  its label parses as a slot in its parent's namespace. Stale legacy signatures carrying chain metadata into
  a named home (from the pre-fork client-side labeling era) could previously mark the home as a chain child
  again, producing labels like `HTTA`.

### Changed

- The "Routes" widget is renamed "Shared Routes" in user-facing strings (widget title and widget picker);
  internal ids are unchanged so saved window layouts survive.
- The routes header checkbox "Show shortest" is now "Prefer safest": checked prefers high-sec routes,
  unchecked takes the shortest path.
- Hardened the route origin-strip in `map_routes.ex` to compare system ids loosely (the route service
  returns the origin as a number on some endpoints and a string on others).

### Added

- `AGENTS.md` working agreement, `.markdownlint.json` (all markdown must pass it), and this changelog.

## 2026-08-30

### Fixed

- Auto-labeling: a named root system (e.g. a home labeled `HTT`) starts a fresh chain — its holes get `A`,
  `B`, `C` instead of `HTTA`. A system's label only acts as a chain prefix when the system is itself a
  chain child.

## 2026-08-27

### Added

- **Server-side auto-labeling of jumped wormhole systems**: chain labels (`A`, `A1`, `A21`, letter-only
  `AABA`), tags, and temporary names are computed at signature-link time for every user, configured per map
  in Map Settings → General. Chain state derives from the labels currently on the map, so manual renames
  are respected (renaming `B` to `C` frees `B` and blocks `C`). Includes a new "Letter-only chain" format,
  return-hole handling, an optional chain separator, and per-map serialization. No database schema changes.
- `Dockerfile.test` (+ its dockerignore) for running the Elixir test suite in Docker.
- `deploy/` assets: daily `update.sh` (mirror fork, rebase onto upstream with safe fallback, rebuild,
  restart), compose override (custom images, wanderer port unpublished, Caddy proxied to the container over
  the `web` network), and the compose `.env` (override must be last in `COMPOSE_FILE`).

### Removed

- The per-user auto-label/auto-tag/temporary-name settings from the user settings dialog (superseded by the
  map-level options above; clipboard bookmark preferences remain per-user).
