import assert from "node:assert/strict"
import test from "node:test"
import {selectionCamera, routeCoordinatesToFit} from "../../assets/js/selection_camera.mjs"

const berth = {latitude: 36.417, longitude: -5.158, speed: 0}

test("stationary selection preserves a close harbour zoom without route fitting", () => {
  for (const route of [[], [berth], Array(500).fill(berth), [berth, {...berth, longitude: -5.1579}]]) {
    assert.deepEqual(selectionCamera(route, berth, 18), {
      kind: "point", center: [-5.158, 36.417], zoom: 18,
    })
  }
})

test("a stopped vessel with a real earlier route still fits its route", () => {
  const camera = selectionCamera([{latitude: 36.5, longitude: -5.3}, berth], berth, 18)
  assert.equal(camera.kind, "route")
  assert.equal(camera.coordinates.length, 2)
  // Fitting may zoom out to show the route, but must not force the old 12.5 cap.
  assert.equal(camera.maxZoom, 18)
})

test("a short but meaningful route can retain an already close view", () => {
  const camera = selectionCamera([berth, {...berth, latitude: berth.latitude + 0.001}], berth, 17)
  assert.equal(camera.kind, "route")
  assert.equal(camera.maxZoom, 17)
})

test("returning to the berth does not erase the journey between endpoints", () => {
  const route = [berth, {...berth, latitude: 36.5}, berth]
  assert.equal(selectionCamera(route, berth, 18).kind, "route")
})

test("invalid observations cannot turn a stationary contact into a route", () => {
  const invalid = [{latitude: NaN, longitude: 0}, {latitude: 91, longitude: 0}, {latitude: 0, longitude: Infinity}]
  assert.equal(routeCoordinatesToFit([...invalid, berth]), null)
  assert.equal(selectionCamera(invalid, null, 18), null)
})

test("dateline jitter stays stationary while a dateline route gets local bounds", () => {
  assert.equal(routeCoordinatesToFit([
    {latitude: 10, longitude: 179.99995}, {latitude: 10, longitude: -179.99995},
  ]), null)
  const coordinates = routeCoordinatesToFit([
    {latitude: 10, longitude: 179.9}, {latitude: 10.1, longitude: -179.9},
  ])
  assert.ok(coordinates)
  assert.ok(Math.abs(coordinates[0][0] - coordinates[1][0]) < 1)
})
