defmodule Hrafnsyn.GRPC.Endpoint do
  @moduledoc false

  use GRPC.Endpoint

  intercept(GRPC.Server.Interceptors.Logger, level: :info)
  intercept Hrafnsyn.GRPC.AuthInterceptor

  run(Hrafnsyn.GRPC.AuthServer)
  run(Hrafnsyn.GRPC.TrackingServer)
  run(Hrafnsyn.GRPC.TrackingIngressServer)
end
