---
name: Hrafnsyn
description: Evening watch — a steady geographic workspace for aircraft and vessel inspection.
colors:
  work-bg: "#152329"
  work-panel: "#203239"
  work-raised: "#2b4149"
  work-ink: "#e6eeef"
  work-soft: "#afc1c6"
  work-line: "#40565e"
  work-accent: "#88d1e2"
  work-plane: "#78c6dc"
  work-vessel: "#efb486"
  work-selection: "#d6bc71"
  navigation-bg: "#19383f"
  map-plane: "#64d2ff"
  map-vessel: "#f97316"
  map-route: "#f4c95d"
typography:
  headline:
    fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif'
    fontSize: "24px"
    fontWeight: 650
    lineHeight: 1.2
    letterSpacing: "-0.025em"
  title:
    fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif'
    fontSize: "17px"
    fontWeight: 650
    lineHeight: 1.45
    letterSpacing: "-0.02em"
  section:
    fontSize: "15px"
    fontWeight: 650
    lineHeight: 1.45
  body:
    fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif'
    fontSize: "14px"
    lineHeight: 1.45
  label:
    fontSize: "13px"
    lineHeight: 1.45
  supporting:
    fontSize: "12px"
    lineHeight: 1.45
  metadata:
    fontSize: "11px"
    lineHeight: 1.45
rounded:
  compact: "4px"
  action: "5px"
  control: "6px"
  floating: "8px"
spacing:
  small: "6px"
  compact: "8px"
  control: "12px"
  mobile-inset: "16px"
  inspector-inset: "18px"
  toolbar-inset: "20px"
  section-gap: "24px"
components:
  button-map:
    backgroundColor: "{colors.work-panel}"
    textColor: "{colors.work-ink}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    padding: "0 12px"
  button-detail:
    textColor: "{colors.work-ink}"
    typography: "{typography.supporting}"
    rounded: "{rounded.action}"
    padding: "6px 10px"
  button-detail-hover:
    backgroundColor: "{colors.work-raised}"
  search-input:
    backgroundColor: "{colors.work-panel}"
    textColor: "{colors.work-ink}"
    typography: "{typography.body}"
    rounded: "{rounded.control}"
    padding: "0 42px 0 36px"
    height: "42px"
  navigation-link:
    typography: "{typography.label}"
    rounded: "{rounded.compact}"
    padding: "12px"
  route-range:
    textColor: "{colors.work-soft}"
    typography: "{typography.supporting}"
    rounded: "{rounded.compact}"
    padding: "4px"
  route-range-active:
    backgroundColor: "{colors.work-raised}"
    textColor: "{colors.work-ink}"
  inspector:
    backgroundColor: "{colors.work-panel}"
    textColor: "{colors.work-ink}"
    width: "352px"
  contact-row:
    textColor: "{colors.work-ink}"
    padding: "11px 18px"
  contact-row-hover:
    backgroundColor: "{colors.work-raised}"
---

# Design System: Hrafnsyn

## Overview

**Creative North Star: "Evening watch"**

A matte blue-green workspace keeps geographic information legible during repeated inspection. Pale text, quiet dividers and compact controls support the map; cyan aircraft and warm vessel cues distinguish the two traffic types. The existing Hrafnsyn name and logo remain the identity assets.

This document records the implemented web tracking workspace in `assets/css/tracking.css`, `lib/hrafnsyn_web/live/dashboard_live.ex` and `assets/js/app.js`. Its frontmatter describes web tokens. The global navigation and body inherit parts of this refresh, but administrative, authentication and other routes still carry legacy `assets/css/app.css` styling; their old cards, decorative backgrounds and display typography are not the new workspace system. Native SwiftUI and Android Compose use their own adaptive semantic colors and platform components as described below. Android implementation authority is `mobile/android/app/src/main/java/io/hrafnsyn/mobile/MainActivity.kt`, `TrafficMap.kt` and the map vector drawables; native values below extend the web system without redefining its frontmatter.

