defmodule Hrafnsyn.MobileBuildsTest do
  use ExUnit.Case, async: false

  alias Hrafnsyn.Accounts.{Scope, User}
  alias Hrafnsyn.MobileBuilds

  setup do
    root = Path.join(System.tmp_dir!(), "hrafnsyn-build-test-#{Ecto.UUID.generate()}")
    directory = Path.join(root, "published")
    previous = Application.fetch_env(:hrafnsyn, :mobile_build_directory)
    Application.put_env(:hrafnsyn, :mobile_build_directory, directory)
    File.mkdir_p!(root)

    on_exit(fn ->
      File.rm_rf!(root)

      case previous do
        {:ok, value} -> Application.put_env(:hrafnsyn, :mobile_build_directory, value)
        :error -> Application.delete_env(:hrafnsyn, :mobile_build_directory)
      end
    end)

    %{
      root: root,
      directory: directory,
      admin: Scope.for_user(%User{id: Ecto.UUID.generate(), is_admin: true}),
      member: Scope.for_user(%User{id: Ecto.UUID.generate(), is_admin: false})
    }
  end

  test "only an admin can publish and only an authenticated account can download", context do
    upload = ipa(context.root, "first")
    assert {:error, :forbidden} = MobileBuilds.publish(nil, upload)
    assert {:error, :forbidden} = MobileBuilds.publish(context.member, upload)
    assert {:error, :not_found} = MobileBuilds.current()
    assert {:error, :not_found} = MobileBuilds.download(context.member)
    assert :ok = MobileBuilds.publish(context.admin, upload)
    assert {:error, :forbidden} = MobileBuilds.download(nil)
    assert {:error, :forbidden} = MobileBuilds.download(Scope.for_user(%User{}))
    assert {:ok, path} = MobileBuilds.download(context.member)
    assert File.read!(path) == File.read!(upload.path)
  end

  test "replacement keeps exactly one private file with current metadata", context do
    first = ipa(context.root, "first")
    second = ipa(context.root, "second")
    assert :ok = MobileBuilds.publish(context.admin, first)
    assert :ok = MobileBuilds.publish(context.admin, second)
    assert {:ok, path} = MobileBuilds.download(context.member)
    assert File.read!(path) == File.read!(second.path)
    assert File.ls!(context.directory) == ["current.ipa"]
    assert Bitwise.band(File.stat!(path).mode, 0o777) == 0o600
    assert Bitwise.band(File.stat!(context.directory).mode, 0o777) == 0o700
    assert {:ok, %{size: size, uploaded_at: uploaded_at}} = MobileBuilds.current()
    assert size == File.stat!(second.path).size
    assert abs(DateTime.diff(DateTime.utc_now(), uploaded_at)) < 5
  end

  test "in-flight downloads retain their bytes during replacement and always remove snapshots",
       context do
    first = ipa(context.root, "first")
    second = ipa(context.root, "a-longer-replacement")
    first_bytes = File.read!(first.path)
    second_bytes = File.read!(second.path)
    assert byte_size(first_bytes) != byte_size(second_bytes)
    assert :ok = MobileBuilds.publish(context.admin, first)

    assert {:ok, {snapshot, downloaded}} =
             MobileBuilds.with_download(context.member, fn path ->
               original_size = File.stat!(path).size
               assert :ok = MobileBuilds.publish(context.admin, second)
               assert File.stat!(path).size == original_size
               {path, File.read!(path)}
             end)

    assert downloaded == first_bytes
    refute File.exists?(snapshot)
    assert {:ok, current} = MobileBuilds.download(context.member)
    assert File.read!(current) == second_bytes
    assert File.ls!(context.directory) == ["current.ipa"]

    assert_raise RuntimeError, "interrupted download", fn ->
      MobileBuilds.with_download(context.member, fn path ->
        assert File.read!(path) == second_bytes
        raise "interrupted download"
      end)
    end

    assert File.ls!(context.directory) == ["current.ipa"]
    assert File.read!(current) == second_bytes
  end

  test "bad files cannot replace the current build and leave no staging files", context do
    original = ipa(context.root, "original")
    assert :ok = MobileBuilds.publish(context.admin, original)
    invalid = Path.join(context.root, "bad.ipa")
    File.write!(invalid, "This is not an IPA")
    assert {:error, :invalid_ipa} = MobileBuilds.publish(context.admin, upload(invalid))
    assert {:error, :invalid_ipa} = MobileBuilds.publish(context.admin, %{file: "missing"})

    assert {:error, :invalid_ipa} =
             MobileBuilds.publish(context.admin, %{original | filename: "app.zip"})

    assert {:ok, path} = MobileBuilds.download(context.member)
    assert File.read!(path) == File.read!(original.path)
    assert File.ls!(context.directory) == ["current.ipa"]
  end

  test "oversized files are rejected before copying", context do
    path = Path.join(context.root, "large.ipa")
    {:ok, file} = :file.open(String.to_charlist(path), [:write, :binary])
    {:ok, _} = :file.position(file, MobileBuilds.max_bytes())
    :ok = :file.write(file, <<0>>)
    :ok = :file.close(file)
    assert {:error, :too_large} = MobileBuilds.publish(context.admin, upload(path))
    refute File.exists?(context.directory)
  end

  test "archives require exactly one top-level app and safe paths", context do
    for entries <- [
          [{~c"README.txt", "not an app"}],
          [{~c"Payload/First.app/Info.plist", "one"}, {~c"Payload/Second.app/Info.plist", "two"}],
          [{~c"Payload/App.app/Info.plist", "app"}, {~c"../escaped", "bad"}]
        ] do
      path = Path.join(context.root, "bad.ipa")
      write_zip(path, entries)
      assert {:error, :invalid_ipa} = MobileBuilds.publish(context.admin, upload(path))
    end

    assert {:error, :not_found} = MobileBuilds.current()
    assert File.ls!(context.directory) == []
  end

  test "unavailable storage has a stable error and does not expose filesystem details", context do
    File.write!(context.directory, "blocking file")

    assert {:error, :storage_unavailable} =
             MobileBuilds.publish(context.admin, ipa(context.root, "app"))

    assert {:error, :storage_unavailable} = MobileBuilds.current()
  end

  defp ipa(root, content) do
    path = Path.join(root, "#{content}.ipa")
    write_zip(path, [{~c"Payload/Hrafnsyn.app/Info.plist", content}])
    upload(path)
  end

  defp write_zip(path, entries) do
    {:ok, {_, bytes}} = :zip.create(~c"build.ipa", entries, [:memory])
    File.write!(path, bytes)
  end

  defp upload(path), do: %Plug.Upload{path: path, filename: Path.basename(path)}
end
