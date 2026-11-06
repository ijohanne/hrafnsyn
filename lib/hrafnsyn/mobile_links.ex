defmodule Hrafnsyn.MobileLinks do
  @moduledoc "Public app association and credential-free links to shared tracks."

  @ranges ~w(1 6 24 72)

  def association do
    ids = Application.get_env(:hrafnsyn, :ios_app_ids, [])

    details =
      if ids == [] do
        []
      else
        [
          %{
            "appIDs" => ids,
            "components" => [
              %{"#" => "no_universal_links", "exclude" => true},
              %{"/" => "/", "?" => %{"vehicle" => "plane", "identity" => "?*"}},
              %{"/" => "/", "?" => %{"vehicle" => "vessel", "identity" => "?*"}}
            ]
          }
        ]
      end

    %{"applinks" => %{"details" => details}}
  end

  def open_url(vehicle, identity, range)
      when vehicle in ["plane", "vessel", :plane, :vessel] and is_binary(identity) and
             byte_size(identity) in 1..256 do
    hours = to_string(range)

    if hours in @ranges and String.valid?(identity) and String.trim(identity) != "" and
         not Regex.match?(~r/\p{Cc}/u, identity) do
      query = URI.encode_query(%{vehicle: vehicle, identity: identity, range: hours})
      web_url = HrafnsynWeb.Endpoint.url() <> "/?" <> query
      "hrafnsyn://open?" <> URI.encode_query(%{url: web_url})
    end
  end

  def open_url(_vehicle, _identity, _range), do: nil

  def open_return_path(path) when is_binary(path) and byte_size(path) <= 4_096 do
    case URI.parse(path) do
      %URI{scheme: nil, host: nil, path: "/", fragment: nil, query: query}
      when is_binary(query) ->
        open_query(query)

      _ ->
        nil
    end
  end

  def open_return_path(_path), do: nil

  defp open_query(query) do
    pairs = Enum.to_list(URI.query_decoder(query))
    params = Map.new(pairs)

    if length(pairs) == map_size(params) do
      open_url(params["vehicle"], params["identity"], params["range"] || "6")
    end
  rescue
    ArgumentError -> nil
  end
end