The earlier SwiftUI finish review returned a ship verdict after checking setup and overview on phone and tablet in light, dark and large-type appearances, plus selected dense-traffic iPad views. The subsequent iOS selection-panel refinement has simulator evidence for phone landscape, dark appearance with large text, and iPad selection. Manual simulator checks exercised panning with compact and medium phone detail panels and iPad pan, zoom and route fitting; its final review verdict remains separate. The login UI and physical-device behavior were not visually exercised; authentication protocol and Keychain behavior were tested separately. The Android finish review returned a ship verdict for the three reviewed fixes: recognizable vehicle symbols, explicit neutral/teal Material roles and phone selection visibility above the initial detail sheet. Evidence covered phone overview, traffic list, detail, setup and unreachable-server error, plus tablet overview and detail in dark appearance at 130% font scale. The reviewer observed no regressions in those views and confirmed documentation persistence. Login UI, physical-device behavior and arbitrary sheet dragging remain outside that evidence.

**Key Characteristics:**

- Geographic content with adjacent, independently scrolling inspection.
- Matte tonal surfaces, small corner radii and clear separators.
- Compact system text and aligned numerical information.
- Explicit vehicle, selection and connection states.
- Platform-native navigation and adaptive native appearance.

## Colors

The web palette uses low-chroma blue-green surfaces with pale foregrounds and restrained functional accents; frontmatter values are authoritative. The sidecar's generated tonal ramps are preview swatch aids, not additional application tokens.

### Primary

- **Clear cyan** (`work-accent`): focus outlines, caret, text selection and interactive legend feedback.
- **Aircraft cyan** (`work-plane`): aircraft icons, counts and type labels in the workspace.

### Secondary

- **Warm vessel** (`work-vessel`): vessel icons, counts and type labels.
- **Muted route gold** (`work-selection`): the active route-range underline.
- **Map aircraft, vessel and route** (`map-plane`, `map-vessel`, `map-route`): brighter geometry cues on the map and matching legend swatches. The map deliberately retains its own higher-chroma marker palette.

### Neutral

- **Deep water** (`work-bg`): the workspace and body ground.
- **Watch panel** (`work-panel`): inspector, search field and floating map controls.
- **Raised panel** (`work-raised`): contact hover and active route controls.
- **Pale ink** (`work-ink`): primary workspace text.
- **Quiet ink** (`work-soft`): supporting labels, age and metadata.
- **Slate divider** (`work-line`): structure, input strokes and scrollbars.
- **Navigation teal** (`navigation-bg`): the shared top navigation bar.

**The Geographic Color Rule.** Keep map geometry and its legend synchronized; do not substitute the softer inspector colors for one side of that pair.

### Native platform boundary

SwiftUI uses `.primary` and `.secondary` foregrounds, UIKit `systemBackground`, `systemGroupedBackground` and `secondarySystemGroupedBackground`, plus `.regularMaterial`. These semantic roles adapt to appearance and must not be frozen into web hex values. `AccentColor` has source sRGB components `(0.024, 0.353, 0.369)` in light appearance and `(0.392, 0.824, 0.843)` in dark appearance. Native aircraft use this accent; vessels use semantic `.indigo`; routes use `.teal`; selected traffic rows use `.teal.opacity(0.12)`. Errors use `.red`. These are platform-specific encodings, not claims of pixel-identical palettes across clients.

Android uses explicit Material 3 light and dark schemes selected by system appearance. Primary teal is `#0b6570` / `#7dd3de`, with white / `#00363d` on-primary text. Aircraft list icons use primary; vessels use warm tertiary (`#9c4a1a` / `#f4b48b`). Background and surface are near-neutral `#f7f9f8` / `#111719`, with on-surface `#182427` / `#e1e8e8` and supporting on-surface-variant `#4c6268` / `#b9c7ca`. Low, ordinary and high surface containers progress through `#f0f4f3`, `#eaf0ef`, `#e2eae8` in light appearance and `#192124`, `#1d272a`, `#263135` in dark appearance. Selected traffic rows use secondary-container (`#d7e9e9` / `#30474d`); the scheme defines matching on-secondary-container (`#1a393e` / `#d8edf0`). Secondary is `#4c6268` / `#b9cbd0`. Roles not explicitly supplied, including error-container roles, retain Material defaults. These are Android semantic assignments, not web aliases or a dynamic wallpaper palette.

