defmodule Hrafnsyn.MobileInstallations do
  @moduledoc "Short-lived installation grants for one current, privately stored iOS build."

  alias Hrafnsyn.Accounts
  alias Hrafnsyn.Accounts.{Scope, User}
  alias Hrafnsyn.MobileBuilds
  alias Hrafnsyn.MobileBuilds.Metadata
  alias HrafnsynWeb.Endpoint

  @lifetime 15 * 60
  @salts %{manifest: "mobile-install-manifest-v1", ipa: "mobile-install-ipa-v1"}

  @type failure ::
          :forbidden
          | :not_found
          | :storage_unavailable
          | :invalid_ipa
          | :metadata_unavailable
          | :https_required

  @spec lifetime_minutes() :: pos_integer()
  def lifetime_minutes, do: div(@lifetime, 60)

  @doc "Issues an installation link only for an existing signed-in account."
  @spec prepare(Scope.t() | nil) :: {:ok, map()} | {:error, failure()}
  def prepare(%Scope{user: %User{id: id}} = scope) when is_binary(id) do
    with {:ok, _user} <- grant_user(id),
         {:ok, origin} <- https_origin() do
      with_snapshot(scope, fn path -> prepare_snapshot(path, id, origin) end)
    end
  end

  def prepare(_scope), do: {:error, :forbidden}

  @doc "Returns a manifest without relying on Safari's cookies."
  @spec manifest(String.t()) :: {:ok, String.t()} | {:error, failure()}
  def manifest(token) do
    with_grant(token, :manifest, fn path, grant ->
      with {:ok, metadata} <- Metadata.read(path),
           {:ok, origin} <- https_origin() do
        ipa_token = sign(:ipa, grant)
        ipa_url = origin <> "/mobile-install/" <> ipa_token <> "/app.ipa"
        {:ok, manifest_xml(metadata, ipa_url)}
      end
    end)
  end

  @doc "Serves the exact authorized build from a stable snapshot."
  @spec with_ipa(String.t(), (String.t() -> result)) :: {:ok, result} | {:error, failure()}
        when result: term()
  def with_ipa(token, callback) do
    with_grant(token, :ipa, fn path, _grant -> {:ok, callback.(path)} end)
  end

  defp prepare_snapshot(path, id, origin) do
    with {:ok, fingerprint} <- fingerprint(path),
         {:ok, metadata} <- Metadata.read(path) do
      grant = %{user_id: id, fingerprint: fingerprint, expires_at: now() + @lifetime}
      manifest_url = origin <> "/mobile-install/" <> sign(:manifest, grant) <> "/manifest.plist"
      query = URI.encode_query(%{"action" => "download-manifest", "url" => manifest_url})

      {:ok,
       %{
         install_url: "itms-services://?" <> query,
         mobile_build: metadata,
         expires_in_minutes: lifetime_minutes()
       }}
    end
  end

  defp with_grant(token, purpose, callback) do
    with {:ok, grant} <- verify(token, purpose),
         {:ok, user} <- grant_user(grant.user_id) do
      with_snapshot(Scope.for_user(user), &authorize_snapshot(&1, grant, callback))
    end
  end

  defp authorize_snapshot(path, grant, callback) do
    with {:ok, fingerprint} <- fingerprint(path),
         true <- Plug.Crypto.secure_compare(fingerprint, grant.fingerprint) do
      callback.(path, grant)
    else
      false -> {:error, :forbidden}
      {:error, _} = error -> error
    end
  end

  defp with_snapshot(scope, callback) do
    case MobileBuilds.with_download(scope, callback) do
      {:ok, result} -> result
      {:error, _} = error -> error
    end
  end

  defp sign(purpose, grant), do: Phoenix.Token.sign(Endpoint, Map.fetch!(@salts, purpose), grant)

  defp verify(token, purpose) when is_binary(token) and byte_size(token) <= 2048 do
    case Phoenix.Token.verify(Endpoint, Map.fetch!(@salts, purpose), token, max_age: @lifetime) do
      {:ok, %{user_id: id, fingerprint: fingerprint, expires_at: expires_at} = grant}
      when is_binary(id) and is_binary(fingerprint) and byte_size(fingerprint) == 32 and
             is_integer(expires_at) ->
        if expires_at > now(), do: {:ok, grant}, else: {:error, :forbidden}

      _ ->
        {:error, :forbidden}
    end
  end

  defp verify(_token, _purpose), do: {:error, :forbidden}

  defp grant_user(id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %User{} = user <- Accounts.get_user(id) do
      {:ok, user}
    else
      _ -> {:error, :forbidden}
    end
  end

  defp fingerprint(path) do
    digest =
      path
      |> File.stream!(64 * 1024)
      |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
      |> :crypto.hash_final()

    {:ok, digest}
  rescue
    File.Error -> {:error, :storage_unavailable}
  end

  defp https_origin do
    url = Endpoint.url()

    case URI.new(url) do
      {:ok, %URI{scheme: "https", host: host, userinfo: nil, query: nil, fragment: nil}}
      when is_binary(host) and host != "" ->
        {:ok, String.trim_trailing(url, "/")}

      _ ->
        {:error, :https_required}
    end
  end

  defp manifest_xml(metadata, ipa_url) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict><key>items</key><array><dict>
    <key>assets</key><array><dict><key>kind</key><string>software-package</string>
    <key>url</key><string>#{xml(ipa_url)}</string></dict></array>
    <key>metadata</key><dict>
    <key>bundle-identifier</key><string>#{xml(metadata.bundle_identifier)}</string>
    <key>bundle-version</key><string>#{xml(metadata.bundle_version)}</string>
    <key>kind</key><string>software</string>
    <key>title</key><string>#{xml(metadata.title)}</string>
    </dict></dict></array></dict></plist>
    """
  end

  defp xml(value), do: value |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
  defp now, do: System.system_time(:second)
end
