defmodule Hrafnsyn.DeviceProfileFixtures do
  @moduledoc """
  Structural CMS fixtures for invitation boundary tests, without signer trust.

  The fixed OpenSSL-signed callback.der fixture separately exercises real CMS
  encoding. These helpers intentionally do not create cryptographic signatures.
  """

  def callback(udid, challenge) do
    wrap_plist("""
    <plist version="1.0"><dict>
    <key>UDID</key><string>#{udid}</string>
    <key>CHALLENGE</key><string>#{challenge}</string>
    </dict></plist>
    """)
  end

  def wrap_plist(xml, signers \\ der(0x30, der(0x02, <<1>>))) do
    data_oid = der(0x06, <<42, 134, 72, 134, 247, 13, 1, 7, 1>>)
    signed_oid = der(0x06, <<42, 134, 72, 134, 247, 13, 1, 7, 2>>)
    content = der(0x30, data_oid <> der(0xA0, der(0x04, xml)))

    signed =
      der(0x30, der(0x02, <<1>>) <> der(0x31, der(0x30, <<>>)) <> content <> der(0x31, signers))

    der(0x30, signed_oid <> der(0xA0, signed))
  end

  def der(tag, content) when byte_size(content) < 128,
    do: <<tag, byte_size(content), content::binary>>

  def der(tag, content) do
    length = :binary.encode_unsigned(byte_size(content))
    <<tag, 128 + byte_size(length), length::binary, content::binary>>
  end
end
