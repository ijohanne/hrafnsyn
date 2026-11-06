defmodule Hrafnsyn.Devices.ProfileTest do
  use ExUnit.Case, async: true

  alias Hrafnsyn.Devices.Profile
  import Hrafnsyn.DeviceProfileFixtures, only: [der: 2, wrap_plist: 1, wrap_plist: 2]

  @challenge "j5mw3dSgkbUN31Pp9WqHVmAJ4OeDdYNqQHCHsi2ePlI"
  @udid "00008110-000123456789ABCD"
  @uuid "2778fad5-89f7-469d-bf84-874281e14914"
  @fixture Path.expand("../../fixtures/devices/callback.der", __DIR__)
  @apple_fixture Path.expand("../../fixtures/devices/callback-apple.ber", __DIR__)

  test "generates an unsigned minimal profile with an escaped configured HTTPS callback" do
    callback = "https://hrafnsyn.example/devices/invite/token/callback?one=1&two=2"
    assert {:ok, xml} = Profile.generate(callback, @challenge, @uuid)
    assert xml =~ "<key>PayloadType</key><string>Profile Service</string>"
    assert xml =~ "<key>DeviceAttributes</key><array><string>UDID</string></array>"
    assert xml =~ "callback?one=1&amp;two=2"
    assert xml =~ "<key>Challenge</key><string>#{@challenge}</string>"
    assert xml =~ "<key>PayloadUUID</key><string>#{@uuid}</string>"
    refute xml =~ "<string>SERIAL</string>"
    refute xml =~ "<string>IMEI</string>"
    refute xml =~ "com.apple.mdm"
  end

  test "requires HTTPS except for loopback development" do
    for url <- [
          "http://hrafnsyn.example/callback",
          "//example.com/callback",
          "file:///tmp/callback",
          "https://user:password@example.com/callback",
          "https://example.com/callback#fragment",
          "https:///callback",
          "https://example.com/\ncallback",
          <<255>>
        ] do
      assert {:error, :invalid_profile} = Profile.generate(url, @challenge, @uuid)
    end

    for host <- ["localhost", "127.0.0.1", "[::1]"] do
      assert {:ok, _} = Profile.generate("http://#{host}:4088/callback", @challenge, @uuid)
    end

    assert {:error, :invalid_profile} =
             Profile.generate("https://example.com/callback", "short", @uuid)

    assert {:error, :invalid_profile} =
             Profile.generate("https://example.com/callback", @challenge, "bad")
  end

  test "parses a real OpenSSL CMS signed envelope without claiming Apple attestation" do
    assert {:ok, @udid} = Profile.parse_callback(File.read!(@fixture), @challenge)

    assert {:error, :invalid_callback} =
             Profile.parse_callback(File.read!(@fixture), String.duplicate("x", 43))
  end

  test "parses actual Apple CMSEncoder output with indefinite BER and constructed octets" do
    body = File.read!(@apple_fixture)
    assert <<0x30, 0x80, _::binary>> = body
    assert {:ok, @udid} = Profile.parse_callback(body, @challenge)
    assert {:ok, @udid} = Profile.parse_callback_detailed(body, @challenge)

    assert {:error, :challenge_mismatch} =
             Profile.parse_callback_detailed(body, String.duplicate("x", 43))
  end

  test "accepts only OCTET STRING chunks within definite or indefinite constructed content" do
    xml = plist(@udid)
    <<first::binary-size(40), last::binary>> = xml

    for octets <- [
          ber(0x24, der(0x04, first) <> ber(0x24, der(0x04, last))),
          der(0x24, der(0x04, first) <> der(0x04, last)),
          der(0x04, xml)
        ] do
      assert {:ok, @udid} = Profile.parse_callback(ber_cms(octets), @challenge)
    end

    for octets <- [
          ber(0x24, der(0x30, der(0x04, xml))),
          ber(0x24, der(0x04, xml) <> der(0x05, <<>>)),
          ber(0x04, xml),
          der(0x24, <<0, 0>> <> der(0x04, xml))
        ] do
      assert {:error, :invalid_cms} = Profile.parse_callback_detailed(ber_cms(octets), @challenge)
    end
  end

  test "bounds BER depth and node count and rejects unbalanced or trailing EOC" do
    good = ber_cms(ber(0x24, der(0x04, plist(@udid))))
    deep = Enum.reduce(1..25, der(0x04, plist(@udid)), fn _, value -> ber(0x24, value) end)
    wide = ber(0x24, :binary.copy(der(0x04, <<>>), 2_048) <> der(0x04, plist(@udid)))

    for body <- [
          ber_cms(deep),
          ber_cms(wide),
          good <> <<0, 0>>,
          binary_part(good, 0, byte_size(good) - 2),
          binary_part(good, 0, byte_size(good) - 1),
          <<0x30, 0x80, 0, 1, 0, 0>>,
          <<0x30, 0x80, 0x1F, 0, 0, 0>>
        ] do
      assert {:error, :invalid_cms} = Profile.parse_callback_detailed(body, @challenge)
    end
  end

  test "exposes only fixed diagnostic categories while preserving generic callback errors" do
    cases = [
      {"not CMS", :invalid_cms},
      {cms("not a plist"), :invalid_plist},
      {cms(plist(@udid, "<data>!</data>")), :invalid_plist},
      {cms(plist(@udid, "<string>wrong</string>")), :challenge_mismatch},
      {cms(plist("not a UDID")), :invalid_udid},
      {String.duplicate("x", Profile.max_body_bytes() + 1), :invalid_callback}
    ]

    for {body, category} <- cases do
      assert {:error, ^category} = Profile.parse_callback_detailed(body, @challenge)
      assert {:error, :invalid_callback} = Profile.parse_callback(body, @challenge)
    end
  end

  test "normalizes modern and legacy identifiers and accepts a binary plist challenge" do
    assert {:ok, @udid} = Profile.parse_callback(cms(plist(String.downcase(@udid))), @challenge)

    legacy = "0123456789abcdef0123456789abcdef01234567"
    xml = plist(legacy, "<data>\n#{Base.encode64(@challenge)}\n</data>")
    assert {:ok, normalized} = Profile.parse_callback(cms(xml), @challenge)
    assert normalized == String.upcase(legacy)
  end

  test "rejects missing, malformed, duplicated or mismatched values" do
    for xml <- [
          plist("00008110-1234"),
          plist("00008110-000123456789ABCZ"),
          plist(" " <> @udid),
          plist(@udid, "<string>wrong</string>"),
          plist(@udid, "<data>not valid base64!</data>"),
          plist(@udid) |> String.replace("<key>UDID</key>", "<key>OTHER</key>"),
          plist(@udid)
          |> String.replace("</dict>", "<key>UDID</key><string>#{@udid}</string></dict>"),
          plist(@udid)
          |> String.replace(
            "</dict>",
            "<key>CHALLENGE</key><string>#{@challenge}</string></dict>"
          ),
          plist(@udid)
          |> String.replace(
            "<string>#{@udid}</string>",
            "<array><string>#{@udid}</string></array>"
          )
        ] do
      assert {:error, :invalid_callback} = Profile.parse_callback(cms(xml), @challenge)
    end
  end

  test "does not resolve DTDs, external entities, internal entities or arbitrary XML" do
    for xml <- [
          "<!DOCTYPE plist SYSTEM \"file:///etc/passwd\">" <> plist(@udid),
          "<!DOCTYPE plist [<!ENTITY secret SYSTEM \"file:///etc/passwd\">]>" <> plist("&secret;"),
          ~s(<!DOCTYPE plist [<!ENTITY a "x"><!ENTITY b "&a;&a;&a;">]>) <> plist("&b;"),
          plist(@udid)
          |> String.replace("<string>#{@udid}</string>", "<string>&unknown;</string>"),
          plist(@udid) |> String.replace("<dict>", "<dict><arbitrary-new-atom/>"),
          plist(@udid) |> String.replace(~s(version="1.0"), ~s(version="1.0')),
          plist(@udid) |> String.replace("</dict>", "<key>OTHER</key><string>\0</string></dict>"),
          "<![CDATA[" <> plist(@udid) <> "]]>",
          plist(@udid) <> "<extra/>"
        ] do
      assert {:error, :invalid_callback} = Profile.parse_callback(cms(xml), @challenge)
    end
  end

  test "allows the inert Apple plist header without fetching its DTD" do
    header = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple Inc//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    """

    assert {:ok, @udid} = Profile.parse_callback(cms(header <> plist(@udid)), @challenge)
  end

  test "requires a bounded CMS SignedData envelope with attached plist content" do
    good = cms(plist(@udid))

    for body <- [
          plist(@udid),
          good <> "trailing",
          binary_part(good, 0, byte_size(good) - 1),
          <<0x30, 0x80, 0, 0>>,
          <<0x30, 0x84, 255, 255, 255, 255, 0>>,
          <<0x30, 0x81, 1, 0>>,
          der(0x30, der(0x06, <<1, 2, 3>>) <> der(0xA0, der(0x30, <<>>))),
          der(
            0x30,
            der(0x06, <<42, 134, 72, 134, 247, 13, 1, 7, 2>>) <> der(0xA0, der(0x04, "wrong"))
          ),
          String.duplicate("x", Profile.max_body_bytes() + 1),
          cms(<<255>>),
          cms(plist(@udid), <<>>),
          cms(plist(@udid), der(0x04, "not a signer"))
        ] do
      assert {:error, :invalid_callback} = Profile.parse_callback(body, @challenge)
    end
  end

  test "limits dictionary size and scalar lengths" do
    pairs = for n <- 1..33, into: "", do: "<key>VALUE_#{n}</key><string>x</string>"
    xml = String.replace(plist(@udid), "</dict>", pairs <> "</dict>")
    assert {:error, :invalid_callback} = Profile.parse_callback(cms(xml), @challenge)

    xml = plist(@udid, "<string>#{String.duplicate("x", 1_025)}</string>")
    assert {:error, :invalid_callback} = Profile.parse_callback(cms(xml), @challenge)
  end

  defp plist(udid, challenge_xml \\ "<string>#{@challenge}</string>") do
    """
    <plist version="1.0"><dict>
    <key>UDID</key><string>#{udid}</string>
    <key>CHALLENGE</key>#{challenge_xml}
    </dict></plist>
    """
  end

  defp cms(xml), do: wrap_plist(xml)
  defp cms(xml, signers), do: wrap_plist(xml, signers)

  defp ber(tag, content), do: <<tag, 0x80, content::binary, 0, 0>>

  defp ber_cms(octets) do
    data_oid = der(0x06, <<42, 134, 72, 134, 247, 13, 1, 7, 1>>)
    signed_oid = der(0x06, <<42, 134, 72, 134, 247, 13, 1, 7, 2>>)
    content = ber(0x30, data_oid <> ber(0xA0, octets))
    signer = der(0x30, der(0x02, <<1>>))
    signed = ber(0x30, der(0x02, <<1>>) <> der(0x31, signer) <> content <> der(0x31, signer))
    ber(0x30, signed_oid <> ber(0xA0, signed))
  end
end
