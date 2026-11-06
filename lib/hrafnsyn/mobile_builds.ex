defmodule Hrafnsyn.MobileBuilds do
  @moduledoc """
  Stores one privately served iOS build. Publishing atomically replaces the prior file.

  Archive checks establish the shape of an IPA, not its signature or provisioning.
  Administrators remain responsible for exporting a correctly signed build.
  """

  alias Hrafnsyn.Accounts.{Scope, User}

  @max_bytes 250 * 1024 * 1024
  @max_entries 100_000

  @type failure :: :forbidden | :invalid_ipa | :too_large | :storage_unavailable

  @spec max_bytes() :: pos_integer()
  def max_bytes, do: @max_bytes

  @spec current() ::
          {:ok, %{size: non_neg_integer(), uploaded_at: DateTime.t()}}
          | {:error, :not_found | :storage_unavailable}
  def current do
    case File.lstat(current_path(), time: :posix) do
      {:ok, %File.Stat{type: :regular, size: size, mtime: modified}} ->
        {:ok, %{size: size, uploaded_at: DateTime.from_unix!(modified)}}

      {:error, :enoent} ->
        {:error, :not_found}

      _ ->
        {:error, :storage_unavailable}
    end
  end

  @spec download(Scope.t() | nil) ::
          {:ok, String.t()} | {:error, :forbidden | :not_found | :storage_unavailable}
  def download(%Scope{user: %User{id: id}}) when is_binary(id) do
    with {:ok, _metadata} <- current(), do: {:ok, current_path()}
  end

  def download(_scope), do: {:error, :forbidden}

  @doc "Serves a stable inode while a replacement may be published concurrently."
  @spec with_download(Scope.t() | nil, (String.t() -> result)) ::
          {:ok, result} | {:error, :forbidden | :not_found | :storage_unavailable}
        when result: term()
  def with_download(scope, callback) do
    with {:ok, path} <- download(scope) do
      snapshot = Path.join(directory(), ".download-#{Ecto.UUID.generate()}")

      case File.ln(path, snapshot) do
        :ok ->
          try do
            {:ok, callback.(snapshot)}
          after
            File.rm(snapshot)
          end

        {:error, _reason} ->
          {:error, :storage_unavailable}
      end
    end
  end

  @spec publish(Scope.t() | nil, Plug.Upload.t() | term()) :: :ok | {:error, failure()}
  def publish(%Scope{user: %User{is_admin: true, id: id}}, %Plug.Upload{} = upload)
      when is_binary(id) do
    with :ok <- validate_upload(upload),
         :ok <- prepare_directory() do
      stage_and_replace(upload.path)
    end
  end

  def publish(%Scope{user: %User{is_admin: true}}, _upload), do: {:error, :invalid_ipa}
  def publish(_scope, _upload), do: {:error, :forbidden}

  defp validate_upload(%Plug.Upload{path: path, filename: filename})
       when is_binary(path) and is_binary(filename) do
    if String.valid?(filename) and String.downcase(Path.extname(filename)) == ".ipa" do
      validate_size(path)
    else
      {:error, :invalid_ipa}
    end
  end

  defp validate_upload(_upload), do: {:error, :invalid_ipa}

  defp validate_size(path) do
    case File.lstat(path) do
      {:ok, %File.Stat{type: :regular, size: size}} when size > @max_bytes ->
        {:error, :too_large}

      {:ok, %File.Stat{type: :regular, size: size}} when size > 0 ->
        :ok

      _ ->
        {:error, :invalid_ipa}
    end
  end

  defp prepare_directory do
    with :ok <- File.mkdir_p(directory()),
         :ok <- File.chmod(directory(), 0o700) do
      :ok
    else
      _ -> {:error, :storage_unavailable}
    end
  end

  defp stage_and_replace(source) do
    stage = Path.join(directory(), ".upload-#{Ecto.UUID.generate()}")

    try do
      with :ok <- copy_private(source, stage),
           :ok <- validate_size(stage),
           :ok <- validate_archive(stage) do
        replace_current(stage)
      end
    after
      File.rm(stage)
    end
  end

  defp copy_private(source, stage) do
    with :ok <- File.cp(source, stage),
         :ok <- File.chmod(stage, 0o600),
         :ok <- File.touch(stage) do
      :ok
    else
      _ -> {:error, :storage_unavailable}
    end
  end

  defp replace_current(stage) do
    case File.rename(stage, current_path()) do
      :ok -> :ok
      {:error, _reason} -> {:error, :storage_unavailable}
    end
  end

  defp validate_archive(path) do
    case :zip.list_dir(String.to_charlist(path)) do
      {:ok, entries} when length(entries) <= @max_entries -> validate_entries(entries)
      _ -> {:error, :invalid_ipa}
    end
  end

  defp validate_entries(entries) do
    names = for {:zip_file, name, _info, _comment, _offset, _size} <- entries, do: name

    if Enum.all?(names, &safe_name?/1) and
         length(Enum.uniq(names)) == length(names) and
         Enum.count(names, &app_info?/1) == 1 do
      :ok
    else
      {:error, :invalid_ipa}
    end
  end

  defp safe_name?(name) do
    case :unicode.characters_to_binary(name) do
      name when is_binary(name) ->
        not String.starts_with?(name, "/") and
          not String.contains?(name, ["\\", <<0>>]) and
          ".." not in String.split(name, "/")

      _ ->
        false
    end
  end

  defp app_info?(name) do
    case :unicode.characters_to_binary(name) do
      name when is_binary(name) -> Regex.match?(~r{\APayload/[^/]+\.app/Info\.plist\z}, name)
      _ -> false
    end
  end

  defp directory do
    Application.get_env(:hrafnsyn, :mobile_build_directory, Path.expand("tmp/mobile-builds"))
  end

  defp current_path, do: Path.join(directory(), "current.ipa")
end
