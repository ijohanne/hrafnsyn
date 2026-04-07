defmodule Hrafnsyn.Aircraft.StaticDB do
  @moduledoc false

  use GenServer

  require Logger

  @table __MODULE__
  @default_record %{
    registration: nil,
    aircraft_type: nil,
    type_description: nil,
    wake_turbulence_category: nil
  }

  @type record :: %{
          registration: String.t() | nil,
          aircraft_type: String.t() | nil,
          type_description: String.t() | nil,
          wake_turbulence_category: String.t() | nil
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec lookup(String.t() | nil) :: record()
  def lookup(identity) when is_binary(identity) do
    case :ets.whereis(@table) do
      :undefined ->
        @default_record

      _table ->
        case :ets.lookup(@table, normalize_identity(identity)) do
          [{_identity, record}] -> record
          [] -> @default_record
        end
    end
  end

  def lookup(_identity), do: @default_record

  @spec reload() :: :ok | {:error, term()}
  def reload do
    GenServer.call(__MODULE__, :reload, 30_000)
  end

  @impl true
  def init(_opts) do
    ensure_table!()

    case load_from_config() do
      {:ok, _count} = ok ->
        {:ok, %{status: ok}}

      {:error, reason} = error ->
        Logger.warning("Aircraft static DB disabled: #{inspect(reason)}")
        {:ok, %{status: error}}
    end
  end

  @impl true
  def handle_call(:reload, _from, state) do
    case load_from_config() do
      {:ok, _count} = ok -> {:reply, :ok, %{state | status: ok}}
      {:error, reason} = error -> {:reply, {:error, reason}, %{state | status: error}}
    end
  end

  defp ensure_table! do
    case :ets.whereis(@table) do
      :undefined -> :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
      _table -> :ok
    end
  end

  defp load_from_config do
    clear_table()

    case configured_path() do
      nil ->
        Logger.info("Aircraft static DB disabled: no path configured")
        {:ok, 0}

      path ->
        load_file(path)
    end
  end

  defp configured_path do
    :hrafnsyn
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:path)
    |> normalize_path()
  end

  defp normalize_path(nil), do: nil

  defp normalize_path(path) when is_binary(path) do
    case String.trim(path) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp load_file(path) do
    if File.exists?(path) do
      path
      |> File.stream!([], :line)
      |> Enum.reduce_while({:ok, 0}, &count_records(&1, &2, path))
      |> case do
        {:ok, count} ->
          Logger.info("Loaded #{count} aircraft records from static DB")
          {:ok, count}

        {:error, reason} ->
          Logger.warning("Failed to load aircraft static DB: #{inspect(reason)}")
          clear_table()
          {:error, reason}
      end
    else
      {:error, :enoent}
    end
  end

  defp load_line(line) do
    trimmed = String.trim(line)

    case trimmed do
      "" ->
        :skip

      _other ->
        trimmed
        |> Jason.decode()
        |> case do
          {:ok, decoded} -> normalize_record(decoded)
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp count_records(line, {:ok, count}, path) do
    case load_line(line) do
      :skip ->
        {:cont, {:ok, count}}

      {:ok, record} ->
        :ets.insert(@table, record)
        {:cont, {:ok, count + 1}}

      {:error, reason} ->
        {:halt, {:error, {path, reason}}}
    end
  end

  defp normalize_record(%{"identity" => identity} = decoded) when is_binary(identity) do
    record =
      @default_record
      |> Map.merge(%{
        registration: normalize_value(decoded["registration"]),
        aircraft_type: normalize_value(decoded["aircraft_type"]),
        type_description: normalize_value(decoded["type_description"]),
        wake_turbulence_category: normalize_value(decoded["wake_turbulence_category"])
      })

    {:ok, {normalize_identity(identity), record}}
  end

  defp normalize_record(_decoded), do: {:error, :invalid_record}

  defp normalize_identity(identity) do
    identity
    |> String.trim()
    |> String.upcase()
  end

  defp normalize_value(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_value(_value), do: nil

  defp clear_table do
    case :ets.whereis(@table) do
      :undefined -> :ok
      _table -> :ets.delete_all_objects(@table)
    end
  end
end
