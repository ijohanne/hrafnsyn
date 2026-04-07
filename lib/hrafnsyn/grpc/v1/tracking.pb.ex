# credo:disable-for-this-file Credo.Check.Readability.ModuleDoc

defmodule Hrafnsyn.V1.VehicleType do
  use Protobuf, enum: true, syntax: :proto3

  field :VEHICLE_TYPE_UNSPECIFIED, 0
  field :VEHICLE_TYPE_PLANE, 1
  field :VEHICLE_TYPE_VESSEL, 2
end

defmodule Hrafnsyn.V1.SourceDescriptor do
  use Protobuf, syntax: :proto3

  field :id, 1, type: :string
  field :name, 2, type: :string
  field :vehicle_type, 3, type: Hrafnsyn.V1.VehicleType, enum: true, json_name: "vehicleType"
  field :adapter, 4, type: :string
end

defmodule Hrafnsyn.V1.Observation do
  use Protobuf, syntax: :proto3

  field :vehicle_type, 1, type: Hrafnsyn.V1.VehicleType, enum: true, json_name: "vehicleType"
  field :identity, 2, type: :string
  field :display_name, 3, type: :string, json_name: "displayName"
  field :callsign, 4, type: :string
  field :registration, 5, type: :string
  field :country, 6, type: :string
  field :category, 7, type: :string
  field :status, 8, type: :string
  field :destination, 9, type: :string
  field :latitude, 10, type: :double
  field :longitude, 11, type: :double
  field :speed_knots, 12, type: :double, json_name: "speedKnots"
  field :heading_degrees, 13, type: :double, json_name: "headingDegrees"
  field :altitude_feet, 14, type: :int32, json_name: "altitudeFeet"
  field :observed_at, 15, type: Google.Protobuf.Timestamp, json_name: "observedAt"
  field :raw_payload_json, 16, type: :bytes, json_name: "rawPayloadJson"
end

defmodule Hrafnsyn.V1.ObservationEnvelope do
  use Protobuf, syntax: :proto3

  field :source, 1, type: Hrafnsyn.V1.SourceDescriptor
  field :observation, 2, type: Hrafnsyn.V1.Observation
end

defmodule Hrafnsyn.V1.ClientHello do
  use Protobuf, syntax: :proto3

  field :client_name, 1, type: :string, json_name: "clientName"
  field :client_version, 2, type: :string, json_name: "clientVersion"
  field :requested_source_ids, 3, repeated: true, type: :string, json_name: "requestedSourceIds"
end

defmodule Hrafnsyn.V1.Heartbeat do
  use Protobuf, syntax: :proto3

  field :sent_at, 1, type: Google.Protobuf.Timestamp, json_name: "sentAt"
end

defmodule Hrafnsyn.V1.StreamObservationsRequest do
  use Protobuf, syntax: :proto3

  oneof(:message, 0)

  field :hello, 1, type: Hrafnsyn.V1.ClientHello, oneof: 0
  field :observation, 2, type: Hrafnsyn.V1.ObservationEnvelope, oneof: 0
  field :heartbeat, 3, type: Hrafnsyn.V1.Heartbeat, oneof: 0
end

defmodule Hrafnsyn.V1.StreamAccepted do
  use Protobuf, syntax: :proto3

  field :active_source_ids, 1, repeated: true, type: :string, json_name: "activeSourceIds"
  field :server_version, 2, type: :string, json_name: "serverVersion"
end

defmodule Hrafnsyn.V1.ObservationAck do
  use Protobuf, syntax: :proto3

  field :source_id, 1, type: :string, json_name: "sourceId"
  field :identity, 2, type: :string
  field :track_id, 3, type: :string, json_name: "trackId"
  field :observed_at, 4, type: Google.Protobuf.Timestamp, json_name: "observedAt"
end

defmodule Hrafnsyn.V1.StreamNotice do
  use Protobuf, syntax: :proto3

  field :code, 1, type: :string
  field :message, 2, type: :string
end

defmodule Hrafnsyn.V1.StreamObservationsResponse do
  use Protobuf, syntax: :proto3

  oneof(:message, 0)

  field :accepted, 1, type: Hrafnsyn.V1.StreamAccepted, oneof: 0
  field :ack, 2, type: Hrafnsyn.V1.ObservationAck, oneof: 0
  field :notice, 3, type: Hrafnsyn.V1.StreamNotice, oneof: 0
