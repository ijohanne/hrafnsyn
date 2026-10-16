defmodule Hrafnsyn.DependencyCompatibilityTest do
  use ExUnit.Case, async: true

  alias GRPC.Google.RPC
  alias PromEx.Storage.Peep

  test "PromEx records and exports metrics through Peep 5" do
    name = __MODULE__.Metrics
    metric = Telemetry.Metrics.counter("hrafnsyn.dependency.compatibility.count")
    start_supervised!(Peep.child_spec(name, [metric]))

    :telemetry.execute([:hrafnsyn, :dependency, :compatibility], %{count: 1}, %{})

    assert name |> Peep.scrape() |> IO.iodata_to_binary() =~
             "hrafnsyn_dependency_compatibility_count 1"
  end

  test "gRPC round trips Google API status details" do
    status = %Google.Rpc.Status{
      code: GRPC.Status.invalid_argument(),
      message: "invalid track",
      details: [
        %Google.Protobuf.Any{type_url: "type.googleapis.com/test.Detail", value: "detail"}
      ]
    }

    encoded = RPC.encode_status(status)
    assert {:ok, ^status} = RPC.decode_status(encoded)
  end

  test "Cowlib rejects injected cookies and Gun rejects CRLF headers" do
    assert_raise ArgumentError, fn ->
      :cow_cookie.cookie([{"session", "value; admin=1"}])
    end

    assert_raise ErlangError, fn ->
      :gun.get(self(), "/", [{"x-review", "value\r\ninjected: true"}])
    end
  end
end
