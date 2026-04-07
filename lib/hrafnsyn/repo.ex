defmodule Hrafnsyn.Repo do
  use Ecto.Repo,
    otp_app: :hrafnsyn,
    adapter: Ecto.Adapters.Postgres
end
