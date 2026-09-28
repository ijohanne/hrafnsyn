defmodule Mix.Tasks.Security do
  use Mix.Task

  alias Mix.Dep.Lock

  @shortdoc "Runs the local dependency and Phoenix security checks"
  @moduledoc """
  Runs the blocking local scanners and writes their reports to `tmp/security/`.

  The reviewed exceptions are specific to Hrafnsyn's current HTTP stack and
  HTTPS plug. See `docs/dependency-security.md` and vardrun `hrafnsyn-fhv`.
  """

  @requirements ["loadpaths"]
  @expires_on ~D[2026-10-14]
  @owner "Ian Johannesen"
  @tracking_issue "hrafnsyn-fhv"
  @reviewed_ids ~w(EEF-CVE-2026-43966 EEF-CVE-2026-43969)
  @mix_audit_exception "GHSA-w4f7-4cxr-rv3c"
  @reviewed_versions %{cowboy: "2.19.0", cowlib: "2.20.0", gun: "2.6.0"}
  @sobelow_skip "Config.HTTPS: HTTPS Not Enabled,config/prod.exs:0,2B5C077\n"

  @impl Mix.Task
  def run(_args) do
    ensure_reviewed_exceptions!()
    ensure_reviewed_sobelow_skip!()

    report_dir = Path.expand("tmp/security")
    File.mkdir_p!(report_dir)

    checks = [
      {"Hex retirement", "mix", ["hex.audit"], "hex-audit.log"},
      {"MixAudit", "mix",
       ["deps.audit", "--format", "json", "--ignore-advisory-ids", @mix_audit_exception],
       "mix-audit.json"},
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

    if status == 0 do
      Mix.shell().info("#{name}: passed (#{Path.relative_to_cwd(report)})")
      []
    else
      Mix.shell().error("#{name}: exit #{status} (#{Path.relative_to_cwd(report)})")
      [name]
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

    ensure_osv_config!()
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
