---
version: 1
slug: "lib-hrafnsyn-web-live-dashboard-live-ex"
primary_target: "lib/hrafnsyn_web/live/dashboard_live.ex"
related_targets: ["assets/css/tracking.css","assets/js/app.js"]
---

# Live tracking workspace

Mode: Operate. Repeated inspection of live aircraft and vessels; map, search and route context take priority. Preserve multi-source data, readonly access, deep links, history and FlightAware actions. User selected Evening watch from the code-led direction chooser.

## Direction contract

THESIS: A geographic workbench for quick contact inspection. Remove the marketing introduction and nested card dashboard.

OWN-WORLD: Evening watch: matte blue-green shell, pale text, cyan aircraft and warm vessel cues, restrained yellow route selection. System UI type, compact labels, clear dividers and plain controls. A person checking traffic beside a window after dusk needs steady contrast without luminous decoration.

STORY: See traffic, find a contact, inspect movement, then return to the map without losing context. Configuration counts do not claim collector health.

FIRST VIEWPORT: A 56px navigation bar and 64px task toolbar above an expansive map and 352px right inspector. Search sits at upper right. Phones stack map and inspector with independently scrollable contents. Selecting a contact replaces the list with route and movement details; Overview restores geographic context.

FORM: Map plus inspection rail, chosen alternative to assigned Coastal atlas; seed:864dc47a20baf46f. Code-led, matching `.impeccable/mocks/decision/night.html`; no approved raster comp.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

## Verification scope

Web at 1440×900, 390×844, 683×838 and tablet width. Native app uses SwiftUI/MapKit conventions, phone sheet and iPad sidebar/map/inspector, Dynamic Type and semantic colors; core transport shared with future native Android. No decorative generated assets required.