Android map vehicle vectors have their own stable cyan (`#0b8394`) and warm brown (`#b25a26`) fills on white circular grounds. Gold (`#e5b84e`) marks route and selection; the selected circle has a dark `#172c31` outline. Cluster fill and text reuse the appearance-specific primary/on-primary pair. This map palette is distinct from both the web legend and adaptive Android list icons.

## Typography

The web workspace uses the system UI stack in the frontmatter. It has no promotional display role. Contact identity is the strongest text; section headings, controls and metadata descend through a compact hierarchy. Numeric content uses tabular figures at the workspace boundary.

- **Headline:** selected identity; wraps long identifiers instead of forcing horizontal overflow. It reduces to `21px` on phone widths.
- **Title:** workspace title; reduces to `15px` on phone widths.
- **Section:** inspector headings. Subsection headings use the label size at weight `650`.
- **Body:** ordinary controls and workspace copy.
- **Label:** traffic totals and contact names; contact names truncate within their row.
- **Supporting:** descriptive copy, action labels and observation ages.
- **Metadata:** compact table headings, secondary identities and log values.

SwiftUI text uses native text styles (`title2`, `headline`, `body`, `subheadline`, `footnote`, `caption`) and monospaced digits for measurements. Accessibility Dynamic Type switches traffic rows from a horizontal arrangement to a vertical stack. Preserve the text styles rather than translating the web pixel scale into native fixed sizes.

Android inherits Material 3 typography rather than defining a custom font or pixel ramp. `headlineSmall` identifies connection setup and selected contacts; `titleLarge` names the empty-map state; `titleMedium` names inspector sections. `bodyLarge` carries measurements, `bodyMedium` carries explanation and identity, and `bodySmall` carries connection help. `labelLarge` carries totals and row speed; `labelMedium` carries ages and measurement labels. Contact names allow two lines before ellipsis. The map uses Noto Sans Regular for cluster counts (`14`) and selected labels (`13`) in MapLibre style units. Android measurements currently use default Material figures, without an explicit tabular or monospaced feature; do not describe that as cross-client numerical parity.

**The Measurement Rule.** Align changing numeric values with tabular or monospaced digits; retain normal proportional text for names and prose.

## Layout

The desktop workspace fills the viewport below the `56px` navigation bar. A task toolbar has a `64px` minimum height. The map and inspector form a two-column grid; the inspector is `352px`, increasing to `384px` from a viewport width of `1600px`. The map consumes the remaining space. Inspector content and contact lists scroll within the workspace. Search sits at the right of the toolbar with a maximum width of `360px`.

At `950px` and below, search takes its own full-width toolbar row and the inspector narrows to `310px`. At `760px` and below, navigation becomes `52px` high and map and inspector stack in one column. Their minimum row heights are `220px` and `180px`; the workspace has a `560px` minimum height so short viewports can scroll. Phone controls enlarge where declared: search is `44px` high with `16px` text; map controls, range tabs and the inspector close control have `44px` targets. These are observed adaptations, not a claim that every web target is `44px`.

The recurring inset rhythm is the frontmatter spacing scale: compact control gaps, larger inspector insets and generous separation between functional sections. Rows and measurements share alignment; the map remains an unrounded edge-to-edge canvas.

Native compact width uses a `NavigationStack` and one phone panel that changes from traffic to selected detail. Traffic uses medium/large detents. Selection starts with a compact summary at `200pt`, or `160pt` in compact vertical size class; accessibility text sizes increase these heights to `300pt` and `220pt`. Detail can expand to medium/large detents while the exposed map stays undimmed and interactive at every detail detent. Regular width retains a `NavigationSplitView`, map and selected-track inspector; sidebar and inspector widths range from `280pt` to `400pt`, ideally `320pt`. SwiftUI decides collapse and presentation from size class rather than web breakpoints. Setup and login forms cap their content width at `640pt`. Map markers and the fit control have `44pt` interaction frames.

