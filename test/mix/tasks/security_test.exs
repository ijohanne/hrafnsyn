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

  test "the fixed source and separate HTTPS review remain valid through the deadline" do
    assert :ok = Security.ensure_reviewed_exceptions!(~D[2026-11-16])
    refute File.read!("osv-scanner.toml") =~ "[[IgnoredVulns]]"
  end

  test "a different Cowlib source cannot reuse the fixed-source classification" do
    lock = Map.update!(Lock.read(), :cowlib, &put_elem(&1, 2, String.duplicate("0", 40)))

    assert_raise Mix.Error, ~r/cowlib must resolve to the reviewed upstream encoder fix/, fn ->
      Security.ensure_reviewed_exceptions!(~D[2026-10-26], lock)
    end
  end

  test "raw catalog classification rejects additional unrelated advisories" do
    finding = %{
      dependency: %{package: "gun", version: "2.7.0"},
      advisory: %{id: "GHSA-w4f7-4cxr-rv3c"}
    }

    assert Security.source_fixed_catalog_only?(
             "MixAudit",
             Jason.encode!(%{vulnerabilities: [finding]})
           )

    unrelated = put_in(finding.advisory.id, "GHSA-unknown-new-risk")

    refute Security.source_fixed_catalog_only?(
             "MixAudit",
             Jason.encode!(%{vulnerabilities: [finding, unrelated]})
           )
  end
end
