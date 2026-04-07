# Hrafnsyn

Unified aircraft + vessel tracking built with Phoenix LiveView, Elixir, and Postgres.

## What This Project Is

- Realtime merged map for ADS-B aircraft and AIS vessels
- Durable track + point history in Postgres
- Search, route replay, and detail/log panels
- Readonly-by-default access, with lightweight admin-managed users
- Designed to grow a bidirectional gRPC ingest/API layer later

## Why It Is Shaped This Way

- Live polling is done by one long-lived GenServer per upstream source
  because these feeds are continuous and should restart independently
- `Hrafnsyn.Ingest` is the stable boundary between collectors and storage
  so future gRPC/mobile/app-native ingestion can reuse the same pipeline
- Current state and historical points are stored separately
  so the map stays fast while replay/logging remains durable
- LiveView + PubSub drive the UI
  so updates feel realtime without manual frontend state management
- Nix/dev/deploy patterns intentionally follow `vardrun`
  for consistent shells, binary pinning, and service deployment

## Where Things Live

- `lib/hrafnsyn/application.ex`
  supervision tree
- `lib/hrafnsyn/collectors/`
  source config, supervisor, and per-source workers
- `lib/hrafnsyn/ingest/`
  normalized observation boundary
- `lib/hrafnsyn/tracking.ex`
  merged track queries, history writes, PubSub fanout
- `lib/hrafnsyn/tracking/`
  Ecto schemas for tracks and track points
- `lib/hrafnsyn/accounts/`
  auth and admin bootstrap
- `lib/hrafnsyn_web/live/dashboard_live.ex`
  main map/dashboard LiveView
- `lib/hrafnsyn_web/live/admin/`
  admin UI
- `assets/js/app.js`
  MapLibre hook, marker/popup behavior, scroll-preservation hook
- `assets/css/app.css`
  dashboard styling
- `config/runtime.exs`
  runtime env contract
- `nix/module.nix`
  NixOS service module, optional nginx helper
- `proto/hrafnsyn/v1/tracking.proto`
  future gRPC seam
- `docs/`
  architecture, development, and deployment docs

## Current Operational Notes

- Default local workflow is `app`
  which resets local Postgres, starts it, runs setup, and boots Phoenix
- Map rendering currently prefers custom plane/boat markers
  but falls back to visible circle markers if SVG icon loading fails
- Public mode is readonly unless authenticated as admin
- The gRPC transport is planned and deployment-aware, but not fully implemented yet

## If You Change Things

- Keep `mix compile`, `mix test`, and `mix credo --strict` green
- Prefer adding new ingestion methods through `Hrafnsyn.Ingest`
  instead of bypassing it
- Preserve multi-source support
  no logic should assume only one plane feed or one vessel feed
- Keep deployment/docs updates in sync with runtime env changes

## Issue Tracking

This project uses **vardrun** for issue tracking (not GitHub Issues).
When the user says "issue", they mean a vardrun issue.
Run `vardrun prime` for full workflow context — do this at the start of every session.

**Quick reference:**
- `vardrun ready` — find unblocked work
- `vardrun create "Title" --type task --priority 2` — create issue
- `vardrun update <id> --status in_progress` — **take/claim** an issue (auto-assigns you)
- `vardrun update <id> --description "Human-readable summary"` — what the issue is about (for non-developers)
- `vardrun update <id> --implementation @plan.md` — technical implementation details (markdown, for developers)
- `vardrun close <id>` — complete work
- `vardrun show <id> --json` — view issue details (JSON for agents)
- `vardrun list --json` — list all open issues (JSON for agents)
- `vardrun sync` — sync with remote (run after every mutation)

**Taking an issue** = `vardrun update <id> --status in_progress` then `vardrun sync`.
"Take", "claim", "work on", "pick up" all mean this. Always sync after so changes
are visible in the TUI and web interface.

**Completing work:** When committing after finishing an issue, also close it and sync:
```
vardrun close <id>
vardrun sync
git add <files> && git commit -m "..."
git push
```

**For agents:** Use `--json` on any command to discover field structure at runtime.
For full workflow details and all commands: `vardrun prime`
