defmodule HrafnsynWeb.PageController do
  use HrafnsynWeb, :controller

  alias Hrafnsyn.GRPC.Contract

  def home(conn, _params) do
    render(conn, :home)
  end

  def grpc(conn, _params) do
    grpc_base_url = request_base_url(conn)
    grpc_authority = request_authority(conn)

    render(conn, :grpc,
      page_title: "gRPC API",
      grpc_contract: Contract.document(),
      grpc_summary: Contract.summary(),
      grpc_auth: Contract.auth_guidance(),
      grpc_quickstart_commands: quickstart_commands(grpc_base_url, grpc_authority, conn.scheme)
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
        :http -> "-plaintext "
        _other -> ""
      end

    """
    curl -fsSL #{grpc_base_url}/grpc/tracking.proto -o tracking.proto
    grpcurl #{grpcurl_flags}-import-path . -proto tracking.proto \\
      #{grpc_authority} hrafnsyn.v1.TrackingService/GetSystemInfo
    """
  end

  defp request_base_url(conn) do
    URI.to_string(%URI{
      scheme: Atom.to_string(conn.scheme),
      host: conn.host,
      port: optional_port(conn.scheme, conn.port)
    })
  end

  defp request_authority(conn) do
    case optional_port(conn.scheme, conn.port) do
      nil -> conn.host
      port -> "#{conn.host}:#{port}"
    end
  end

  defp optional_port(:http, 80), do: nil
  defp optional_port(:https, 443), do: nil
  defp optional_port(_scheme, port), do: port
end
