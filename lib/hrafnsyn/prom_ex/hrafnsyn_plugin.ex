defmodule Hrafnsyn.PromEx.HrafnsynPlugin do
  @moduledoc """
  Hrafnsyn-specific PromEx metrics for collectors and merged track state.
  """

  use PromEx.Plugin

  alias Hrafnsyn.Collectors.Config, as: CollectorConfig
  alias Hrafnsyn.Repo
  alias Hrafnsyn.Tracking
  alias Hrafnsyn.Tracking.TrackPoint
  alias PromEx.MetricTypes.{Event, Polling}

  @impl true
  def event_metrics(_opts) do
    [
      collector_event_metrics(),
      ingest_event_metrics()
    ]
  end

  @impl true
  def polling_metrics(_opts) do
    [
      state_polling_metrics()
    ]
  end

  defp collector_event_metrics do
    Event.build(
      :hrafnsyn_collector_event_metrics,
      [
        counter(
          [:hrafnsyn, :collector, :polls, :total],
          event_name: [:hrafnsyn, :collector, :poll, :stop],
          measurement: :count,
          tags: [:source_id, :vehicle_type, :result]
        ),
        distribution(
          [:hrafnsyn, :collector, :poll, :duration, :seconds],
          event_name: [:hrafnsyn, :collector, :poll, :stop],
          measurement: :duration_seconds,
          tags: [:source_id, :vehicle_type, :result],
          reporter_options: [buckets: [0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10]]
        )
      ]
    )
  end

  defp ingest_event_metrics do
    Event.build(
      :hrafnsyn_ingest_event_metrics,
      [
        counter(
          [:hrafnsyn, :ingest, :observations, :total],
          event_name: [:hrafnsyn, :ingest, :batch],
          measurement: :observations,
          tags: [:source_id, :vehicle_type]
        ),
        counter(
          [:hrafnsyn, :ingest, :tracks, :touched, :total],
          event_name: [:hrafnsyn, :ingest, :batch],
          measurement: :touched_tracks,
          tags: [:source_id, :vehicle_type]
        )
      ]
    )
  end

  defp state_polling_metrics do
    Polling.build(
      :hrafnsyn_state_polling_metrics,
      10_000,
      {__MODULE__, :poll_state_metrics, []},
      [
        last_value(
          [:hrafnsyn, :tracks, :active, :total],
          event_name: [:prom_ex, :plugin, :hrafnsyn, :state],
          measurement: :active_tracks
        ),
        last_value(
          [:hrafnsyn, :tracks, :active, :planes],
          event_name: [:prom_ex, :plugin, :hrafnsyn, :state],
          measurement: :active_planes
        ),
        last_value(
          [:hrafnsyn, :tracks, :active, :vessels],
          event_name: [:prom_ex, :plugin, :hrafnsyn, :state],
          measurement: :active_vessels
        ),
        last_value(
          [:hrafnsyn, :sources, :configured, :total],
          event_name: [:prom_ex, :plugin, :hrafnsyn, :state],
          measurement: :configured_sources
        ),
        last_value(
          [:hrafnsyn, :sources, :enabled, :total],
          event_name: [:prom_ex, :plugin, :hrafnsyn, :state],
          measurement: :enabled_sources
        ),
        last_value(
          [:hrafnsyn, :track_points, :total],
          event_name: [:prom_ex, :plugin, :hrafnsyn, :state],
          measurement: :track_points
        )
      ]
    )
  end

  def poll_state_metrics do
    sources = CollectorConfig.list_sources()

    metrics =
      if Process.whereis(Repo) do
        counts = Tracking.active_counts()

        %{
          active_tracks: counts.total,
          active_planes: counts.planes,
          active_vessels: counts.vessels,
          configured_sources: length(sources),
          enabled_sources: Enum.count(sources, & &1.enabled),
          track_points: Repo.aggregate(TrackPoint, :count, :id)
        }
      else
        zero_state_metrics(sources)
      end

    :telemetry.execute([:prom_ex, :plugin, :hrafnsyn, :state], metrics, %{})
  rescue
    _error ->
      sources = CollectorConfig.list_sources()
      :telemetry.execute([:prom_ex, :plugin, :hrafnsyn, :state], zero_state_metrics(sources), %{})
  end

  defp zero_state_metrics(sources) do
    %{
      active_tracks: 0,
      active_planes: 0,
      active_vessels: 0,
      configured_sources: length(sources),
      enabled_sources: Enum.count(sources, & &1.enabled),
      track_points: 0
    }
  end
end
