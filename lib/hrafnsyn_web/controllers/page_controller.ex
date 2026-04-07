defmodule HrafnsynWeb.PageController do
  use HrafnsynWeb, :controller

  alias Hrafnsyn.GRPC.Contract

  def home(conn, _params) do
    render(conn, :home)
  end

  def grpc(conn, _params) do
    render(conn, :grpc,
      page_title: "gRPC API",
      grpc_contract: Contract.document(),
      grpc_summary: Contract.summary(),
      grpc_auth: Contract.auth_guidance()
    )
  end

  def grpc_proto(conn, _params) do
    send_download(conn, {:binary, Contract.proto_source()},
      filename: Contract.proto_filename(),
      content_type: "text/plain; charset=utf-8"
    )
  end
end