end

defmodule Hrafnsyn.V1.UserProfile do
  use Protobuf, syntax: :proto3

  field :id, 1, type: :string
  field :username, 2, type: :string
  field :email, 3, type: :string
  field :is_admin, 4, type: :bool, json_name: "isAdmin"
end

defmodule Hrafnsyn.V1.SessionInfo do
  use Protobuf, syntax: :proto3

  field :id, 1, type: :string
  field :current, 2, type: :bool
  field :created_at, 3, type: Google.Protobuf.Timestamp, json_name: "createdAt"
  field :last_used_at, 4, type: Google.Protobuf.Timestamp, json_name: "lastUsedAt"
  field :expires_at, 5, type: Google.Protobuf.Timestamp, json_name: "expiresAt"
  field :revoked_at, 6, type: Google.Protobuf.Timestamp, json_name: "revokedAt"
end

defmodule Hrafnsyn.V1.AuthStatus do
  use Protobuf, syntax: :proto3

  field :auth_required, 1, type: :bool, json_name: "authRequired"
  field :authenticated, 2, type: :bool
  field :access_token_ttl_seconds, 3, type: :int32, json_name: "accessTokenTtlSeconds"
  field :refresh_token_ttl_seconds, 4, type: :int32, json_name: "refreshTokenTtlSeconds"
  field :current_user, 5, type: Hrafnsyn.V1.UserProfile, json_name: "currentUser"
end

defmodule Hrafnsyn.V1.LoginRequest do
  use Protobuf, syntax: :proto3

  field :username, 1, type: :string
  field :password, 2, type: :string
end

defmodule Hrafnsyn.V1.RefreshRequest do
  use Protobuf, syntax: :proto3

  field :refresh_token, 1, type: :string, json_name: "refreshToken"
end

defmodule Hrafnsyn.V1.TokenPair do
  use Protobuf, syntax: :proto3

  field :access_token, 1, type: :string, json_name: "accessToken"
  field :refresh_token, 2, type: :string, json_name: "refreshToken"

  field :access_token_expires_at, 3,
    type: Google.Protobuf.Timestamp,
    json_name: "accessTokenExpiresAt"

  field :refresh_token_expires_at, 4,
    type: Google.Protobuf.Timestamp,
    json_name: "refreshTokenExpiresAt"

  field :session, 5, type: Hrafnsyn.V1.SessionInfo
  field :user, 6, type: Hrafnsyn.V1.UserProfile
end

defmodule Hrafnsyn.V1.ListSessionsResponse do
  use Protobuf, syntax: :proto3

  field :sessions, 1, repeated: true, type: Hrafnsyn.V1.SessionInfo
end

defmodule Hrafnsyn.V1.RevokeSessionRequest do
  use Protobuf, syntax: :proto3

  field :session_id, 1, type: :string, json_name: "sessionId"
end

defmodule Hrafnsyn.V1.RevocationResponse do
  use Protobuf, syntax: :proto3

  field :scope, 1, type: :string
  field :session_id, 2, type: :string, json_name: "sessionId"
  field :revoked_at, 3, type: Google.Protobuf.Timestamp, json_name: "revokedAt"
end

defmodule Hrafnsyn.V1.ActiveCounts do
  use Protobuf, syntax: :proto3

  field :total, 1, type: :int32
  field :planes, 2, type: :int32
  field :vessels, 3, type: :int32
end

defmodule Hrafnsyn.V1.SystemInfo do
  use Protobuf, syntax: :proto3

  field :sources, 1, repeated: true, type: Hrafnsyn.V1.SourceDescriptor
  field :counts, 2, type: Hrafnsyn.V1.ActiveCounts
end

