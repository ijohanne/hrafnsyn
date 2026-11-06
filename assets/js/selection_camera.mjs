const minimumRouteExtentMeters = 50
const earthRadiusMeters = 6_371_000
const radians = degrees => degrees * Math.PI / 180

const validPosition = point => point &&
  Number.isFinite(point.latitude) && Math.abs(point.latitude) <= 90 &&
  Number.isFinite(point.longitude) && Math.abs(point.longitude) <= 180

// Repeated observations and GPS drift at a berth are not a route to zoom out for.
// Unwrap the shortest longitude arc so nearby points across ±180° stay nearby.
export function routeCoordinatesToFit(route) {
  const points = route.filter(validPosition)
  if (points.length < 2) return null

  const longitudes = points.map(point => point.longitude).sort((a, b) => a - b)
  let start = longitudes[0]
  let largestGap = longitudes[0] + 360 - longitudes.at(-1)
  for (let index = 1; index < longitudes.length; index++) {
    const gap = longitudes[index] - longitudes[index - 1]
    if (gap > largestGap) {
      largestGap = gap
      start = longitudes[index]
    }
  }

  const coordinates = points.map(point => [
    point.longitude < start ? point.longitude + 360 : point.longitude,
    point.latitude,
  ])
  let minLongitude = Infinity, maxLongitude = -Infinity
  let minLatitude = Infinity, maxLatitude = -Infinity
  for (const [longitude, latitude] of coordinates) {
    minLongitude = Math.min(minLongitude, longitude)
    maxLongitude = Math.max(maxLongitude, longitude)
    minLatitude = Math.min(minLatitude, latitude)
    maxLatitude = Math.max(maxLatitude, latitude)
  }
  const latitudeDelta = radians(maxLatitude - minLatitude)
  const longitudeDelta = radians(maxLongitude - minLongitude)
  const haversine = Math.sin(latitudeDelta / 2) ** 2 +
    Math.cos(radians(minLatitude)) * Math.cos(radians(maxLatitude)) * Math.sin(longitudeDelta / 2) ** 2
  const extent = 2 * earthRadiusMeters * Math.asin(Math.sqrt(Math.min(1, haversine)))

  return extent >= minimumRouteExtentMeters ? coordinates : null
}

export function selectionCamera(route, selectedTrack, currentZoom) {
  const coordinates = routeCoordinatesToFit(route)
  if (coordinates) {
    return {kind: "route", coordinates, maxZoom: Math.max(currentZoom, 12.5)}
  }
  if (!validPosition(selectedTrack)) return null
  return {
    kind: "point",
    center: [selectedTrack.longitude, selectedTrack.latitude],
    zoom: Math.max(currentZoom, 9.8),
  }
}
