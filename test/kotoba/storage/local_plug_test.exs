defmodule Kotoba.Storage.Local.PlugTest do
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  alias Kotoba.Storage.Local.Plug, as: FilePlug

  setup do
    base = Path.join(System.tmp_dir!(), "kotoba-plug-#{System.unique_integer([:positive])}")
    root = Path.join(base, "root")
    File.mkdir_p!(Path.join(root, "2026/09"))
    File.write!(Path.join(root, "2026/09/cat.png"), "png bytes")
    File.write!(Path.join(root, "2026/09/page.html"), "<script>alert(1)</script>")
    File.write!(Path.join(Path.dirname(root), "secret.txt"), "secret")
    on_exit(fn -> File.rm_rf!(base) end)

    %{root: root, opts: FilePlug.init(at: "/files", root: root, max_age: 60)}
  end

  defp call(method \\ :get, path, opts), do: conn(method, path) |> FilePlug.call(opts)

  test "serves a file with its type and the cache and safety headers", %{opts: opts} do
    conn = call("/files/2026/09/cat.png", opts)

    assert conn.halted
    assert conn.status == 200
    assert conn.resp_body == "png bytes"
    assert get_resp_header(conn, "content-type") == ["image/png"]
    assert get_resp_header(conn, "cache-control") == ["private, max-age=60"]
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert get_resp_header(conn, "content-security-policy") == ["default-src 'none'; sandbox"]
    assert get_resp_header(conn, "content-disposition") == ["inline"]
  end

  test "serves a file that is not an image as a download", %{opts: opts} do
    conn = call("/files/2026/09/page.html", opts)

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["text/html"]
    assert get_resp_header(conn, "content-disposition") == ["attachment"]
  end

  test "answers HEAD with no body", %{opts: opts} do
    conn = call(:head, "/files/2026/09/cat.png", opts)
    assert conn.status == 200
    assert conn.resp_body == ""
  end

  test "refuses .. and unsafe segments", %{opts: opts} do
    for path <- [
          "/files/2026/../../secret.txt",
          "/files/..",
          "/files/2026/%2e%2e/x",
          "/files/a%2Fb",
          "/files/a%00b"
        ] do
      conn = call(path, opts)
      assert conn.halted
      assert conn.status == 400, "#{path} gave #{conn.status}"
    end
  end

  test "gives 404 for a missing file, a directory, or the prefix alone", %{opts: opts} do
    assert call("/files/2026/09/none.png", opts).status == 404
    assert call("/files/2026/09", opts).status == 404
    assert call("/files", opts).status == 404
  end

  test "gives 404 for a symbolic link", %{root: root, opts: opts} do
    File.ln_s!(Path.join(Path.dirname(root), "secret.txt"), Path.join(root, "2026/09/link.txt"))
    assert call("/files/2026/09/link.txt", opts).status == 404
  end

  test "passes other paths and methods on", %{opts: opts} do
    for conn <- [
          call("/other/cat.png", opts),
          call("/filesx/2026/09/cat.png", opts),
          call(:post, "/files/2026/09/cat.png", opts)
        ] do
      refute conn.halted
      assert conn.status == nil
    end
  end

  test "with at: \"/\", serves the whole path (for a router forward)", %{root: root} do
    conn = call("/2026/09/cat.png", FilePlug.init(at: "/", root: root))
    assert conn.status == 200
    assert get_resp_header(conn, "cache-control") == ["private, max-age=3600"]
  end
end
