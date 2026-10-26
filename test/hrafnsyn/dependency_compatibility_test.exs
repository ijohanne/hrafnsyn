defmodule Hrafnsyn.DependencyCompatibilityTest do
  use ExUnit.Case, async: true

  alias GRPC.Google.RPC
  alias PromEx.Storage.Peep

  defmodule BodyReader do
    @behaviour Plug

    def init(opts), do: opts

    def call(conn, _opts) do
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      Plug.Conn.send_resp(conn, 200, body)
    end
  end

  test "malformed crypto input cannot expose the secret in exception arguments" do
    secret = "dependency-regression-secret"

    assert {:error, :invalid} = Plug.Crypto.verify(secret, "salt", ["invalid-token"])

    try do
      Plug.Crypto.secure_compare(secret, nil)
      flunk("expected invalid comparison to raise")
    rescue
      error in ArgumentError ->
        refute Exception.format(:error, error, __STACKTRACE__) =~ secret
    end
  end

  test "Bandit rejects bare newlines in HTTP chunk extensions" do
    server = start_supervised!({Bandit, plug: BodyReader, ip: {127, 0, 0, 1}, port: 0})
    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
    {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false], 5_000)
    on_exit(fn -> :gen_tcp.close(socket) end)

    :ok =
      :gen_tcp.send(socket, [
        "POST / HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: chunked\r\n",
        "Connection: close\r\n\r\n1;extension=\"bare\nnewline\"\r\na\r\n0\r\n\r\n"
      ])

    assert {:ok, response} = :gen_tcp.recv(socket, 0, 5_000)
    assert response =~ "HTTP/1.1 400"
  end

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

  test "fixed Cowlib rejects every non-VCHAR byte before transport validation" do
    for byte <- Enum.to_list(0..31) ++ Enum.to_list(127..255) do
      assert_raise FunctionClauseError, fn ->
        :cow_http_struct_hd.item({:item, {:string, <<"value", byte, "injected">>}, []})
      end
    end

    string = :erlang.list_to_binary(Enum.to_list(32..126))
    item = {:item, {:string, string}, []}
    encoded = item |> :cow_http_struct_hd.item() |> IO.iodata_to_binary()
    assert :cow_http_struct_hd.parse_item(encoded) == item
  end

  test "JOSE uses native crypto without enabling variable-time fallback" do
    refute :jose.crypto_fallback()
    key = :crypto.strong_rand_bytes(32)
    signer = Joken.Signer.create("HS256", key)
    assert {:ok, token, _claims} = Joken.encode_and_sign(%{"sub" => "security-check"}, signer)
    assert {:ok, %{"sub" => "security-check"}} = Joken.verify(token, signer)
    assert {:error, _reason} = Joken.verify(token <> "tampered", signer)
  end
end
