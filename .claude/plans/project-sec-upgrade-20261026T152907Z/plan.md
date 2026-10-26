# Plan: Accepted Hrafnsyn dependency updates U52–U54

**Status**: COMPLETED
**Created**: 2026-10-26
**Last Updated**: 2026-10-26

Baseline: clean master c17d93541f3d534a2a086c827f2b52508ae7e0ea. First-party roots: root Mix Phoenix application, assets/, scripts/build_aircraft_db.py, nix/module.nix and flake.nix. Issue hrafnsyn-dbi. Authoritative baseline SHA256 receipts: /Users/ij/.codex/project-sec-upgrade/runs/20261026T152907Z/projects/hrafnsyn/fingerprints.json. Accepted finish LOCAL VERIFIED/REVIEWED; no source publication, downstream changes or production operations. User authorized phx-work → phx-review without another transition question.

## Phase 1: Exact accepted resolution and audit [COMPLETED]

- [x] [P1-T1][security] Resolve only U52 bandit 1.13.1→1.14.0 and plug_crypto 2.2.0→2.2.1; U53 phoenix 1.8.15→1.8.16 and phoenix_live_view 1.2.12→1.2.13; U54 castore 1.0.21→1.0.22, elixir_make 0.10.0→0.10.1, esbuild 0.10.0→0.10.1, tailwind 0.5.1→0.5.2. Inspect release changes, native Mode B audit before compilation, preserve HTTP overrides/Nov16 exceptions and exact Sobelow fingerprint; format, compile and affected auth/dependency/LiveView tests plus strict Credo. — Exact eight only; native zero BLOCK/WARN, CAStore OIDC actor/repo matches (INFO); format/compile pass, 27 focused tests pass including new crypto/chunk regression cases, strict Credo clean. Existing missing-form-ID diagnostic retained as preexisting debt.

## Phase 2: Complete local verification and reproducible packaging [COMPLETED]

- [x] [P2-T1][direct] Use task-owned flake Postgres18/PostGIS instance (never reset existing dev DB); run full precommit once, assets/runtime smoke, final raw/filtered security, actual fixed-output hash regeneration, Darwin/Linux release and Nix module checks. Check vendor MapLibre/data boundaries without unselected upgrades. Document internal helper-only CLI release N/A. Record truthful unsupported layers and final actual resolved advisory residuals. — Full precommit151passed, assets/runtimeHTTP and Chrome map/search pass, final-source Darwin/Linux release+aircraftDb build exit0, module assertions true; raw/filtered scanners recorded,12 targeted records clear. Native audit pass. Named MapLibre and just-published JOSE vulnerabilities are unselected scope deltas, reported/proposed separately. Semgrep proprietary Elixir parser unavailable (not a clean scan); YARA Phoenix matches same old/new. Task runtime/DB stopped. CLI release N/A: only internal/service/data helpers.

## Phase 3: Complete diff review and handoff [COMPLETED]

- [x] [P3-T1][security] Run sequential read-only phx-review for complete baseline-to-worktree diff with plan coverage; correct actionable findings via phx-work and repeat affected checks within three-cycle cap. Require PASS for ready state, preserve known Cowlib/Gun CVE alias and expiry in result, final file hashes/snapshot and exact check receipts. Close/sync issue only when accepted local scope ready; no source commit/push/deploy. — PASS, no new actionable findings; all accepted requirements met. Review and complete source snapshot saved in this run's project report directory. New MapLibre and JOSE findings remain proposed separately; accepted rows complete locally.

Acceptance criteria: all eight exact accepted versions, no unrelated dependencies/runtime/pins; twelve listed CVEs disappear from final unfiltered lock query; remaining Cowlib/Gun same CVE stays explicitly reported with owner Ian Johannesen, issue hrafnsyn-fhv, expiry 2026-11-16; no new ignore or expiry extension. Existing security/full test/compile/format/Credo/assets and native integration gates pass; reproducible release/dependency hashes and module consumer checks verified on available Darwin/Linux platforms. Deployment intentionally NOT DEPLOYED. Coverage boundaries (runtime/OS, deep vendor supply chain) remain explicit rather than false clean claims.

## Authorized security continuation — U55, U56, U60

User explicitly authorized substantive security fixes, including necessary major migrations, for this run. U52–U54 remain completed and preserved. Local-only publication boundary persists. Earlier requirements to keep Cowlib at its vulnerable Hex version are superseded by U60's actual source fix; preserve the Sobelow HTTPS expiry and CSP. Do not merely extend the encoder mitigation or declare scanner omissions fixed.

## Phase 4: Implement source and browser security fixes [COMPLETED]

- [x] [P4-T1][security] Update JOSE exactly 1.11.13; inspect/audit and use exact upstream Cowlib fix 4401b858f2229abb3ea115c60924f6c77e5f8aa3 or a minimal audited backport. Prove structured-field CR/LF/control rejection and safe round-trips, JWT/native crypto behavior, actual provenance and scanner catalog residual truth. Retire encoder mitigation ignore where applicable; maintain no broader ignore or expiry extension.
- [x] [P4-T2][liveview] Migrate vendored MapLibre 5.19.0 to verified 6.4.1 ESM/main/shared/worker/CSS distribution and consumer loading; preserve CSP and same-origin workers. Add meaningful actual attribution exploit regression independent of CSP. Verify WebGL2 map, controls, markers/popups, feature/route updates, visibility and reconnect behavior plus focused tests.

## Phase 5: Serialized complete gate and final packaging [COMPLETED]

- [x] [P5-T1][direct] Obtain coordinator READY_HEAVY grant before full precommit/full suite; send HEAVY_DONE afterward. Use task-owned PG18/PostGIS only. Run final native/source/security/raw advisory checks, assets/browser regression and actual Mix hash/Darwin/Linux release/module builds. No source commit/push, pins or activation.

## Phase 6: Final complete diff review [COMPLETED]

- [x] [P6-T1][security] Review entire baseline-to-final diff through read-only phx-review, require PASS after bounded corrections; save exact source/artifact/checkpoint hashes, fixed IDs and any source-fixed catalog discrepancies; close/sync issue only when all authorized local work is complete.

Final continuation evidence: full155-test gate PASS under coordinator lease; final static/security PASS; fixed6.4.1 browser fixture10PASS and old5.19.0 exploit reproduced without CSP; actual app plane/vessel selection/route/visibility/Search and no-WebGL2 fallback pass. Native9Hex + exact CowlibGit delta reviewed. Final Darwin/Linux releases and aircraftDb build exit0 after documented three-attempt packaging replan; immutable-FOD loader proof and packaged Cowlib/JOSE boundary probe pass. Source attestation matches all20 business-file changes; complete-diff phx-review PASS. All task processes/DB stopped, own ephemeral83MB removed, old idle devdata preserved. No publication/pins/deploy. Forced network-outage reconnect/Safari/Firefox matrix not claimed; existing LiveView lifecycle/server tests and real normal navigation checked.
