defmodule Kotoba.Storage.Local.Plug do
  @moduledoc """
  Serves the files of `Kotoba.Storage.Local`, read only.

  In the endpoint, before the router:

      plug Kotoba.Storage.Local.Plug

  The plug answers `GET` and `HEAD` requests under the `:at` path (by
  default the configured `:url_prefix` of `Kotoba.Storage.Local`), and
  passes every other request on. In a router, `forward` strips the path, so
  give `at: "/"`:

      forward "/uploads/kotoba", Kotoba.Storage.Local.Plug, at: "/"

  ## Options

    * `:at` - the request path of the files. The default is the configured
      `:url_prefix`.
    * `:root` - the directory. The default is the configured `:root`.
    * `:max_age` - the `max-age` of the `Cache-Control` header, in seconds.
      The default is `3600`.

  ## Responses

    * The content type comes from the file extension.
    * `Cache-Control: private, max-age=…`, `X-Content-Type-Options: nosniff`
      and `Content-Security-Policy: default-src 'none'; sandbox`, so a file
      cannot run a script on the app's origin.
    * PNG, JPEG, GIF and WebP images are served inline; every other file
      has `Content-Disposition: attachment`.
    * A path with a segment that is not a valid key segment (`..`, `.`, or
      a character other than ASCII letters, digits, `.`, `-` and `_`) gives
      `400`. A key with no regular file (a directory or a symbolic link
      included) gives `404`.
  """

  @behaviour Plug

  import Plug.Conn

  alias Kotoba.Storage
  alias Kotoba.Storage.Local

  @inline ~w(image/png image/jpeg image/gif image/webp)

  @impl Plug
  def init(opts), do: Keyword.validate!(opts, [:at, :root, max_age: 3600])

  @impl Plug
  def call(%Plug.Conn{method: method} = conn, opts) when method in ["GET", "HEAD"] do
    at = split(Keyword.get_lazy(opts, :at, &Local.url_prefix/0))

    case strip(conn.path_info, at) do
      nil -> conn
      segments -> serve(conn, segments, opts)
    end
  end

  def call(conn, _opts), do: conn

  defp split(path), do: String.split(path, "/", trim: true)

  defp strip(path_info, []), do: path_info
  defp strip([segment | path_info], [segment | at]), do: strip(path_info, at)
  defp strip(_path_info, _at), do: nil

  defp serve(conn, [], _opts), do: halt_with(conn, 404)

  defp serve(conn, segments, opts) do
    if Enum.all?(segments, &Storage.valid_segment?/1) do
      root = opts |> Keyword.get_lazy(:root, &Local.root/0) |> Path.expand()
      send_regular_file(conn, Path.join([root | segments]), opts)
    else
      halt_with(conn, 400)
    end
  end

  defp send_regular_file(conn, path, opts) do
    case File.lstat(path) do
      {:ok, %File.Stat{type: :regular}} ->
        type = MIME.from_path(path)

        conn
        |> put_resp_content_type(type, nil)
        |> put_resp_header("cache-control", "private, max-age=#{opts[:max_age]}")
        |> put_resp_header("x-content-type-options", "nosniff")
        |> put_resp_header("content-security-policy", "default-src 'none'; sandbox")
        |> put_resp_header("content-disposition", disposition(type))
        |> send_body(path)
        |> halt()

      _other ->
        halt_with(conn, 404)
    end
  end

  defp send_body(%Plug.Conn{method: "HEAD"} = conn, _path), do: send_resp(conn, 200, "")
  defp send_body(conn, path), do: send_file(conn, 200, path)

  defp disposition(type) when type in @inline, do: "inline"
  defp disposition(_type), do: "attachment"

  defp halt_with(conn, status), do: conn |> send_resp(status, "") |> halt()
end
