# Stationary selection regression review

Scope: hrafnsyn-bxh, native iOS and web selection-camera changes; functional source/test review, no visual redesign review.

Result: no unresolved material findings in the reviewed changes.

- Resolved finding: native pending route fitting previously depended on a false-to-true user-positioned flag transition. The final continuous map-camera callback compares actual rect changes while user-positioned, canceling pending work even when the user had already panned before selecting. The focused regression test covers unchanged annotation callbacks, subsequent pan, delayed eligibility, zoom and programmatic changes.
- Native stationary, repeated and jitter-only histories no longer trigger the 2 km fit. Marker selection preserves the camera; list selections reveal obscured/offscreen positions while retaining rect dimensions. Fit actions use the same useful-route predicate.
- Both platforms measure geographic route extent rather than speed or cumulative jitter distance. Full-history bounds retain out-and-back journeys; dateline wrapping and invalid-coordinate filtering are present. Web tests explicitly cover those cases, and the production map hook imports and calls the tested helper.
- Native short-route tests enforce removal of the 2 km minimum. Web route fitting retains the current zoom as its cap instead of forcing 12.5.

Limitations: this reviewer did not run builds, tests, CUA or hardware checks. Final test results and manual simulator/browser behavior remain the parent task's validation responsibility. The cancellation test exercises the production policy and event eligibility, not an automated MapKit gesture.
