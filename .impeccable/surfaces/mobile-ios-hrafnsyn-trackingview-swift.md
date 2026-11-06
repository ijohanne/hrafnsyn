---
version: 1
slug: "mobile-ios-hrafnsyn-trackingview-swift"
primary_target: "mobile/ios/Hrafnsyn/TrackingView.swift"
related_targets: ["mobile/ios/Hrafnsyn/HrafnsynApp.swift","mobile/ios/Hrafnsyn/AppModel.swift"]
---

# Native traffic client

Mode: Operate. Native iPhone and iPad extension of the same tracking product. Share transport and domain components with future native Android; keep platform rendering native. The server protocol, not fabricated onboarding, decides whether sign-in is required.

## Direction contract

THESIS: Carry geographic inspection into native device navigation. A phone map uses sheets; a wide iPad keeps traffic, map and detail together.

OWN-WORLD: Existing Hrafnsyn raven-eye identity, system text, SF Symbols, semantic grouped surfaces and adaptive teal accents. Daylight and evening use follow the device appearance. Aircraft and vessel markers remain distinguishable.

STORY: Enter the gRPC server, sign in only if required, then inspect traffic. Remember a secure session without retaining a password. Expose retry, empty feeds, server changes and sign-out honestly.

FIRST VIEWPORT: Disconnected state is a native server form. Connected phone gives the map the screen, with Traffic and Server actions. Selecting a contact opens a compact summary with identity, speed, Close, Fit route and Details; the exposed map remains undimmed and interactive. Regular-width iPad shows a searchable sidebar, map and selection inspector; larger text and resizing must remain usable.

FORM: SwiftUI/MapKit native extension, following the existing approved product direction (web reference seed:864dc47a20baf46f); no new direction roll or approved raster comp. Android shares Rust/UniFFI components, not screens.

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

## Selection-panel refinement

The user supplied a phone screenshot in which expanded detail blocked map inspection. Preserve the native visual identity and semantic colors while restoring geographic interaction alongside selection.

One phone panel owns Traffic and detail presentation, so selecting a traffic row changes its content without a timed sheet handoff. Traffic retains medium/large detents. Selected detail begins at `200pt` in portrait and `160pt` in compact vertical size class; accessibility text sizes use `300pt` and `220pt`. The summary scrolls and stacks its actions at accessibility sizes. Details expands to medium in portrait or large in compact vertical size class, and Map returns to the compact summary. All detail detents allow interaction with the exposed, undimmed map.

Fit route frames the route and current selected contact in the unobscured map; using it in expanded phone detail also collapses the panel. Selection may frame the contact and its arriving route, but user camera movement cancels pending route framing and polling preserves that view. Regular-width iPad retains its sidebar/map/inspector arrangement with Fit route in the inspector. Keep these behaviors separate from the global palette and typography; no new shipping raster assets are introduced.

## Verification evidence

Simulator captures: `.impeccable/review/ios-panel-phone-landscape.png`, `.impeccable/review/ios-panel-phone-dark-large.png`, and `.impeccable/review/ios-panel-ipad.png`. Manual simulator checks exercised phone map panning with compact and medium detail panels and iPad pan, zoom and Fit route. These checks do not establish physical-device behavior, every sheet position, or a comprehensive accessibility audit. The final review verdict is recorded by the reviewer separately from this behavior documentation.
