# Fork changelog

Differences between [temetvince/wanderer](https://github.com/temetvince/wanderer) (branch `custom`) and
upstream [wanderer-industries/wanderer](https://github.com/wanderer-industries/wanderer). Only fork changes
are recorded here; upstream's own `CHANGELOG.md` is never modified. Newest first.

## 2026-10-16

### Changed

- The Labels submenu of the system context menu offers only the custom label (set and clear). Upstream's
  predefined labels (`A`, `B`, `C`, `1`, `2`, `3`) are no longer selectable, so a system's label is always
  either the server-assigned chain label or one typed by hand.

## 2026-10-09

### Fixed

- Auto-labeling only treats labels of systems connected to the source system (over any chain of drawn
  connections) as occupied slots. A labeled system with no path to the chain, such as a `C` left floating next
  to home or a stale `BC` from a closed hole, no longer blocks that label: the next hole from home becomes `C`
  and the third hole from `B` becomes `BC` instead of skipping to `D` and `BD`.

## 2026-10-06

### Fixed

- A system that appears through tracking (jump or warp into an unmapped system) or from the add-system
  dialog without coordinates is never drawn on top of an existing system. Placement
  (`WandererApp.Map.SystemPlacement`) checks candidates against the systems the map actually draws instead
  of the spatial index upstream keeps in a garbage-collected cache; once that index was evicted after a quiet
  spell, the newcomer landed on the neighbour of the system it was entered from, and under a locked home it
  was unreachable for everyone without permission to unlock and move home.

## 2026-10-01

### Changed

- The manual custom label input (the "Edit label" dialog and System settings) accepts 19 characters instead
  of upstream's 5, so labels as long as the auto-assigned chain labels can be typed and edited by hand.

## 2026-09-28

### Changed

- Auto-labeling roots are explicit: a system with the Home status starts a fresh chain whatever its label
  is, its label never occupies a slot, and it never receives a chain label itself. Every other labeled
  system is a chain prefix, so a chain child keeps chaining off its label after its entrance closes, and a
  named system such as `STAGING` hands out `STAGINGA` unless it is marked Home.

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
  the same hole later reuses that slot for its bookmark metadata. Gate jumps never label.

### Changed

- The connection countdown leaves a connection with no known lifetime (time status 0) alone instead of
  forcing it to 24h on its first pass.

## 2026-09-02

### Changed

- The "Routes" widget is renamed "Shared Routes" in user-facing strings (widget title and widget picker);
  internal ids are unchanged so saved window layouts survive.
- The routes header checkbox "Show shortest" is now "Prefer safest": checked prefers high-sec routes,
  unchecked takes the shortest path.
- Hardened the route origin-strip in `map_routes.ex` to compare system ids loosely (the route service
  returns the origin as a number on some endpoints and a string on others).

### Added

- `AGENTS.md` working agreement, `.markdownlint.json` (all markdown must pass it), and this changelog.

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
