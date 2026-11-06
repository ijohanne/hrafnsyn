---
version: 1
slug: "udid-collection"
primary_target: "lib/hrafnsyn_web/controllers/device_html.ex"
related_targets: ["assets/css/devices.css"]
---

# Device invitation collection

Mode: Operate. Extend Hrafnsyn's approved Evening watch web system with a focused device-registration task. The user explicitly requested a self-hosted collection page and shareable friend invitations; no new visual world or concept chooser is needed.

## Direction contract

THESIS: Let a signed-in owner create a device link and retrieve its result; let a friend understand and approve the collection on their own iPhone or iPad.

OWN-WORLD: Inherit matte blue-green grounds, pale type, cyan actions, small control radii, compact system text and clear separators. Use no decorative imagery, promotional heading, nested cards or status dashboard.

STORY: An owner names one device, shares one expiring link and later copies its UDID. A guest opens Safari, downloads and approves an unsigned Profile Service profile, then checks receipt. The profile requests only the UDID. It neither installs the app nor enrolls the device in remote management. Registration with Apple and app distribution remain separate steps.

FIRST VIEWPORT: Owner page leads with the creation form beside a flat invitation list. The mobile layout stacks those regions. The guest page is a narrow reading column with three ordered actions and clear receiver identity; received, invalid, expired and collection-error states use explicit text. Public pages never expose a collected UDID.

FORM: A code-led extension of the established system. Plain server-rendered Phoenix forms retain CSRF handling and work without clipboard JavaScript. Readonly fields support selection/copying; delete uses an explicit confirmation. Long labels wrap, long identifiers scroll inside their fields, and controls retain at least 44px interaction heights.

FINISH: Parent performs controller integration, responsive browser verification and the independent finish review. No physical iOS approval flow has been claimed as tested by this UI implementation.

## Documentation boundary and evidence

The finished controller markup and `assets/css/devices.css` extend Evening watch without changing `DESIGN.md` or `.impeccable/design.json`: the seven workspace colors, flat separators, 5px/6px control radii and cyan focus treatment match the incumbent system. Owner received-state desktop/mobile captures and the 683px guest capture in `.impeccable/review/` show the two-column/stacked form and ordered guest instructions; the owner captures distinguish 7-day link validity from 30-day record retention after creation.

Surface-local values are not promoted to global tokens: 26px desktop headings, 15px reading text, 16px editable/mobile readonly fields and the lighter cyan hover (`#a9e0eb`). The detector's 16px advisory overlaps an existing documented mobile-search adaptation in `DESIGN.md`; legacy shared-navigation styling is also pre-existing and remains outside this extension. No new display role or design-system revision is authorized. These captures establish rendered layout only, not physical iOS profile approval or complete accessibility coverage.
