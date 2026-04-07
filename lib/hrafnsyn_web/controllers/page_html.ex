defmodule HrafnsynWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use HrafnsynWeb, :html

  embed_templates "page_html/*"

  def service_anchor(service_name) do
    "service-" <> slug(service_name)
  end

  def rpc_anchor(service_name, rpc_name) do
    "rpc-" <> slug(service_name) <> "-" <> slug(rpc_name)
  end

  def schema_anchor(schema_name) do
    "schema-" <> slug(schema_name)
  end

  def rpc_mode(%{client_stream?: true, server_stream?: true}), do: "Bidirectional stream"
  def rpc_mode(%{client_stream?: true}), do: "Client stream"
  def rpc_mode(%{server_stream?: true}), do: "Server stream"
  def rpc_mode(_rpc), do: "Unary"

  def field_mode(%{oneof: oneof}) when is_binary(oneof), do: "oneof " <> oneof
  def field_mode(%{repeated?: true}), do: "repeated"
  def field_mode(_field), do: nil

  def short_type("google.protobuf.Empty"), do: "Empty"
  def short_type(type), do: List.last(String.split(type, "."))

  defp slug(value) do
    value
    |> String.replace(~r/([a-z0-9])([A-Z])/, "\\1-\\2")
    |> String.downcase()
  end
end
