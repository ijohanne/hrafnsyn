defmodule Hrafnsyn.MobileBuilds.Metadata do
  @moduledoc "Reads bounded manifest metadata from the app inside an IPA."

  @max_output 8192
  @timeout 6000

  @type metadata :: %{
          bundle_identifier: String.t(),
          bundle_version: String.t(),
          title: String.t()
        }

  @spec read(String.t()) :: {:ok, metadata()} | {:error, :invalid_ipa | :metadata_unavailable}
  def read(path) when is_binary(path) do
    script = Application.app_dir(:hrafnsyn, "priv/scripts/read_ipa_metadata.py")

    port =
      Port.open({:spawn_executable, String.to_charlist(script)}, [
        :binary,
        :exit_status,
        :use_stdio,
        :stderr_to_stdout,
        args: [path]
      ])

    deadline = System.monotonic_time(:millisecond) + @timeout
    collect(port, "", deadline)
  rescue
    ErlangError -> {:error, :metadata_unavailable}
  end

  def read(_path), do: {:error, :invalid_ipa}

  defp collect(port, output, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, data}} when byte_size(output) + byte_size(data) <= @max_output ->
        collect(port, output <> data, deadline)

      {^port, {:data, _data}} ->
        close(port)
        {:error, :metadata_unavailable}

      {^port, {:exit_status, 0}} ->
        decode(output)

      {^port, {:exit_status, 2}} ->
        {:error, :invalid_ipa}

      {^port, {:exit_status, _status}} ->
        {:error, :metadata_unavailable}
    after
      remaining ->
        close(port)
        {:error, :metadata_unavailable}
    end
  end

  defp close(port) do
    Port.close(port)
  rescue
    ArgumentError -> :ok
  end

  defp decode(output) do
    case Jason.decode(output) do
      {:ok, %{"bundle_identifier" => bundle, "bundle_version" => version, "title" => title}}
      when is_binary(bundle) and is_binary(version) and is_binary(title) ->
        {:ok, %{bundle_identifier: bundle, bundle_version: version, title: title}}

      _ ->
        {:error, :metadata_unavailable}
    end
  end
end
