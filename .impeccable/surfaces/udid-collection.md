---
version: 1
slug: "udid-collection"
primary_target: "lib/hrafnsyn_web/controllers/device_html.ex"
related_targets: ["assets/css/devices.css", "assets/js/mobile_build_upload.js"]
---

# Device invitation collection

Mode: Operate. Extend Hrafnsyn's approved Evening watch web system with a focused device-registration task. The user explicitly requested a self-hosted collection page and shareable friend invitations; no new visual world or concept chooser is needed.

## Direction contract

THESIS: Let a signed-in owner create a device link and retrieve its result; let a friend understand and approve the collection on their own iPhone or iPad.

OWN-WORLD: Inherit matte blue-green grounds, pale type, cyan actions, small control radii, compact system text and clear separators. Use no decorative imagery, promotional heading, nested cards or status dashboard.

STORY: An owner names one device, shares one expiring link and later copies its UDID. A guest opens Safari, downloads and approves an unsigned Profile Service profile, then checks receipt. The profile requests only the UDID. It neither installs the app nor enrolls the device in remote management. Registration with Apple and signing remain separate steps. The signed-in owner page also offers the current IPA download, with a private administrator upload/replace action; downloading the IPA does not install it.

FIRST VIEWPORT: Owner page places a flat app-download section before the creation form and invitation list. Download metadata sits beside the download action on desktop; the mobile layout stacks these with a full-width download action and then stacks the invitation regions. Administrator upload controls stay inside a native disclosure. The guest page is a narrow reading column with three ordered actions and clear receiver identity; received, invalid, expired and collection-error states use explicit text. Public pages never expose a collected UDID.

FORM: A code-led extension of the established system. Plain server-rendered Phoenix forms retain CSRF handling and work without clipboard JavaScript. Readonly fields support selection/copying; delete uses an explicit confirmation. Long labels wrap, long identifiers scroll inside their fields, and controls retain at least 44px interaction heights.

FINISH: Parent performs controller integration, responsive browser verification and the independent finish review. No physical iOS approval flow has been claimed as tested by this UI implementation.

## Documentation boundary and evidence

The finished controller markup and `assets/css/devices.css` extend Evening watch without changing `DESIGN.md` or `.impeccable/design.json`: the seven workspace colors, flat separators, 5px/6px control radii and cyan focus treatment match the incumbent system. Owner received-state desktop/mobile captures and the 683px guest capture in `.impeccable/review/` show the two-column/stacked form and ordered guest instructions; the owner captures distinguish 7-day link validity from 30-day record retention after creation.

Surface-local values are not promoted to global tokens: 26px desktop headings, 15px reading text, 16px editable/mobile readonly fields and the lighter cyan hover (`#a9e0eb`). The detector's 16px advisory overlaps an existing documented mobile-search adaptation in `DESIGN.md`; legacy shared-navigation styling is also pre-existing and remains outside this extension. No new display role or design-system revision is authorized. These captures establish rendered layout only, not physical iOS profile approval or complete accessibility coverage.

The copy refinement reuses one field component for invitation links and collected UDIDs. Adjacent controls have a 48px minimum height, a stable 104px width and 18px clipboard/check icons; they retain the incumbent panel, cyan, divider and focus colors. `assets/js/device_clipboard.js` shows “Copied” and polite field-specific feedback only after the clipboard operation reports success, then resets after four seconds. If both clipboard paths fail, the readonly text is selected and manual-copy instructions appear; direct field selection remains available without JavaScript. The reviewed `udid-copy-desktop.png`, `udid-copy-mobile.png`, `udid-copy-user-1280.png` and `udid-copy-blocked-mobile.png` captures verify visible success feedback for both field types and the selected-text fallback without changing the page hierarchy. These controls remain a surface extension; global design files are unchanged, and physical iOS profile-flow verification remains separate.

The IPA extension retains those same colors, typography and controls. A divider and 24px vertical padding separate the app section; file size and update time use tabular figures. The administrator disclosure retains a 44px minimum target and the established cyan focus outline. Its form caps at 620px, with 16px gaps; the native file selector uses the incumbent raised surface, pale text and 4px compact radius. At the existing 760px breakpoint, the download region stacks and its action fills the available width. These are surface-local compositions, not new global tokens or a new visual world.

Every signed-in user can download the one current IPA. Only administrators see the upload/replace form. Its help states the 250 MiB limit, replacement of the current file without version history, and the need for a signed Ad Hoc build that includes the testers’ devices. The page distinguishes missing and temporarily unavailable builds. `assets/js/mobile_build_upload.js` rejects oversized files before submission, announces upload activity politely, disables duplicate submission and restores controls on page return. Installation guidance separates downloading from installing on a registered device; no physical installation success is implied.

The finish reviewer returned **ship** with no material fixes for this extension. The validated `.impeccable/review/ipa-desktop.png`, `ipa-mobile.png` and `ipa-user-1280.png` captures cover administrator desktop/mobile layouts, including a 1280px desktop view. Despite its filename, the 1280px capture displays administrator controls; it does not establish the regular-user view. These captures establish the rendered hierarchy, not physical-device installation or comprehensive accessibility coverage. `PRODUCT.md`, `DESIGN.md` and `.impeccable/design.json` remain unchanged. The previously recorded legacy shared-navigation styling and surface-specific type sizes remain outside this addition and are not repaired or promoted into global rules.
