defmodule Hrafnsyn.GRPC.TrackingIngressServer do
  @moduledoc false

  use GRPC.Server, service: Hrafnsyn.V1.TrackingIngress.Service

  alias Hrafnsyn.GRPC.Helpers
  alias Hrafnsyn.Ingest

  def stream_observations(requests, stream) do
    requests
    |> Stream.flat_map(&handle_message/1)
    |> GRPC.Stream.from()
    |> GRPC.Stream.run_with(stream)
  end

  defp handle_message(%Hrafnsyn.V1.StreamObservationsRequest{message: {:hello, hello}}) do
    accepted = %Hrafnsyn.V1.StreamAccepted{
      active_source_ids: hello.requested_source_ids,
      server_version: Application.spec(:hrafnsyn, :vsn) |> to_string()
    }

    [%Hrafnsyn.V1.StreamObservationsResponse{message: {:accepted, accepted}}]
  end

  defp handle_message(%Hrafnsyn.V1.StreamObservationsRequest{message: {:heartbeat, _heartbeat}}) do
    []
  end

  defp handle_message(%Hrafnsyn.V1.StreamObservationsRequest{message: {:observation, envelope}}) do
    case ingest_observation(envelope) do
      {:ok, response} -> [response]
      {:error, response} -> [response]
    end
  end

  defp handle_message(_other) do
    [
      %Hrafnsyn.V1.StreamObservationsResponse{
        message:
          {:notice,
           %Hrafnsyn.V1.StreamNotice{
             code: "invalid_message",
             message: "Unsupported ingress message"
           }}
      }
    ]
  end

  defp ingest_observation(%Hrafnsyn.V1.ObservationEnvelope{
         source: source,
         observation: observation
       }) do
    with {:ok, source} <- Helpers.grpc_source(source),
         {:ok, attrs} <- Helpers.observation_attrs(observation),
         {:ok, [track_id | _]} <- Ingest.ingest_batch(source, [attrs]) do
      ack = %Hrafnsyn.V1.ObservationAck{
        source_id: source.id,
        identity: attrs.identity,
        track_id: track_id,
        observed_at: Helpers.timestamp(attrs.observed_at)
      }

      {:ok, %Hrafnsyn.V1.StreamObservationsResponse{message: {:ack, ack}}}
    else
      {:ok, []} ->
        {:error,
         %Hrafnsyn.V1.StreamObservationsResponse{
           message:
             {:notice,
              %Hrafnsyn.V1.StreamNotice{
                code: "ignored_observation",
                message: "Observation was ignored by ingest"
              }}
         }}

      {:error, reason} ->
        {:error,
         %Hrafnsyn.V1.StreamObservationsResponse{
           message:
             {:notice,
              %Hrafnsyn.V1.StreamNotice{
                code: "ingest_failed",
                message: "Observation could not be ingested: #{inspect(reason)}"
              }}
         }}
    end
  end
end
