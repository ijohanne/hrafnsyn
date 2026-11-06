defmodule Hrafnsyn.Devices.Profile do
  @moduledoc """
  The small subset of Apple's Profile Service protocol used to collect a UDID.

  Callback CMS envelopes are decoded, not authenticated as Apple device
  attestations. A returned UDID is user-supplied registration information and
  must never authorize access. The invitation challenge binds the response to
  the profile that was downloaded.
  """

  @max_body_bytes 65_536
  @max_asn1_depth 24
  @max_asn1_nodes 2_048
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
  def parse_callback(body, expected_challenge) do
    case parse_callback_detailed(body, expected_challenge) do
      {:ok, udid} -> {:ok, udid}
      {:error, _reason} -> {:error, :invalid_callback}
    end
  end

  @doc "Returns only fixed diagnostic categories; never returns callback content."
  @spec parse_callback_detailed(binary(), String.t()) ::
          {:ok, String.t()}
          | {:error,
             :invalid_callback
             | :invalid_cms
             | :invalid_plist
             | :challenge_mismatch
             | :invalid_udid}
  def parse_callback_detailed(body, expected_challenge)
      when is_binary(body) and byte_size(body) <= @max_body_bytes and
             is_binary(expected_challenge) do
    with true <- Regex.match?(@challenge_pattern, expected_challenge),
         {:cms, {:ok, xml}} <- {:cms, cms_content(body)},
         {:plist, {:ok, values}} <- {:plist, plist_values(xml)},
         {:ok, udid} <- validate_values(values, expected_challenge) do
      {:ok, udid}
    else
      {:cms, _} -> {:error, :invalid_cms}
      {:plist, _} -> {:error, :invalid_plist}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_callback}
    end
  end

  def parse_callback_detailed(_body, _expected_challenge), do: {:error, :invalid_callback}

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
    case asn1_value(body, 0, @max_asn1_nodes) do
      {:ok, {0x30, [{0x06, @signed_data_oid}, {0xA0, [{0x30, signed_data}]}]}, <<>>, _remaining} ->
        signed_content(signed_data)

      _ ->
        :error
    end
  end

  defp signed_content([{0x02, version}, {0x31, algorithms}, {0x30, content} | rest]) do
    with true <- version in [<<1>>, <<3>>, <<4>>, <<5>>] and algorithms != [],
         true <- signed_tail?(rest),
         [{0x06, @data_oid}, {0xA0, [wrapped]}] <- content,
         {:ok, chunks} <- octet_content(wrapped) do
      {:ok, IO.iodata_to_binary(chunks)}
    else
      _ -> :error
    end
  end

  defp signed_content(_signed_data), do: :error

  defp octet_content({0x04, bytes}) when is_binary(bytes), do: {:ok, bytes}

  defp octet_content({0x24, children}) do
    Enum.reduce_while(children, {:ok, []}, fn child, {:ok, chunks} ->
      case octet_content(child) do
        {:ok, bytes} -> {:cont, {:ok, [bytes | chunks]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, chunks} -> {:ok, Enum.reverse(chunks)}
      :error -> :error
    end
  end

  defp octet_content(_value), do: :error

  defp signed_tail?([{0xA0, _certificates}, {0xA1, _revocations}, {0x31, signers}]),
    do: signers?(signers)

  defp signed_tail?([{0xA0, _certificates}, {0x31, signers}]), do: signers?(signers)
  defp signed_tail?([{0xA1, _revocations}, {0x31, signers}]), do: signers?(signers)
  defp signed_tail?([{0x31, signers}]), do: signers?(signers)
  defp signed_tail?(_rest), do: false

  defp signers?(signers) do
    length(signers) in 1..8 and Enum.all?(signers, &match?({0x30, [_ | _]}, &1))
  end

  # Apple's CMS encoder streams BER with indefinite constructed containers.
  # Bound the entire tree, including opaque certificate/signature structures;
  # EOC is accepted only while reading an indefinite constructed container.
  defp asn1_value(<<tag, rest::binary>>, depth, remaining)
       when tag != 0 and Bitwise.band(tag, 31) != 31 and
              depth < @max_asn1_depth and remaining > 0 do
    with {:ok, length, content} <- asn1_length(rest) do
      asn1_content(tag, length, content, depth, remaining - 1)
    end
  end

  defp asn1_value(_binary, _depth, _remaining), do: :error

  defp asn1_length(<<128, rest::binary>>), do: {:ok, :indefinite, rest}
  defp asn1_length(<<length, rest::binary>>) when length < 128, do: {:ok, length, rest}

  defp asn1_length(<<count, rest::binary>>) when count in 129..132 do
    octets = count - 128

    case rest do
      <<length_bytes::binary-size(^octets), content::binary>> ->
        length = :binary.decode_unsigned(length_bytes)

        if :binary.first(length_bytes) != 0 and length >= 128,
          do: {:ok, length, content},
          else: :error

      _ ->
        :error
    end
  end

  defp asn1_length(_binary), do: :error

  defp asn1_content(tag, :indefinite, rest, depth, remaining)
       when Bitwise.band(tag, 32) != 0 do
    with {:ok, fields, tail, remaining} <-
           asn1_fields(rest, :indefinite, depth + 1, remaining, []) do
      {:ok, {tag, fields}, tail, remaining}
    end
  end

  defp asn1_content(tag, length, rest, depth, remaining)
       when is_integer(length) and byte_size(rest) >= length do
    <<content::binary-size(^length), tail::binary>> = rest

    if Bitwise.band(tag, 32) == 0 do
      {:ok, {tag, content}, tail, remaining}
    else
      with {:ok, fields, <<>>, remaining} <-
             asn1_fields(content, :definite, depth + 1, remaining, []) do
        {:ok, {tag, fields}, tail, remaining}
      end
    end
  end

  defp asn1_content(_tag, _length, _rest, _depth, _remaining), do: :error

  defp asn1_fields(<<>>, :definite, _depth, remaining, fields),
    do: {:ok, Enum.reverse(fields), <<>>, remaining}

  defp asn1_fields(<<0, 0, tail::binary>>, :indefinite, _depth, remaining, fields),
    do: {:ok, Enum.reverse(fields), tail, remaining}

  defp asn1_fields(binary, mode, depth, remaining, fields) do
    with {:ok, field, rest, remaining} <- asn1_value(binary, depth, remaining) do
      asn1_fields(rest, mode, depth, remaining, [field | fields])
    end
  end

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
         true <-
           byte_size(supplied) == byte_size(expected) and
             Plug.Crypto.secure_compare(supplied, expected),
         {:ok, decoded_udid} <- scalar({"string", udid}) do
      normalize_udid(decoded_udid)
    else
      false -> {:error, :challenge_mismatch}
      _ -> {:error, :invalid_plist}
    end
  end

  defp validate_values(_values, _expected), do: {:error, :invalid_plist}

  defp scalar({"data", text}) do
    text |> String.replace(~r/[\t\r\n ]/, "") |> Base.decode64()
  end

  defp scalar({"string", text}) do
    if String.contains?(Regex.replace(@entity_pattern, text, ""), "&"),
      do: :error,
      else: {:ok, Regex.replace(@entity_pattern, text, &Map.fetch!(@entities, &1))}
  end
end