Android adapts to available window width in dp. Below `840dp`, the top app bar switches between map and traffic list, and selection opens a dismissible Material modal bottom sheet; its detail content requests 85% of available height. From `840dp`, a `320dp` side pane sits beside the map and changes from traffic to detail on selection. From `1200dp`, traffic remains in the left pane and a separate `320dp` right inspector appears for selection. Dividers separate panes, and lists and details scroll independently. The compact selected camera adds bottom padding equal to half the map view height so the contact sits in the geographic area above the initial sheet; this is a source behavior, not a guarantee for every dragged sheet position.

Android setup/login content caps at `520dp` with `24dp` outer padding, `16dp` vertical gaps, scrolling and IME padding. Search has `12dp` insets; horizontally scrolling filter chips use `8dp` gaps. Traffic rows have a `72dp` minimum height. Inspector content has `20dp` padding and `16dp` section gaps. The bottom status row includes navigation-bar padding, active count or reconnecting text, observation age and an Overview action. Scaffold insets keep app bars separate from content.

## Elevation & Depth

Web depth comes primarily from tonal panels and separators. The map and inspector have no decorative elevation. Shadows distinguish floating search results, map controls and popups from geographic content: search uses `0 8px 28px #0005`, map overlays use `0 2px 8px #0002`, and popups use `0 5px 18px #0003`. The active route control uses an inset underline rather than an elevated shadow.

**The Floating Context Rule.** Reserve workspace shadows for content that floats over the map or another interaction surface.

SwiftUI bottom status content and the empty-map message use regular material. SwiftUI sheets, grouped lists and navigation retain platform-provided depth; do not copy web shadow values into them.

Android uses Material tonal elevation: side panes at `1dp`, the bottom status surface at `2dp`, and the empty-map message at `3dp`. The modal sheet retains Material depth and scrim behavior. Flat list items and pane dividers carry the rest of the structure; no custom web shadows are translated into Compose.

## Shapes

The web canvas, inspector and contact rows are square-edged. Small rounded corners identify controls; the slightly larger floating radius belongs to search results. Type dots and map symbol points are circular. Route legend geometry is a short line. Borders divide content and expose field boundaries without surrounding every value in a card.

SwiftUI markers are circular, with `26pt` symbol bodies inside their interaction frames. The empty-map material container has `16pt` corners. Other shapes come from native grouped forms, segmented controls and sheet presentations.

Android retains Material defaults for buttons, outlined fields, filter chips and modal-sheet corners rather than defining a custom shape scale. Map vehicle symbols are `24dp` vector drawables rasterized at device density. MapLibre grounds use radius `13`, selection radius `17` with stroke width `2`, and clusters radius `23` in style units. Vehicle silhouettes remain visible within these circular grounds.

## Components

### Buttons

Map Overview is a panel-colored floating button. Detail actions are compact outlined controls; hover fills them with the raised-panel tone. Inspector close is a quiet icon control whose hover reveals the raised tone. Workspace focus uses a `2px` cyan outline with `3px` offset. Button labels remain plain sentence case.

### Search

The search input has a panel background, divider stroke and control radius. Its inset reserves space for search and clear icons. Results are a floating, scrollable list of the same contact rows used by the inspector. Search feedback has a polite live region, and an empty query result explains the state in text.

### Navigation and route controls

The top navigation uses plain links over navigation teal, with a translucent light hover fill. Phone layout hides the first link and profile text. Route ranges are compact sibling buttons; active state combines raised fill, pale text and the selection underline. They are functional controls, not decorative badges.

### Inspector and contact rows

The inspector is a continuous panel separated from the map by one divider. Contact rows arrange a vehicle icon, two-line identity and right-aligned measurements. Hover changes the row background. The selected view replaces the list with identity, measurements, route range, expandable identity fields, actions and recent observations. Source configuration appears in a collapsible section; its count does not assert feed health.

### Geographic canvas

Aircraft and vessel SVG markers retain recognizable silhouettes, with visible circle fallbacks if icon loading fails. Marker colors match the legend; route geometry is gold. Layer toggles strike through their labels when muted. Web selection fits route history only when its geographic extent reaches `50m`; otherwise it centers the contact while preserving an existing close zoom. Camera movement lasts `900ms`, or `0ms` with reduced motion. Workspace reduced-motion CSS disables animations, transitions and smooth scrolling.

