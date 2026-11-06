# Dashboard critique · 6 November 2026

Impeccable 4.7.0, two independent agents: design assessment plus detector/browser evidence. Target: `lib/hrafnsyn_web/live/dashboard_live.ex`. Reviewed the running application with real traffic at desktop and 390 × 844 phone sizes.

## Findings

The map, direction-aware vehicle symbols, searchable identities, and route context are specific and useful. The surrounding dashboard is generic: a promotional headline, duplicated branding, gradients, translucent rounded panels, and repeated metric cards compete with observation.

1. The map starts at y270 on desktop and y472 on phone. Phone search starts at approximately y1341. Introductory content takes priority over the task.
2. Inspection repeats the popup and puts sharing instructions ahead of movement data. The selected phone inspector measures approximately 1972px tall.
3. The highest sidebar card says “Collector health,” but displays configured source count rather than measured runtime health.
4. Search and live contacts are collapsed. Selection has no obvious dismissal or return to overview.
5. Empty fields, nested cards, inconsistent Aircraft/Plane and Boats/Vessels terminology, and developer-oriented prose add noise.

## Heuristic scores

| Heuristic | Score / 4 |
| --- | ---: |
| System status | 2 |
| Real-world language | 3 |
| User control | 2 |
| Consistency | 2 |
| Error prevention | 3 |
| Recognition | 2 |
| Efficiency | 2 |
| Minimalism | 1 |
| Error recovery | 2 |
| Help | 1 |
| Total | 20 / 40 |

## Technical evidence

No horizontal overflow was found at either inspected size. Search lacked a meaningful accessible label; its disclosure lacked expanded/control semantics. Range buttons lacked pressed state. Panel titles were not headings. Desktop map visibility targets were approximately 22.5px high; map navigation targets were 29px. Dynamic search feedback had no explicit live-region semantics.

The detector flagged the externally loaded Instrument Sans / Space Grotesk font URL. Its `.ex` coverage is limited; empty CLI findings do not establish accessibility. Browser evaluation was read-only, so no overlay was injected. No screen-reader or automated contrast audit was performed during critique.

## Direction

User confirmed: prioritize the map and quick inspection; explicitly remove generic AI dashboard styling. Use compact navigation, immediately visible search, continuous contact rows, a focused inspector, truthful source labels, and native phone/tablet behavior. Preserve source multiplicity, tracking, routes, sharing, and authentication.

Questions skipped: the user already requested implementation after critique and confirmed the map-first priority; no additional critique approval is needed.

## Implemented result

The user chose **Evening watch**. The refreshed workspace uses matte blue-green
surfaces, system typography, continuous contact rows, immediate search, and a map
beside the inspector. Phones stack the map and inspector. Contact identity,
movement and route duration come first; secondary identification fields disclose
on demand. Selection dismissal preserves the camera; Overview restores the active
traffic extent. Reduced-motion preferences also apply to camera movement.

The final web review requested two corrections: move the vehicle type beside its
identity, and add persistent live announcements for typed search results. Both were
scored resolved by the independent reviewer (`ship`, limited to those two fixes).
Evidence is under `.impeccable/review/`, covering desktop, phone, tablet, the 683px
app viewport, selection and empty search. Static detection of the changed targets
returned no findings; this is not a full accessibility certification.

Validation: the complete `mix precommit` gate passes, including compilation with
warnings as errors, Credo strict, all 161 Phoenix tests and security checks.
The six dependency advisories discovered during this work were resolved under
`hrafnsyn-5ww`; no scanner exceptions were broadened. The Linux Nix release also
builds successfully.
