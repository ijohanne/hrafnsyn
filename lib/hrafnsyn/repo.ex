defmodule Hrafnsyn.Repo do
  alias Ecto.Adapters.Postgres

  Postgrex.Types.define(
    __MODULE__.PostgresTypes,
    [Geo.PostGIS.Extension] ++ Postgres.extensions(),
    json: Jason
  )

  use Ecto.Repo,
    otp_app: :hrafnsyn,
    adapter: Postgres

  @impl true
  def init(_type, config) do
    {:ok, Keyword.put_new(config, :types, __MODULE__.PostgresTypes)}
  end
end
