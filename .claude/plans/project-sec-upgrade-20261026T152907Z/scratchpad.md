# Hrafnsyn upgrade scratchpad

Read before execution. Scan facts apply only to Hrafnsyn. No compound solutions directory exists.

- Use explicit fish via login:false. Project Nix shell has a hook that mutates deps/heroicons; override shellHook empty and export MIX_HOME=.nix-mix, HEX_HOME=.nix-hex plus actual Nix esbuild/tailwind paths explicitly. getFlake path failed on an existing PostgreSQL socket; git+file URI works without source commits.
- Existing .pgdev instance must be preserved. Use PGDEV_DIR=/tmp/hrafnsyn-sec-20261026T152907Z with bundled pg-start/pg-stop and explicit TEST_DATABASE_URL/DATABASE_URL for that port/socket only. Stop only task-owned instance.
- Prior scan `mix deps.audit --help` unexpectedly compiled dependencies; stopped upon detection. Execution now authorizes build, but first inspect actual package changes/audit before compiling. Eight exact targets only, no deps.update --all.
- Preserve grpc/googleapis/gun/peep overrides. Existing dependency_compatibility_test.exs checks Peep5 export, googleapis status details and Gun CRLF rejection.
- Preserve security gate exact Cowboy2.20.0/Cowlib2.21.0/Gun2.7.0 guard and all ignored IDs/expiry/fingerprint. Current raw OSV14 rows include twelve new CVEs and two aliases of CVE-2026-43966; no released Cowlib fix. Do not infer deployment from local fixes.
- No first-party distributed CLI observed: release admin executable, pg-dev helpers and aircraft-db builder are internal service/build helpers. Confirm repository channel evidence before N/A final statement. Do not invent Homebrew distribution.
- User preauthorized research and phx-work→phx-review transition through project-sec-upgrade; no routine prompts. Native audit uses Mode B baseline HEAD vs working lock. No nested workers needed.

## Authorized continuation

U55 MapLibre6.4.1, U56 JOSE1.11.13 and U60 actual Cowlib fix are now accepted. Supersede earlier exact-Cowlib preservation and pending-selection notes; preserve U52–U54 changes. No package/major approval prompt is needed. Investigate direct fixed-source versus minimal backport before choosing. Remove obsolete encoder mitigation exceptions where the actual fix is proved; preserve the unrelated Sobelow HTTPS fingerprint/expiry and transport validation. Source-based scanner catalog discrepancies must remain visible.

Coordinator globally serializes full suites: send READY_HEAVY with exact command, wait grant, then HEAVY_DONE. Focused tests, source research and builds without full suites may proceed concurrently. Task-owned DB path remains safe; restart it via bundled pg-start. No recursive delegation or sibling source inspection. After three failed concrete attempts, checkpoint and research/replan a justified approach with coordinator instead of repeating unchanged.

## Packaging research after three concrete attempts

Nix shells enable glob behavior that drops unquoted external patterns: quote all esbuild --external arguments. After that fix, assets bundle successfully, but direct `mix phx.digest --no-compile --no-deps-check` still cannot work with normalized Git dependency metadata. Mix.Task.maybe_load_or_compile_task/2 calls deps.loadpaths with no args before it finds dependency tasks, so the flag never reaches the first check. Nix fetchMixDeps intentionally retains only .git/HEAD, and Mix.SCM.Git also requires origin config. Primary Mix.Task/Git and Nix compile/release hook source inspected. Replanned recipe explicitly preloads through the built-in task: `mix do deps.loadpaths --no-deps-check, phx.digest --no-compile`. Verified locally against the immutable FOD (proof exit0) before another release build. Do not retry the direct-task forms.

Full155 gate passed under coordinator lease; subsequent fixes are JS capability preflight and Nix-only packaging, covered by actual browser/assets/build checks, not another full backend suite. Actual no-WebGL2 browser test found v6 logs an error and returns an invalid map instead of throwing; explicit disposable context probe now runs before construction, loses its temporary context, and shows usable status when absent. Actual page fallback/Search tested, then normal rendering restored.

Lifecycle cleanup completed after browser tests: task app/fixtures and PG57655 stopped, exact task cluster removed. Old preexisting PG60329 had zero client backends/no app dependency in two checks, stopped via pg-stop but data retained. Do not restart either DB for packaging/review. Any new focused DB check requires explicit task-owned pg-start lifecycle again.

Final result: verified loader-preflight replan succeeded, Darwin/Linux/source/module/package probes PASS. No further backend source changes/full-suite rerun. Final review PASS; named residual catalog alias is source-fixed, no new ignore or expiry extension. Local-only finish.
