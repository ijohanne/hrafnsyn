defmodule Hrafnsyn.GRPC.Contract do
  @moduledoc false

  alias Hrafnsyn.Accounts.ApiAuth

  @proto_path Path.expand("../../../proto/hrafnsyn/v1/tracking.proto", __DIR__)
  @external_resource @proto_path

  @proto_source File.read!(@proto_path)

  def document, do: parse_document(@proto_source)

  def summary do
    document = document()

    %{
      service_count: length(document.services),
      rpc_count:
        Enum.reduce(document.services, 0, fn service, count -> count + length(service.rpcs) end),
      message_count: length(document.messages),
      enum_count: length(document.enums)
    }
  end

  def proto_filename, do: Path.basename(@proto_path)
  def proto_source, do: @proto_source

  def auth_guidance do
    if ApiAuth.auth_required?() do
      %{
        mode: "Authenticated deployment",
        headline:
          "Read calls require an access token, and ingestion calls require admin credentials.",
        notes: [
          "Use AuthService.GetAuthStatus, Login, and Refresh to bootstrap access tokens.",
          "TrackingService expects authenticated clients when API auth is enabled.",
          "TrackingIngress is reserved for admin-capable publishers when API auth is enabled."
        ]
      }
    else
      %{
        mode: "Public readonly deployment",
        headline:
          "Read calls can be explored without a token, while AuthService remains available for session-aware clients.",
        notes: [
          "TrackingService can be called anonymously in readonly mode.",
          "TrackingIngress accepts optional auth in readonly mode, so operators can still identify publishers.",
          "AuthService remains the place to inspect auth policy and mint tokens when needed."
        ]
      }
    end
  end

  defp parse_document(source) do
    source
    |> String.split("\n")
    |> parse_lines(%{package: nil, imports: [], enums: [], messages: [], services: []})
    |> finalize_document()
  end

  defp parse_lines([], acc), do: acc

  defp parse_lines([line | rest], acc) do
    trimmed = String.trim(line)

    cond do
      trimmed == "" ->
        parse_lines(rest, acc)

      match = Regex.run(~r/^package\s+([.\w]+);$/, trimmed) ->
        parse_lines(rest, %{acc | package: Enum.at(match, 1)})

      match = Regex.run(~r/^import\s+"([^"]+)";$/, trimmed) ->
        parse_lines(rest, update_in(acc.imports, &(&1 ++ [Enum.at(match, 1)])))

      match = Regex.run(~r/^enum\s+(\w+)\s*\{$/, trimmed) ->
        {enum, remaining} = parse_enum(Enum.at(match, 1), rest, [])
        parse_lines(remaining, update_in(acc.enums, &(&1 ++ [enum])))

      match = Regex.run(~r/^message\s+(\w+)\s*\{$/, trimmed) ->
        {message, remaining} = parse_message(Enum.at(match, 1), rest, [])
        parse_lines(remaining, update_in(acc.messages, &(&1 ++ [message])))

      match = Regex.run(~r/^service\s+(\w+)\s*\{$/, trimmed) ->
        {service, remaining} = parse_service(Enum.at(match, 1), rest, [])
        parse_lines(remaining, update_in(acc.services, &(&1 ++ [service])))

      true ->
        parse_lines(rest, acc)
    end
  end

  defp parse_enum(name, [line | rest], values) do
    trimmed = String.trim(line)

    cond do
      trimmed == "" ->
        parse_enum(name, rest, values)

      trimmed == "}" ->
        {%{name: name, values: Enum.reverse(values)}, rest}

      match = Regex.run(~r/^(\w+)\s*=\s*(\d+);$/, trimmed) ->
        value = %{name: Enum.at(match, 1), number: String.to_integer(Enum.at(match, 2))}
        parse_enum(name, rest, [value | values])

      true ->
        parse_enum(name, rest, values)
    end
  end

  defp parse_message(name, [line | rest], fields) do
    trimmed = String.trim(line)

    cond do
      trimmed == "" ->
        parse_message(name, rest, fields)

      trimmed == "}" ->
        {%{name: name, fields: Enum.reverse(fields)}, rest}

      match = Regex.run(~r/^oneof\s+(\w+)\s*\{$/, trimmed) ->
        {oneof_fields, remaining} = parse_oneof(Enum.at(match, 1), rest, [])
        parse_message(name, remaining, Enum.reverse(oneof_fields) ++ fields)

      field = parse_field(trimmed, nil) ->
        parse_message(name, rest, [field | fields])

      true ->
        parse_message(name, rest, fields)
    end
  end

  defp parse_oneof(oneof_name, [line | rest], fields) do
    trimmed = String.trim(line)

    cond do
      trimmed == "" ->
        parse_oneof(oneof_name, rest, fields)

      trimmed == "}" ->
        {fields, rest}

      field = parse_field(trimmed, oneof_name) ->
        parse_oneof(oneof_name, rest, [field | fields])

      true ->
        parse_oneof(oneof_name, rest, fields)
    end
  end

  defp parse_service(name, [line | rest], rpcs) do
    trimmed = String.trim(line)

    cond do
      trimmed == "" ->
        parse_service(name, rest, rpcs)

      trimmed == "}" ->
        {%{name: name, rpcs: Enum.reverse(rpcs)}, rest}

      match =
          Regex.run(
            ~r/^rpc\s+(\w+)\((stream\s+)?([.\w]+)\)\s+returns\s+\((stream\s+)?([.\w]+)\);$/,
            trimmed
          ) ->
        rpc = %{
          name: Enum.at(match, 1),
          client_stream?: match |> Enum.at(2) |> is_binary(),
          request_type: Enum.at(match, 3),
          server_stream?: match |> Enum.at(4) |> is_binary(),
          response_type: Enum.at(match, 5)
        }

        parse_service(name, rest, [rpc | rpcs])

      true ->
        parse_service(name, rest, rpcs)
    end
  end

  defp parse_field(line, oneof_name) do
    case Regex.run(~r/^(repeated\s+)?([.\w]+)\s+(\w+)\s*=\s*(\d+);$/, line) do
      [_, repeated, type, name, number] ->
        %{
          name: name,
          type: type,
          number: String.to_integer(number),
          repeated?: is_binary(repeated),
          oneof: oneof_name
        }

      _other ->
        nil
    end
  end

  defp finalize_document(document) do
    Map.update!(document, :services, fn services ->
      Enum.map(services, &enrich_service/1)
    end)
  end

  defp enrich_service(service) do
    service
    |> Map.put(:description, service_description(service.name))
    |> Map.update!(:rpcs, fn rpcs ->
      Enum.map(rpcs, &enrich_rpc(service.name, &1))
    end)
  end

  defp enrich_rpc(service_name, rpc) do
    Map.put(rpc, :description, rpc_description(service_name, rpc.name))
  end

  defp service_description("TrackingIngress"),
    do: "Bidirectional ingestion for collectors and external publishers."

  defp service_description("TrackingService"),
    do: "Query live state, track history, and server-driven update streams."

  defp service_description("AuthService"),
    do: "Inspect auth requirements, mint tokens, and manage client sessions."

  defp service_description(_service_name), do: "Published gRPC service."

  defp rpc_description("TrackingIngress", "StreamObservations"),
    do:
      "Send a hello, observations, and heartbeats while receiving accepts, acknowledgements, and notices."

  defp rpc_description("TrackingService", "GetSystemInfo"),
    do: "Return configured sources plus the current aircraft and vessel counts."

  defp rpc_description("TrackingService", "ListActiveTracks"),
    do: "List active tracks inside the requested activity window."

  defp rpc_description("TrackingService", "SearchTracks"),
    do: "Search active tracks by callsign, registration, identity, and related labels."

  defp rpc_description("TrackingService", "GetTrack"),
    do: "Fetch one track with route history, route stats, and recent log entries."

  defp rpc_description("TrackingService", "StreamTrackUpdates"),
    do: "Subscribe to server-sent updates for changed track ids and active counts."

  defp rpc_description("AuthService", "GetAuthStatus"),
    do: "Report whether auth is required and which user, if any, is already authenticated."

  defp rpc_description("AuthService", "Login"),
    do: "Exchange a username and password for an access token, refresh token, and session record."

  defp rpc_description("AuthService", "Refresh"),
    do: "Rotate credentials with a refresh token and receive a fresh token pair."

  defp rpc_description("AuthService", "ListSessions"),
    do: "List the sessions that belong to the authenticated user."

  defp rpc_description("AuthService", "RevokeSession"),
    do: "Revoke one session and return the revocation timestamp."

  defp rpc_description("AuthService", "RevokeAllSessions"),
    do: "Revoke every session in scope."

  defp rpc_description(_service_name, _rpc_name), do: "Published gRPC method."
end