Native MapKit uses a muted standard map without points of interest, SF Symbols for vehicle markers, count clusters and a teal route polyline. The selected marker inverts foreground and background. Native traffic search, type filtering, pull-to-refresh, retry, empty states and server settings use standard SwiftUI controls.

The native phone selection summary keeps identity, type, speed, Close, Fit route and Details together in scrollable content. Accessibility text sizes stack the actions vertically. Details expands to medium in portrait or large in compact vertical size class; Map returns expanded detail to its compact summary. Fit route frames the selected route and current contact within the unobscured map, collapsing expanded phone detail first. The iPad inspector also exposes Fit route. Route fitting requires at least `50m` of geographic extent and uses the actual bounds without an artificial minimum `2km` span. Empty, single-position, repeated-position and smaller GPS-jitter histories leave marker selection at the current view; selecting from Traffic may recenter an obscured or offscreen contact without changing zoom. Once the user moves the camera, polling does not reset that view. Selecting from Traffic replaces content in the same phone panel without a timed dismissal-and-presentation handoff. Route loading, missing or stationary history and retry remain explicit states.

### Android controls and geographic canvas

Compose uses Material top app bars, labeled outlined fields, full-width connection buttons with a `48dp` minimum height, text/outlined secondary actions, filter chips and standard icon buttons. Busy connection actions disable editing and show progress with text. Errors use an error-container surface with explanatory text and a Retry action when available. Server settings expose the current address, access state, change-server action and sign-out when applicable. Back first clears selected detail, then returns from traffic to the map.

Traffic uses a `LazyColumn` of Material list items with Flight or DirectionsBoat symbols, textual type, identity and trailing speed. Selection uses a secondary-container fill. Detail content is scrollable, has a labeled close button, and shows measurements and a six-hour route summary with loading progress. Empty search/category results and empty server traffic have distinct text. These components retain native semantics and interaction behavior rather than copying web markup.

Android MapLibre loads OpenFreeMap Liberty in light appearance and Dark in dark appearance. Bundled Material aircraft/boat vectors form recognizable symbols; attribution for the source icons is retained in the Android artwork and asset licenses. GeoJSON clustering uses radius `64` through maximum zoom `14`; selecting a cluster moves to its expansion zoom. A separately rendered selected contact carries a name with contrasting halo, gold ground and route line of width `3`. Map hit testing uses a `24dp` radius around the tap. Overview fits available traffic with `32dp` bounds padding; a lone contact uses zoom `10`. Camera changes currently use immediate `moveCamera` calls rather than the web's animation duration. Map-loading failures leave a text notice and access to traffic/search; source-level fallback behavior is not a claim of offline map support.

## Do's and Don'ts

### Do:

- **Do** keep aircraft, vessel and route cues consistent with their own map legend.
- **Do** use aligned numerical text and clear supporting labels for changing measurements.
- **Do** preserve independent scrolling and visible ways to return to geographic overview.
- **Do** retain semantic native colors, text styles, materials and size-class adaptation.
- **Do** describe empty, reconnecting and authentication states with explicit text.

### Don't:

- **Don't** treat configured source counts as evidence of live collector health.
- **Don't** carry legacy decorative dashboard cards or display headings into the tracking workspace.
- **Don't** replace native semantic roles with the web workspace's fixed dark colors.
- **Don't** add generated decorative art to substitute for the geographic content or existing logo.

Not canonized or repaired: legacy styling on non-dashboard routes remains outside this refresh. The web's small metadata sizes are recorded only for compact supporting content, not promoted to a general body-text rule. Android has no explicit tabular-number setting; its source-defined camera padding does not establish visibility at every sheet position. SwiftUI coverage remains simulator-only for the selection-panel refinement; it does not establish every gesture or sheet position, login-UI or physical-device behavior, and is not a comprehensive accessibility audit. Android review is limited to the three fixes and captured views above; it does not establish login-UI, physical-device or arbitrary-sheet-drag behavior.
