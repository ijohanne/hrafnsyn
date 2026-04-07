defmodule Hrafnsyn.Ingest do
  @moduledoc """
  Stable ingestion boundary shared by today's HTTP collectors and future transports.

  Long-lived source workers, replay imports, and a future bidirectional gRPC stream
  should all hand normalized observations to this module instead of reaching into
  persistence directly.
  """

  alias Hrafnsyn.Ingest.Observation
  alias Hrafnsyn.Tracking

  @spec ingest_batch(struct(), [map() | Observation.t()]) :: {:ok, [Ecto.UUID.t()]}
  def ingest_batch(source, observations) do
    observations
    |> Observation.normalize_many()
    |> then(&Tracking.ingest_batch(source, &1))
  end
end
