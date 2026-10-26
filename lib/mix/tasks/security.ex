defmodule Mix.Tasks.Security do
  use Mix.Task

  alias Mix.Dep.Lock

  @shortdoc "Runs the local dependency and Phoenix security checks"
  @moduledoc """
  Runs the blocking local scanners and writes their reports to `tmp/security/`.

  Raw scanner reports are retained. The known Gun catalog alias is classified
  as source-fixed only after validating the pinned Cowlib source and encoder.
  The separate HTTPS review still expires; see `docs/dependency-security.md`.
  """

  @requirements ["loadpaths"]
  @expires_on ~D[2026-11-16]
  @owner "Ian Johannesen"
  @tracking_issue "hrafnsyn-fhv"
  @reviewed_ids []
  @reviewed_versions %{cowboy: "2.20.0", gun: "2.7.0"}
  @fixed_cowlib_repo "https://github.com/ninenines/cowlib.git"
  @fixed_cowlib_ref "4401b858f2229abb3ea115c60924f6c77e5f8aa3"
  @fixed_encoder_sha256 "69a5d5b3c41a562489532bfb7385801fcefa6e47cbc0a6a9675cdc4105686ab7"
  @catalog_aliases ~w(EEF-CVE-2026-43966 GHSA-w4f7-4cxr-rv3c CVE-2026-43966)
  @sobelow_skip "Config.HTTPS: HTTPS Not Enabled,config/prod.exs:0,2B5C077\n"

  @impl Mix.Task
  def run(_args) do
    ensure_reviewed_exceptions!()
    ensure_reviewed_sobelow_skip!()

    report_dir = Path.expand("tmp/security")
    File.mkdir_p!(report_dir)

    checks = [
      {"Hex retirement", "mix", ["hex.audit"], "hex-audit.log"},
      {"MixAudit", "mix", ["deps.audit", "--format", "json"], "mix-audit.json"},
      {"OSV-Scanner", "osv-scanner",
       ["scan", "source", "--lockfile=mix.lock", "--format=json", "--config", "osv-scanner.toml"],
       "osv-scanner.json"},
      {"Sobelow", "mix",
       [
         "sobelow",
         "--private",
         "--format",
         "json",
         "--threshold",
         "low",
         "--exit",
         "medium",
         "--skip"
       ], "sobelow.json"}
    ]

    failures = Enum.flat_map(checks, &run_check(&1, report_dir))

    if failures != [] do
      Mix.raise("security checks failed: #{Enum.join(failures, ", ")}")
    end
  end

  defp run_check({name, command, args, report_name}, report_dir) do
    report = Path.join(report_dir, report_name)

    case System.find_executable(command) do
      nil ->
        File.write!(report, "#{command} executable not found; enter the Nix developer shell\n")
        Mix.shell().error("#{name}: missing scanner (#{Path.relative_to_cwd(report)})")
        [name]

      executable ->
        execute_check(name, executable, args, report)
    end
  end

  defp execute_check(name, executable, args, report) do
    {output, status} =
      System.cmd(executable, args, env: [{"MIX_ENV", Atom.to_string(Mix.env())}])

    File.write!(report, output)

    cond do
      status == 0 ->
        Mix.shell().info("#{name}: passed (#{Path.relative_to_cwd(report)})")
        []

      status == 1 and source_fixed_catalog_only?(name, output) ->
        Mix.shell().info(
          "#{name}: source-fixed Cowlib alias retained in raw report " <>
            "(#{Path.relative_to_cwd(report)})"
        )

        []

      true ->
        Mix.shell().error("#{name}: exit #{status} (#{Path.relative_to_cwd(report)})")
        [name]
    end
  end

  @doc false
  def source_fixed_catalog_only?(name, output) do
    case Jason.decode(output) do
      {:ok, %{"vulnerabilities" => vulnerabilities}} when name == "MixAudit" ->
        vulnerabilities != [] and
          Enum.all?(vulnerabilities, fn finding ->
            finding["dependency"]["package"] == "gun" and
              finding["dependency"]["version"] == "2.7.0" and
              finding["advisory"]["id"] == "GHSA-w4f7-4cxr-rv3c"
          end)

      {:ok, %{"results" => results}} when name == "OSV-Scanner" ->
        packages = Enum.flat_map(results, &Map.get(&1, "packages", []))
        findings = Enum.filter(packages, &(Map.get(&1, "vulnerabilities", []) != []))

        findings != [] and
          Enum.all?(findings, fn finding ->
            finding["package"]["name"] in ~w(gun cowlib) and
              Enum.all?(finding["vulnerabilities"], &(&1["id"] in @catalog_aliases))
          end)

      _ ->
        false
    end
  end

  @doc false
  def ensure_reviewed_exceptions!(today \\ Date.utc_today(), lock \\ Lock.read()) do
    if Date.compare(today, @expires_on) == :gt do
      Mix.raise("security exceptions expired on #{@expires_on}; review #{@tracking_issue}")
    end

    Enum.each(@reviewed_versions, fn {name, version} ->
      case lock[name] do
        {:hex, ^name, ^version, _, _, _, _, _} -> :ok
        _ -> Mix.raise("#{name} changed; review advisory exceptions in #{@tracking_issue}")
      end
    end)

    ensure_fixed_cowlib!(lock)
    ensure_osv_config!()
  end

  defp ensure_fixed_cowlib!(lock) do
    case lock[:cowlib] do
      {:git, @fixed_cowlib_repo, @fixed_cowlib_ref, _opts} -> :ok
      _ -> Mix.raise("cowlib must resolve to the reviewed upstream encoder fix")
    end

    source_hash =
      :sha256
      |> :crypto.hash(File.read!("deps/cowlib/src/cow_http_struct_hd.erl"))
      |> Base.encode16(case: :lower)

    if source_hash != @fixed_encoder_sha256 do
      Mix.raise("cowlib encoder source differs from the reviewed upstream fix")
    end

    Enum.each(Enum.to_list(0..31) ++ Enum.to_list(127..255), fn byte ->
      rejects? =
        try do
          :cow_http_struct_hd.item({:item, {:string, <<"check", byte, "header">>}, []})
          false
        rescue
          FunctionClauseError -> true
        end

      unless rejects?, do: Mix.raise("cowlib encoder accepts non-VCHAR byte #{byte}")
    end)
  end

  defp ensure_osv_config! do
    contents = File.read!("osv-scanner.toml")

    entries =
      Regex.scan(~r/\[\[IgnoredVulns\]\](.*?)(?=\[\[IgnoredVulns\]\]|\z)/ms, contents,
        capture: :all_but_first
      )
      |> Enum.map(fn [entry] ->
        id = capture!(entry, ~r/^id\s*=\s*"([^"]+)"/m)
        expiry = capture!(entry, ~r/^ignoreUntil\s*=\s*(\d{4}-\d{2}-\d{2})/m)
        reason = capture!(entry, ~r/^reason\s*=\s*"([^"]+)"/m)
        {id, expiry, reason}
      end)

    ids = Enum.map(entries, &elem(&1, 0))

    if length(ids) != length(@reviewed_ids) or MapSet.new(ids) != MapSet.new(@reviewed_ids) do
      Mix.raise("OSV exception IDs changed; review #{@tracking_issue}")
    end

    Enum.each(entries, fn {_id, expiry, reason} ->
      if expiry != Date.to_iso8601(@expires_on) or
           not String.contains?(reason, @owner) or
           not String.contains?(reason, @tracking_issue) do
        Mix.raise("OSV exception metadata changed or expired; review #{@tracking_issue}")
      end
    end)
  end

  defp capture!(entry, pattern) do
    case Regex.run(pattern, entry, capture: :all_but_first) do
      [value] -> value
      _ -> Mix.raise("invalid OSV exception configuration; review #{@tracking_issue}")
    end
  end

  defp ensure_reviewed_sobelow_skip! do
    if File.read!(".sobelow-skips") != @sobelow_skip do
      Mix.raise("Sobelow skips changed; review #{@tracking_issue}")
    end
  end
end
