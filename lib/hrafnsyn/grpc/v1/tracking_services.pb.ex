# credo:disable-for-this-file Credo.Check.Readability.ModuleDoc

defmodule Hrafnsyn.V1.TrackingIngress.Service do
  use GRPC.Service, name: "hrafnsyn.v1.TrackingIngress"

  rpc(
    :StreamObservations,
    stream(Hrafnsyn.V1.StreamObservationsRequest),
    stream(Hrafnsyn.V1.StreamObservationsResponse)
  )
end

defmodule Hrafnsyn.V1.TrackingIngress.Stub do
  use GRPC.Stub, service: Hrafnsyn.V1.TrackingIngress.Service
end

defmodule Hrafnsyn.V1.TrackingService.Service do
  use GRPC.Service, name: "hrafnsyn.v1.TrackingService"

  rpc(:GetSystemInfo, Google.Protobuf.Empty, Hrafnsyn.V1.SystemInfo)

  rpc(
    :ListActiveTracks,
    Hrafnsyn.V1.ListActiveTracksRequest,
    Hrafnsyn.V1.ListActiveTracksResponse
  )

  rpc(:SearchTracks, Hrafnsyn.V1.SearchTracksRequest, Hrafnsyn.V1.SearchTracksResponse)
  rpc(:GetTrack, Hrafnsyn.V1.GetTrackRequest, Hrafnsyn.V1.GetTrackResponse)
  rpc(:StreamTrackUpdates, Hrafnsyn.V1.StreamTrackUpdatesRequest, stream(Hrafnsyn.V1.TrackUpdate))
end

defmodule Hrafnsyn.V1.TrackingService.Stub do
  use GRPC.Stub, service: Hrafnsyn.V1.TrackingService.Service
end

defmodule Hrafnsyn.V1.AuthService.Service do
  use GRPC.Service, name: "hrafnsyn.v1.AuthService"

  rpc(:GetAuthStatus, Google.Protobuf.Empty, Hrafnsyn.V1.AuthStatus)
  rpc(:Login, Hrafnsyn.V1.LoginRequest, Hrafnsyn.V1.TokenPair)
  rpc(:Refresh, Hrafnsyn.V1.RefreshRequest, Hrafnsyn.V1.TokenPair)
  rpc(:ListSessions, Google.Protobuf.Empty, Hrafnsyn.V1.ListSessionsResponse)
  rpc(:RevokeSession, Hrafnsyn.V1.RevokeSessionRequest, Hrafnsyn.V1.RevocationResponse)
  rpc(:RevokeAllSessions, Google.Protobuf.Empty, Hrafnsyn.V1.RevocationResponse)
end

defmodule Hrafnsyn.V1.AuthService.Stub do
  use GRPC.Stub, service: Hrafnsyn.V1.AuthService.Service
end
