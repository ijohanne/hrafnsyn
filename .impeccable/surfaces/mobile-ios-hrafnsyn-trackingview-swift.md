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

Fit route frames the route and current selected contact in the unobscured map; using it in expanded phone detail also collapses the panel. Route fitting requires at least `50m` of geographic extent and uses actual bounds without an artificial minimum `2km` span. Marker selection preserves the current view for empty, single-position, repeated-position or smaller GPS-jitter histories. Traffic-list selection may recenter an obscured or offscreen contact without changing zoom. User camera movement cancels pending route framing and polling preserves that view. Regular-width iPad retains its sidebar/map/inspector arrangement with Fit route in the inspector. The web selection camera uses the same `50m` route gate and preserves close zoom when falling back to the contact position. Keep these behaviors separate from the global palette and typography; no new shipping raster assets are introduced.

## Verification evidence

Simulator captures: `.impeccable/review/ios-panel-phone-landscape.png`, `.impeccable/review/ios-panel-phone-dark-large.png`, and `.impeccable/review/ios-panel-ipad.png`. Manual simulator checks exercised phone map panning with compact and medium detail panels and iPad pan, zoom and Fit route. These checks do not establish physical-device behavior, every sheet position, or a comprehensive accessibility audit. The final review verdict is recorded by the reviewer separately from this behavior documentation.

The subsequent camera regression fix passed 13 native code tests, including cancellation of delayed route fitting after a new pan. A manual web check with the real JOY contact preserved the `20m` map scale. The earlier panel screenshots and gesture checks remain evidence for the unchanged panel behavior; the new native camera logic has not yet had a fresh simulator interaction check because the Mac was locked. Code-test results are not new screenshot or physical-device evidence.

## Sharing and link navigation

The compact phone summary adds a 44pt native share symbol beside Close, with the contact name in its accessibility label. Full detail and the iPad inspector expose Share track in Identity. SwiftUI supplies the phone share sheet and anchored iPad popover. Links contain the server's canonical public web origin, vehicle identity and history range; an unavailable web address produces an explicit explanation rather than an invented gRPC-port URL.

Incoming links retain the map-first inspection flow. A link for the current instance uses its existing session. A different saved instance or unknown website shows a native server confirmation form before connecting; its editable tracking address accommodates separate web and gRPC origins. Credentials remain partitioned by server. Login and token refresh retain the pending contact, and newer links replace older requests. Inactive contacts remain inspectable. Warm navigation to a stationary contact preserves an existing close zoom; an overview narrows to at most 2km and the contact stays above the phone panel.

Verification: 29 native tests pass, covering server confirmation, origin validation, saved mappings, pending login/refresh, late responses, inactive contacts, same-contact navigation and camera behavior. Fresh simulator captures are `.impeccable/review/ios-share-phone.png`, `ios-share-handoff-phone.png` and `ios-share-ipad.png`. Phone sharing and iPad anchored sharing were exercised through native controls. Safari delivered the actual dashboard-emitted custom-scheme URL through a clearly labeled loopback handoff fixture and opened JOY in the app. The real dashboard's nested mobile detail could not be scrolled through DeviceHub during this check; the fixture isolates OS delivery, not dashboard layout. An earlier manually entered encoded address was rejected; the exact emitted URI passes a Foundation/Rust regression and the anchor handoff. These checks do not establish physical Universal Link association, every Dynamic Type size or every device appearance.

The web keeps Copy link and adds Open in app alongside existing detail actions. Root review verified these controls at desktop 1280×720 and phone 390×844 with unchanged palette, type and wrapping. Login fallback is covered by ExUnit, not a manual authenticated browser check. No shipping raster assets were added.

The unfamiliar-instance form was also opened through Safari, inspected and cancelled without connecting; `.impeccable/review/ios-share-server-confirmation.png` records the website, editable tracking address and explicit Connect and open action. Cancelling returned to JOY on the existing instance. Finish review: the added controls retain native hierarchy, readable labels and map priority; no material visual finding remains within this narrow sharing scope. Broader appearance, accessibility and physical-device verification remain bounded as stated above.

Final rendered review replaced the share service's generic website title and blank thumbnail with `contact · Hrafnsyn` and the existing SF vehicle symbol. The symbol is drawn into an in-memory native image in semantic teal over the grouped background, since exporting a symbolic SwiftUI Image directly produced a blank preview. Refreshed phone and iPad share captures verify aircraft and vessel thumbnails respectively; all 29 tests pass after this refinement. No generated or bundled raster asset was introduced.
