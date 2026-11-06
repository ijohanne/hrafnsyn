defmodule Hrafnsyn.Devices.Profile do
  @moduledoc """
  The small subset of Apple's Profile Service protocol used to collect a UDID.

  Callback CMS envelopes are decoded, not authenticated as Apple device
  attestations. A returned UDID is user-supplied registration information and
  must never authorize access. The invitation challenge binds the response to
  the profile that was downloaded.
  """

  @max_body_bytes 65_536
  @signed_data_oid <<42, 134, 72, 134, 247, 13, 1, 7, 2>>
  @data_oid <<42, 134, 72, 134, 247, 13, 1, 7, 1>>
  @challenge_pattern ~r/\A[A-Za-z0-9_-]{32,128}\z/
  @udid_pattern ~r/\A(?:[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}|[0-9A-Fa-f]{40})\z/
  @declaration ~r/\A<\?xml\s+version=(["'])1\.0\1(?:\s+encoding=(["'])UTF-8\2)?(?:\s+standalone=(["'])(?:yes|no)\3)?\s*\?>/i
  @doctype ~r/\A<!DOCTYPE\s+plist\s+PUBLIC\s+(["'])-\/\/Apple(?: Inc)?\/\/DTD PLIST 1\.0\/\/EN\1\s+(["'])https?:\/\/www\.apple\.com\/DTDs\/PropertyList-1\.0\.dtd\2\s*>/
  @plist ~r/\A<plist\s+version=(?:"1\.0"|'1\.0')\s*>\s*<dict>\s*(.*?)\s*<\/dict>\s*<\/plist>\z/s
  @pair ~r/\A\s*<key>([A-Z][A-Z0-9_]{0,63})<\/key>\s*<(string|data)>([^<]*)<\/\2>\s*/s
  @entities %{
    "&amp;" => "&",
    "&lt;" => "<",
    "&gt;" => ">",
    "&quot;" => "\"",
    "&apos;" => "'"
  }
  @entity_pattern ~r/&(amp|lt|gt|quot|apos);/

  @spec max_body_bytes() :: pos_integer()
  def max_body_bytes, do: @max_body_bytes

  @spec generate(String.t(), String.t(), String.t()) ::
          {:ok, String.t()} | {:error, :invalid_profile}
  def generate(callback_url, challenge, profile_uuid)
      when is_binary(callback_url) and is_binary(challenge) and is_binary(profile_uuid) do
    with true <- valid_callback_url?(callback_url),
         true <- Regex.match?(@challenge_pattern, challenge),
         {:ok, uuid} <- Ecto.UUID.cast(profile_uuid) do
      {:ok, profile_xml(callback_url, challenge, uuid)}
    else
      _ -> {:error, :invalid_profile}
    end
  end

  def generate(_callback_url, _challenge, _profile_uuid), do: {:error, :invalid_profile}

  @spec parse_callback(binary(), String.t()) ::
          {:ok, String.t()} | {:error, :invalid_callback}
  def parse_callback(body, expected_challenge)
      when is_binary(body) and byte_size(body) <= @max_body_bytes and
             is_binary(expected_challenge) do
    with true <- Regex.match?(@challenge_pattern, expected_challenge),
         {:ok, xml} <- cms_content(body),
         {:ok, values} <- plist_values(xml),
         {:ok, udid} <- validate_values(values, expected_challenge) do
      {:ok, udid}
    else
      _ -> {:error, :invalid_callback}
    end
  end

  def parse_callback(_body, _expected_challenge), do: {:error, :invalid_callback}

  @spec normalize_udid(term()) :: {:ok, String.t()} | {:error, :invalid_udid}
  def normalize_udid(value) when is_binary(value) and byte_size(value) in [25, 40] do
    if Regex.match?(@udid_pattern, value),
      do: {:ok, String.upcase(value)},
      else: {:error, :invalid_udid}
  end

  def normalize_udid(_value), do: {:error, :invalid_udid}

  defp valid_callback_url?(url) when byte_size(url) <= 2_048 do
    with true <- String.valid?(url),
         {:ok, uri} <- URI.new(url) do
      valid_callback_transport?(uri) and is_nil(uri.userinfo) and is_nil(uri.fragment) and
        not String.match?(url, ~r/[\x00-\x20\x7F]/)
    else
      _ -> false
    end
  end

  defp valid_callback_url?(_url), do: false

  defp valid_callback_transport?(%URI{scheme: "https", host: host}) do
    is_binary(host) and host != ""
  end

  defp valid_callback_transport?(%URI{scheme: "http", host: host}),
    do: host in ["localhost", "127.0.0.1", "::1"]

  defp valid_callback_transport?(_uri), do: false

  defp profile_xml(callback_url, challenge, uuid) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
      <key>PayloadContent</key><dict>
        <key>URL</key><string>#{xml_escape(callback_url)}</string>
        <key>DeviceAttributes</key><array><string>UDID</string></array>
        <key>Challenge</key><string>#{challenge}</string>
      </dict>
      <key>PayloadOrganization</key><string>Hrafnsyn</string>
      <key>PayloadDisplayName</key><string>Hrafnsyn device registration</string>
      <key>PayloadDescription</key><string>Sends this device's UDID to the Hrafnsyn user who invited you. Does not install an app or grant device management.</string>
      <key>PayloadVersion</key><integer>1</integer>
      <key>PayloadUUID</key><string>#{uuid}</string>
      <key>PayloadIdentifier</key><string>io.hrafnsyn.device-registration.#{uuid}</string>
      <key>PayloadType</key><string>Profile Service</string>
    </dict></plist>
    """
  end

  defp xml_escape(value) do
    value
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end

  defp cms_content(body) do
    with {:ok, {0x30, content}, <<>>} <- der_value(body),
         {:ok, [{0x06, @signed_data_oid}, {0xA0, wrapped}]} <- der_fields(content, 2),
         {:ok, {0x30, signed_data}, <<>>} <- der_value(wrapped) do
      signed_content(signed_data)
    else
      _ -> :error
    end
  end

  defp signed_content(signed_data) do
    with {:ok, [{0x02, version}, {0x31, algorithms}, {0x30, content} | rest]} <-
           der_fields(signed_data, 6),
         true <- version in [<<1>>, <<3>>, <<4>>, <<5>>] and algorithms != <<>>,
         true <- signed_tail?(rest),
         {:ok, [{0x06, @data_oid}, {0xA0, wrapped}]} <- der_fields(content, 2) do
      case der_value(wrapped) do
        {:ok, {0x04, xml}, <<>>} -> {:ok, xml}
        _ -> :error
      end
    else
      _ -> :error
    end
  end

  defp signed_tail?([{0xA0, _certificates}, {0xA1, _revocations}, {0x31, signers}]),
    do: signers?(signers)

  defp signed_tail?([{0xA0, _certificates}, {0x31, signers}]), do: signers?(signers)
  defp signed_tail?([{0xA1, _revocations}, {0x31, signers}]), do: signers?(signers)
  defp signed_tail?([{0x31, signers}]), do: signers?(signers)
  defp signed_tail?(_rest), do: false

  defp signers?(signers) do
    case der_fields(signers, 8) do
      {:ok, [_ | _] = fields} -> Enum.all?(fields, &match?({0x30, <<_, _::binary>>}, &1))
      _ -> false
    end
  end

  # Decode only the shallow CMS envelope. Certificates and signer structures are
  # opaque, bounded bytes; no recursive ASN.1 or certificate validation occurs.
  defp der_fields(binary, limit), do: der_fields(binary, limit, [])
  defp der_fields(<<>>, _limit, fields), do: {:ok, Enum.reverse(fields)}

  defp der_fields(binary, limit, fields) when limit > 0 do
    with {:ok, field, rest} <- der_value(binary) do
      der_fields(rest, limit - 1, [field | fields])
    end
  end

  defp der_fields(_binary, _limit, _fields), do: :error

  defp der_value(<<tag, length, rest::binary>>) when length < 128 do
    der_content(tag, length, rest)
  end

  defp der_value(<<tag, count, rest::binary>>) when count in 129..132 do
    octets = count - 128

    case rest do
      <<length_bytes::binary-size(^octets), content::binary>> ->
        length = :binary.decode_unsigned(length_bytes)

        if :binary.first(length_bytes) != 0 and length >= 128,
          do: der_content(tag, length, content),
          else: :error

      _ ->
        :error
    end
  end

  defp der_value(_binary), do: :error

  defp der_content(tag, length, rest) when byte_size(rest) >= length do
    <<content::binary-size(^length), tail::binary>> = rest
    {:ok, {tag, content}, tail}
  end

  defp der_content(_tag, _length, _rest), do: :error

  defp plist_values(xml) do
    if String.valid?(xml) and not String.match?(xml, ~r/[\x00-\x08\x0B\x0C\x0E-\x1F]/) do
      case Regex.run(@plist, strip_plist_header(xml), capture: :all_but_first) do
        [dictionary] -> plist_pairs(dictionary, %{}, 32)
        _ -> :error
      end
    else
      :error
    end
  end

  defp strip_plist_header(xml) do
    xml
    |> String.trim_leading("\uFEFF")
    |> String.trim()
    |> then(&Regex.replace(@declaration, &1, "", global: false))
    |> String.trim_leading()
    |> then(&Regex.replace(@doctype, &1, "", global: false))
    |> String.trim_leading()
  end

  defp plist_pairs("", values, _remaining), do: {:ok, values}

  defp plist_pairs(xml, values, remaining) when remaining > 0 do
    case Regex.run(@pair, xml) do
      [matched, key, type, text] when byte_size(text) <= 1_024 ->
        if Map.has_key?(values, key) do
          :error
        else
          rest = binary_part(xml, byte_size(matched), byte_size(xml) - byte_size(matched))
          plist_pairs(rest, Map.put(values, key, {type, text}), remaining - 1)
        end

      _ ->
        :error
    end
  end

  defp plist_pairs(_xml, _values, _remaining), do: :error

  defp validate_values(%{"UDID" => {"string", udid}, "CHALLENGE" => challenge}, expected) do
    with {:ok, supplied} <- scalar(challenge),
         true <- byte_size(supplied) == byte_size(expected),
         true <- Plug.Crypto.secure_compare(supplied, expected),
         {:ok, decoded_udid} <- scalar({"string", udid}) do
      normalize_udid(decoded_udid)
    end
  end

  defp validate_values(_values, _expected), do: :error

  defp scalar({"data", text}) do
    text |> String.replace(~r/[\t\r\n ]/, "") |> Base.decode64()
  end

  defp scalar({"string", text}) do
    if String.contains?(Regex.replace(@entity_pattern, text, ""), "&"),
      do: :error,
      else: {:ok, Regex.replace(@entity_pattern, text, &Map.fetch!(@entities, &1))}
  end
end
