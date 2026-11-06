defmodule Hrafnsyn.MobileBuilds.MetadataTest do
  use ExUnit.Case, async: true

  alias Hrafnsyn.MobileBuilds.Metadata

  @binary_plist Base.decode64!(
                  "YnBsaXN0MDDTAQIDBAUGXxATQ0ZCdW5kbGVEaXNwbGF5TmFtZV8QEkNGQnVuZGxlSWRlbnRpZmllcl8QD0NGQnVuZGxlVmVyc2lvbl8QEUZpeHR1cmUgJiBGcmllbmRzXxASaW8uZXhhbXBsZS5maXh0dXJlUjQyCA8lOkxgdQAAAAAAAAEBAAAAAAAAAAcAAAAAAAAAAAAAAAAAAAB4"
                )

  setup do
    root = Path.join(System.tmp_dir!(), "hrafnsyn-metadata-#{Ecto.UUID.generate()}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "reads binary and XML Info.plist metadata without extracting the app", %{root: root} do
    for plist <- [@binary_plist, xml()] do
      path = ipa(root, [{~c"Payload/Fixture.app/Info.plist", plist}])

      assert {:ok,
              %{
                bundle_identifier: "io.example.fixture",
                bundle_version: "42",
                title: "Fixture & Friends"
              }} = Metadata.read(path)
    end

    assert Enum.all?(File.ls!(root), &String.ends_with?(&1, ".ipa"))
  end

  test "falls back to bundle name then identifier when display name is absent", %{root: root} do
    base = String.replace(xml(), "<key>CFBundleDisplayName</key>", "<key>CFBundleName</key>")
    assert {:ok, %{title: "Fixture & Friends"}} = Metadata.read(ipa(root, [{info(), base}]))

    base =
      String.replace(base, "<key>CFBundleName</key><string>Fixture &amp; Friends</string>", "")

    assert {:ok, %{title: "io.example.fixture"}} = Metadata.read(ipa(root, [{info(), base}]))
  end

  test "reads UTF-16 metadata while leaving unrelated binary object trees undecoded", %{
    root: root
  } do
    plist =
      Base.decode64!(
        "YnBsaXN0MDDUAQIDBAUGBwhfEBNDRkJ1bmRsZURpc3BsYXlOYW1lXxASQ0ZCdW5kbGVJZGVudGlmaWVyXxAPQ0ZCdW5kbGVWZXJzaW9uVlVudXNlZGsASAByAGEAZgBuAHMA/QBuACDYPdwmXxASaW8uZXhhbXBsZS5maXh0dXJlUjQy0QkKVWFycmF5pAsMDQ4QARACCURkYXRhCBEnPE5VbIGEh42SlJaXAAAAAAAAAQEAAAAAAAAADwAAAAAAAAAAAAAAAAAAAJw="
      )

    assert {:ok, %{title: "Hrafnsýn 🐦", bundle_version: "42"}} =
             Metadata.read(ipa(root, [{info(), plist}]))
  end

  test "rejects unsafe or ambiguous archives and oversized compressed metadata", %{root: root} do
    cases = [
      [{~c"../Info.plist", xml()}, {info(), xml()}],
      [{info(), xml()}, {~c"Payload/Other.app/Info.plist", xml()}],
      [{info(), "not a property list"}],
      [{info(), String.duplicate("a", 1024 * 1024 + 1)}],
      [{~c"Info.plist", xml()}]
    ]

    for entries <- cases do
      assert {:error, :invalid_ipa} = Metadata.read(ipa(root, entries))
    end
  end

  test "rejects invalid metadata fields and XML entities", %{root: root} do
    cases = [
      String.replace(xml(), "io.example.fixture", "../not-an-id"),
      String.replace(xml(), "<string>42</string>", "<integer>42</integer>"),
      String.replace(xml(), "<string>42</string>", "<string></string>"),
      String.replace(xml(), "<string>42</string>", "<string>&lt;script&gt;</string>"),
      String.replace(xml(), "Fixture &amp; Friends", "Fixture&#10;Friends"),
      "<!DOCTYPE plist [<!ENTITY x 'expanded'>]>" <> String.replace(xml(), "42", "&x;")
    ]

    for plist <- cases do
      assert {:error, :invalid_ipa} = Metadata.read(ipa(root, [{info(), plist}]))
    end
  end

  test "rejects oversized directory declarations before opening the zip", %{root: root} do
    path = ipa(root, [{info(), xml()}])
    data = File.read!(path)
    {offset, _length} = :binary.match(data, <<80, 75, 5, 6>>)
    <<prefix::binary-size(^offset + 12), _size::little-32, suffix::binary>> = data
    File.write!(path, <<prefix::binary, 17_000_000::little-32, suffix::binary>>)
    assert {:error, :invalid_ipa} = Metadata.read(path)
  end

  test "rejects binary plist allocation amplification through duplicate or overlapping offsets",
       %{
         root: root
       } do
    # Both files fit under the plist byte limit but a general graph decoder can
    # allocate the large data separately for each of 2048 object references.
    for kind <- [:duplicate_offsets, :overlapping_objects] do
      plist = amplification_plist(kind)
      assert byte_size(plist) < 1024 * 1024
      assert {:error, :invalid_ipa} = Metadata.read(ipa(root, [{info(), plist}]))
    end
  end

  test "missing, invalid, and symlink paths fail without returning path information", %{
    root: root
  } do
    assert {:error, :invalid_ipa} = Metadata.read(Path.join(root, "missing.ipa"))
    assert {:error, :invalid_ipa} = Metadata.read(nil)
    path = ipa(root, [{info(), xml()}])
    link = Path.join(root, "link.ipa")
    File.ln_s!(path, link)
    assert {:error, :invalid_ipa} = Metadata.read(link)
  end

  defp ipa(root, entries) do
    path = Path.join(root, "#{Ecto.UUID.generate()}.ipa")
    {:ok, _path} = :zip.create(String.to_charlist(path), entries)
    path
  end

  defp info, do: ~c"Payload/Fixture.app/Info.plist"

  defp amplification_plist(kind) do
    count = 2048
    references = for reference <- 9..(count + 8), into: <<>>, do: <<reference::16>>

    objects = [
      <<0xD4, 1::16, 2::16, 3::16, 4::16, 5::16, 6::16, 7::16, 8::16>>,
      binary_string("CFBundleIdentifier"),
      binary_string("CFBundleVersion"),
      binary_string("CFBundleDisplayName"),
      binary_string("Unused"),
      binary_string("io.example.fixture"),
      binary_string("42"),
      binary_string("Fixture"),
      <<0xAF, 0x11, count::16, references::binary>>
    ]

    {offsets, data_start} =
      Enum.map_reduce(objects, 8, fn object, offset -> {offset, offset + byte_size(object)} end)

    {payload, data_offsets} =
      case kind do
        :duplicate_offsets ->
          {<<0x4F, 0x12, 16_384::32, 0::size(16_384 * 8)>>, List.duplicate(data_start, count)}

        :overlapping_objects ->
          # Every large data object begins inside the previous object's span.
          headers = :binary.copy(<<0x4F, 0x12, 262_144::32, 0, 0>>, count)

          {headers <> :binary.copy(<<0>>, 262_144),
           Enum.map(0..(count - 1), &(data_start + &1 * 8))}
      end

    body = IO.iodata_to_binary(["bplist00", objects, payload])
    table = for offset <- offsets ++ data_offsets, into: <<>>, do: <<offset::32>>
    trailer = <<0::48, 4, 2, count + 9::64, 0::64, byte_size(body)::64>>
    body <> table <> trailer
  end

  defp binary_string(value), do: <<0x5F, 0x10, byte_size(value), value::binary>>

  defp xml do
    """
    <plist version="1.0"><dict>
    <key>CFBundleIdentifier</key><string>io.example.fixture</string>
    <key>CFBundleVersion</key><string>42</string>
    <key>CFBundleDisplayName</key><string>Fixture &amp; Friends</string>
    </dict></plist>
    """
  end
end
