defmodule HrafnsynWeb.PageController do
  use HrafnsynWeb, :controller

  alias Hrafnsyn.GRPC.Contract
  alias HrafnsynWeb.Endpoint

  def home(conn, _params) do
    render(conn, :home)
  end

  def grpc(conn, _params) do
    grpc_uri = grpc_docs_uri(conn)
    grpc_base_url = URI.to_string(grpc_uri)
    grpc_authority = request_authority(grpc_uri)

    render(conn, :grpc,
      page_title: "gRPC API",
      grpc_contract: Contract.document(),
      grpc_summary: Contract.summary(),
      grpc_auth: Contract.auth_guidance(),
      grpc_quickstart_commands: quickstart_commands(grpc_base_url, grpc_authority, grpc_uri.scheme)
    )
  end

  def grpc_proto(conn, _params) do
    send_download(conn, {:binary, Contract.proto_source()},
      filename: Contract.proto_filename(),
      content_type: "text/plain; charset=utf-8"
    )
  end

  defp quickstart_commands(grpc_base_url, grpc_authority, scheme) do
    grpcurl_flags =
      case scheme do
        scheme when scheme in [:http, "http"] -> "-plaintext "
        _other -> ""
      end

    """
    curl -fsSL #{grpc_base_url}/grpc/tracking.proto -o tracking.proto
    grpcurl #{grpcurl_flags}-import-path . -proto tracking.proto \\
      #{grpc_authority} hrafnsyn.v1.TrackingService/GetSystemInfo
    """
  end

  defp grpc_docs_uri(conn) do
    endpoint_uri = configured_endpoint_uri()

    if localhost_host?(endpoint_uri.host) do
      %URI{
        scheme: Atom.to_string(conn.scheme),
        host: conn.host,
        port: optional_port(conn.scheme, conn.port)
      }
    else
      %URI{
        scheme: endpoint_uri.scheme,
        host: endpoint_uri.host,
        port: optional_port(endpoint_uri.scheme, endpoint_uri.port)
      }
    end
  end

  defp configured_endpoint_uri do
    url_config =
      :hrafnsyn
      |> Application.fetch_env!(Endpoint)
      |> Keyword.get(:url, [])

    scheme = Keyword.get(url_config, :scheme, "http")

    %URI{
      scheme: to_string(scheme),
      host: Keyword.get(url_config, :host),
      port: optional_port(scheme, Keyword.get(url_config, :port, default_port(scheme)))
    }
  end

  defp request_authority(%URI{} = uri) do
    case optional_port(uri.scheme, uri.port) do
      nil -> uri.host
      port -> "#{uri.host}:#{port}"
    end
  end

  defp localhost_host?(host), do: host in [nil, "", "localhost", "127.0.0.1"]

  defp optional_port(:http, 80), do: nil
  defp optional_port(:https, 443), do: nil
  defp optional_port("http", 80), do: nil
  defp optional_port("https", 443), do: nil
  defp optional_port(_scheme, port), do: port

  defp default_port(:http), do: 80
  defp default_port(:https), do: 443
  defp default_port("http"), do: 80
  defp default_port("https"), do: 443
  defp default_port(_scheme), do: nil
end
