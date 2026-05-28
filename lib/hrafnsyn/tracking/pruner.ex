defmodule Hrafnsyn.Tracking.Pruner do
  @moduledoc """
  Periodically compacts old track point history.

  Full-resolution points are retained inside the configured window. Older
  history is reduced to one point per track: the most recent point before the
  cutoff, which preserves the last-seen historical location.
  """

  use GenServer

  require Logger

  alias Hrafnsyn.Tracking

  @default_retention_days 7
  @default_initial_delay_ms :timer.minutes(1)
  @default_interval_ms :timer.hours(6)
  @seconds_per_day 86_400

  @type state :: %{
          retention_days: pos_integer(),
          interval_ms: pos_integer()
        }

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    config = config(opts)
    schedule_prune(config.initial_delay_ms)

    {:ok,
     %{
       retention_days: config.retention_days,
       interval_ms: config.interval_ms
     }}
  end

  @impl true
  def handle_info(:prune, state) do
    cutoff = retention_cutoff(state.retention_days)

    case Tracking.prune_stale_points(cutoff) do
      {:ok, deleted_count} ->
        :telemetry.execute(
          [:hrafnsyn, :track_points, :prune],
          %{deleted_points: deleted_count},
          %{retention_days: state.retention_days}
        )

        if deleted_count > 0 do
          Logger.info("Pruned #{deleted_count} stale track points")
        end

      {:error, reason} ->
        Logger.error("Failed to prune stale track points: #{inspect(reason)}")
    end

    schedule_prune(state.interval_ms)
    {:noreply, state}
  end

  defp retention_cutoff(retention_days) do
    DateTime.utc_now(:second)
    |> DateTime.add(-(retention_days * @seconds_per_day), :second)
  end

  defp schedule_prune(delay_ms), do: Process.send_after(self(), :prune, delay_ms)

  defp config(opts) do
    app_config = Application.get_env(:hrafnsyn, __MODULE__, [])

    %{
      retention_days:
        positive_integer(opts, app_config, :retention_days, @default_retention_days),
      initial_delay_ms:
        positive_integer(opts, app_config, :initial_delay_ms, @default_initial_delay_ms),
      interval_ms: positive_integer(opts, app_config, :interval_ms, @default_interval_ms)
    }
  end

  defp positive_integer(opts, app_config, key, default) do
    opts
    |> Keyword.get(key, Keyword.get(app_config, key, default))
    |> ensure_positive_integer!(key)
  end

  defp ensure_positive_integer!(value, _key) when is_integer(value) and value > 0, do: value

  defp ensure_positive_integer!(value, key) when is_binary(value) do
    value
    |> String.to_integer()
    |> ensure_positive_integer!(key)
  end

  defp ensure_positive_integer!(value, key) do
    raise ArgumentError,
          "#{inspect(key)} must be a positive integer, got: #{inspect(value)}"
  end
end