defmodule Hrafnsyn.V1.TrackSummary do
  use Protobuf, syntax: :proto3

  field :id, 1, type: :string
  field :vehicle_type, 2, type: Hrafnsyn.V1.VehicleType, enum: true, json_name: "vehicleType"
  field :identity, 3, type: :string
  field :latest_source_id, 4, type: :string, json_name: "latestSourceId"
  field :latest_source_name, 5, type: :string, json_name: "latestSourceName"
  field :display_name, 6, type: :string, json_name: "displayName"
  field :callsign, 7, type: :string
  field :registration, 8, type: :string
  field :country, 9, type: :string
  field :category, 10, type: :string
  field :status, 11, type: :string
  field :destination, 12, type: :string
  field :latitude, 13, type: :double
  field :longitude, 14, type: :double
  field :speed_knots, 15, type: :double, json_name: "speedKnots"
  field :heading_degrees, 16, type: :double, json_name: "headingDegrees"
  field :altitude_feet, 17, type: :int32, json_name: "altitudeFeet"
  field :observed_at, 18, type: Google.Protobuf.Timestamp, json_name: "observedAt"
end

defmodule Hrafnsyn.V1.ListActiveTracksRequest do
  use Protobuf, syntax: :proto3

  field :limit, 1, type: :int32
  field :active_window_minutes, 2, type: :int32, json_name: "activeWindowMinutes"
end

defmodule Hrafnsyn.V1.ListActiveTracksResponse do
  use Protobuf, syntax: :proto3

  field :tracks, 1, repeated: true, type: Hrafnsyn.V1.TrackSummary
  field :counts, 2, type: Hrafnsyn.V1.ActiveCounts
end

defmodule Hrafnsyn.V1.SearchTracksRequest do
  use Protobuf, syntax: :proto3

  field :query, 1, type: :string
  field :limit, 2, type: :int32
  field :active_window_minutes, 3, type: :int32, json_name: "activeWindowMinutes"
end

defmodule Hrafnsyn.V1.SearchTracksResponse do
  use Protobuf, syntax: :proto3

  field :tracks, 1, repeated: true, type: Hrafnsyn.V1.TrackSummary
end

defmodule Hrafnsyn.V1.TrackPoint do
  use Protobuf, syntax: :proto3

  field :id, 1, type: :string
  field :track_id, 2, type: :string, json_name: "trackId"
  field :source_id, 3, type: :string, json_name: "sourceId"
  field :source_name, 4, type: :string, json_name: "sourceName"
  field :vehicle_type, 5, type: Hrafnsyn.V1.VehicleType, enum: true, json_name: "vehicleType"
  field :latitude, 6, type: :double
  field :longitude, 7, type: :double
  field :speed_knots, 8, type: :double, json_name: "speedKnots"
  field :heading_degrees, 9, type: :double, json_name: "headingDegrees"
  field :altitude_feet, 10, type: :int32, json_name: "altitudeFeet"
  field :observed_at, 11, type: Google.Protobuf.Timestamp, json_name: "observedAt"
end

defmodule Hrafnsyn.V1.RouteStats do
  use Protobuf, syntax: :proto3

  field :distance_meters, 1, type: :double, json_name: "distanceMeters"
  field :observed_seconds, 2, type: :int32, json_name: "observedSeconds"
end

defmodule Hrafnsyn.V1.GetTrackRequest do
  use Protobuf, syntax: :proto3

  field :track_id, 1, type: :string, json_name: "trackId"
  field :history_hours, 2, type: :int32, json_name: "historyHours"
  field :log_limit, 3, type: :int32, json_name: "logLimit"
end

defmodule Hrafnsyn.V1.GetTrackResponse do
  use Protobuf, syntax: :proto3

  field :track, 1, type: Hrafnsyn.V1.TrackSummary
  field :route_points, 2, repeated: true, type: Hrafnsyn.V1.TrackPoint, json_name: "routePoints"
  field :route_stats, 3, type: Hrafnsyn.V1.RouteStats, json_name: "routeStats"
  field :log_entries, 4, repeated: true, type: Hrafnsyn.V1.TrackPoint, json_name: "logEntries"
end

defmodule Hrafnsyn.V1.StreamTrackUpdatesRequest do
  use Protobuf, syntax: :proto3

  field :active_window_minutes, 1, type: :int32, json_name: "activeWindowMinutes"
end

defmodule Hrafnsyn.V1.TrackUpdate do
  use Protobuf, syntax: :proto3

  field :track_ids, 1, repeated: true, type: :string, json_name: "trackIds"
  field :counts, 2, type: Hrafnsyn.V1.ActiveCounts
  field :sent_at, 3, type: Google.Protobuf.Timestamp, json_name: "sentAt"
end
