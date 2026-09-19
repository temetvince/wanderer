# Fork changelog

Differences between [temetvince/wanderer](https://github.com/temetvince/wanderer) (branch `custom`) and
upstream [wanderer-industries/wanderer](https://github.com/wanderer-industries/wanderer). Only fork changes
are recorded here; upstream's own `CHANGELOG.md` is never modified. Newest first.

## 2026-09-18

### Fixed

- Auto-labeling: a named root keeps starting fresh chains when one of its own depth-one children carries a
  label that begins its name. With letter-only chains, home `HTT` next to its eighth hole `H` parsed as H's
  slot `TT`, so home counted as a chain child and its next hole was labeled `HTTA` instead of the lowest
  free root letter. A letter-only parent vouches only for single-letter slots.

## 2026-09-14

### Fixed

- Routes settings (Shared Routes, User Routes, Routes By) are applied per key: `WandererApp.Map.RoutesSettings`
  keeps every recognized setting present in the request and falls back to the server default only for absent
  keys. Upstream pattern-matched the full payload and silently used all defaults when any key was missing, so
  a settings blob saved by an older client or pushed as an admin default left every toggle inert: Thera
  connections were always included, Trig/Edencom/Pochven systems never avoided, "Prefer safest" ignored.
- The routes widgets reload when two settings toggles are applied together (one turned on, one turned off).
  The reload trigger compared a sorted list of the setting values, which is identical before and after such a
  change.
- Thera and Turnur connections from EVE-Scout are flagged end-of-life when under 4 hours remain. Upstream
  flagged the healthy ones instead, so "Include EOL" off dropped every long-lived hole and kept the dying ones.
- "Include Thera connections" off adds Thera to the avoid list (Shared Routes, User Routes, Routes By), so no
  route passes through Thera even when Thera is mapped with its own connections; a route that starts in Thera
  may still leave it. Upstream only withheld the EVE-Scout connections and kept routing through a mapped Thera.

## 2026-09-05

### Added

- Wormhole connection lifetimes are resolved from static EVE data (`WandererApp.Map.WormholeLifetime`):
  frigate holes 4.5h, then the source system's static leading to the target's class, then the target's
  static leading back (K162 side), then every wandering type joining the two classes, shortest on
  disagreement. Previously any hole touching a C1–C4 was 16h and any other hole touching a C5/C6 was 24h, so
  C4-to-C5 statics, C1–C4 k-space statics, Pochven, Thera, drifter, and k-space-to-k-space holes were wrong
  or had no lifetime at all.
- Lifetime self-correction: a jump through a wormhole that has outlived its guessed lifetime by more than
  EVE's 30-minute "closure imminent" window promotes it to the shortest candidate that can still be alive and
  restarts the countdown from the remaining time; a candidate still inside that window is treated as alive
  with nothing left and shows EOL. Holes deleted by auto-expiry are remembered by system pair for 48h so the
  jump that recreates the connection corrects it as well. A time status set by a person is never
  overridden. Auto-labeling of the jumped-into system is unaffected: it runs after the connection exists,
  on the same jump.
- A 12h time-status bucket (value 7) for Pochven holes, in the lifetime selector, bookmark name format
  (`time_12h`), and the countdown.

- Auto-labeling fires when a tracked pilot jumps a wormhole connection, not only when a signature is linked
  on splash. The jumped-into system gets its label, tag, or temporary name immediately; a signature linked to
  the same hole later reuses that slot for its bookmark metadata. Gate jumps never label. Chain parents are
  resolved from wormhole connections as well as signatures, so jump-labeled systems chain correctly without
  any signature.

### Changed

- The connection countdown leaves a connection with no known lifetime (time status 0) alone instead of
  forcing it to 24h on its first pass.

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
