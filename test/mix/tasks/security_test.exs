defmodule Mix.Tasks.SecurityTest do
  use ExUnit.Case, async: true

  alias Mix.Dep.Lock
  alias Mix.Tasks.Security

  test "reviewed exceptions expire on their deadline" do
    assert_raise Mix.Error, ~r/security exceptions expired on 2026-11-16/, fn ->
      Security.ensure_reviewed_exceptions!(~D[2026-11-17])
    end
  end

  test "a changed Gun version requires a new advisory review" do
    lock = Map.update!(Lock.read(), :gun, &put_elem(&1, 2, "2.7.1"))

    assert_raise Mix.Error, ~r/gun changed; review advisory exceptions/, fn ->
      Security.ensure_reviewed_exceptions!(~D[2026-10-16], lock)
    end
  end

  test "the reviewed lock and narrowed exception remain valid through the deadline" do
    assert :ok = Security.ensure_reviewed_exceptions!(~D[2026-11-16])
    refute File.read!("osv-scanner.toml") =~ "EEF-CVE-2026-43969"
  end
end
