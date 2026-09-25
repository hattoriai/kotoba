defmodule Kotoba.Storage do
  @moduledoc """
  The behaviour of a file store for attachments.

  `Kotoba.Live.consume_uploads/4` stores each uploaded file through the
  configured adapter, and puts the URL that the adapter returns in the
  attachment node:

      config :kotoba, storage: Kotoba.Storage.Local

  The default adapter is `Kotoba.Storage.Local`.

  ## Keys

  A key is a relative path with segments of ASCII letters, digits, `.`, `-`
  and `_`, separated by `/`. A segment is never `.` or `..`. `key/1` makes
  a new key in the form `yyyy/mm/<uuid>-<safe name>`. An adapter refuses a
  key that `valid_key?/1` refuses.

  ## Another store

  To keep the files somewhere else (S3, another object store, a database),
  write a module with the three callbacks and name it in the config, or
  give it per call with the `:storage` option of
  `Kotoba.Live.consume_uploads/4`. For example, with `ExAws.S3`:

      defmodule MyApp.KotobaStorage do
        @behaviour Kotoba.Storage

        @bucket "my-app-uploads"

        @impl true
        def put(key, path, meta) do
          path
          |> ExAws.S3.Upload.stream_file()
          |> ExAws.S3.upload(@bucket, key, content_type: meta.content_type)
          |> ExAws.request()
          |> case do
            {:ok, _response} -> {:ok, url(key)}
            {:error, reason} -> {:error, reason}
          end
        end

        @impl true
        def url(key), do: "https://\#{@bucket}.s3.amazonaws.com/" <> key

        @impl true
        def delete(key) do
          case ExAws.request(ExAws.S3.delete_object(@bucket, key)) do
            {:ok, _response} -> :ok
            {:error, reason} -> {:error, reason}
          end
        end
      end

      config :kotoba, storage: MyApp.KotobaStorage

  The URL goes into the stored document, so it must stay valid: a public
  or CDN URL, or a path in the app (for example `"/files/" <> key`) whose
  controller checks access and redirects to a short-lived signed URL.
  The file first comes to the LiveView (a normal LiveView upload); the
  adapter then sends it on.
  """

  @typedoc "A storage key, for example `\"2026/09/0b6…-cat.png\"`."
  @type key :: String.t()

  @typedoc """
  What Kotoba knows about the file: `:name` (the client's file name),
  `:content_type` (checked on the server) and `:bytes`.
  """
  @type meta :: %{
          optional(:name) => String.t(),
          optional(:content_type) => String.t(),
          optional(:bytes) => non_neg_integer()
        }

  @doc """
  Stores the file at `path` under `key`, and returns its URL.

  The file at `path` is a temporary file: the adapter copies it, and must
  not keep a reference to it.
  """
  @callback put(key(), path :: Path.t(), meta()) :: {:ok, url :: String.t()} | {:error, term()}

  @doc "Returns the URL of the file with `key`."
  @callback url(key()) :: String.t()

  @doc "Deletes the file with `key`. A key with no file gives `:ok`."
  @callback delete(key()) :: :ok | {:error, term()}

  @max_name 100
  @max_key 255
  @segment ~r/\A[A-Za-z0-9._\-]+\z/

  @doc """
  Returns the configured adapter (`config :kotoba, storage:`), by default
  `Kotoba.Storage.Local`.
  """
  @spec adapter() :: module()
  def adapter, do: Application.get_env(:kotoba, :storage, Kotoba.Storage.Local)

  @doc """
  Returns a new key for a file name: `yyyy/mm/<uuid>-<safe name>`, with the
  year and month of now (UTC) and a random UUID.

  ## Examples

      iex> key = Kotoba.Storage.key("My cat (1).png")
      iex> [_year, _month, file] = String.split(key, "/")
      iex> String.slice(file, 37..-1//1)
      "My_cat_1_.png"

  """
  @spec key(String.t()) :: key()
  def key(name) when is_binary(name) do
    now = DateTime.utc_now()
    year = now.year |> Integer.to_string() |> String.pad_leading(4, "0")
    month = now.month |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{year}/#{month}/#{uuid()}-#{safe_name(name)}"
  end

  @doc """
  Returns a safe file name: ASCII letters, digits, `.`, `-` and `_`, at
  most #{@max_name} characters, with the extension kept.

  Every run of other characters becomes one `_`, and a run of dots becomes
  one dot. A name with nothing left is `"file"`.

  ## Examples

      iex> Kotoba.Storage.safe_name("../../etc/passwd")
      "._._etc_passwd"

      iex> Kotoba.Storage.safe_name("résumé 2026.pdf")
      "r_sum_2026.pdf"

      iex> Kotoba.Storage.safe_name("")
      "file"

  """
  @spec safe_name(String.t()) :: String.t()
  def safe_name(name) when is_binary(name) do
    safe =
      name
      |> String.replace(~r/[^A-Za-z0-9._\-]+/, "_")
      |> String.replace(~r/\.{2,}/, ".")

    safe = if safe in ["", ".", "_"], do: "file", else: safe
    truncate(safe)
  end

  defp truncate(name) when byte_size(name) <= @max_name, do: name

  defp truncate(name) do
    ext = Path.extname(name)
    ext = if byte_size(ext) <= 16, do: ext, else: ""
    binary_part(name, 0, @max_name - byte_size(ext)) <> ext
  end

  @doc """
  Returns `true` when `key` is a valid storage key (see the module doc).

  ## Examples

      iex> Kotoba.Storage.valid_key?("2026/09/a-cat.png")
      true

      iex> Kotoba.Storage.valid_key?("2026/../../etc/passwd")
      false

      iex> Kotoba.Storage.valid_key?("/etc/passwd")
      false

  """
  @spec valid_key?(term()) :: boolean()
  def valid_key?(key) when is_binary(key) and byte_size(key) in 1..@max_key do
    key |> String.split("/") |> Enum.all?(&valid_segment?/1)
  end

  def valid_key?(_key), do: false

  @doc false
  @spec valid_segment?(String.t()) :: boolean()
  def valid_segment?(segment) when segment in ["", ".", ".."], do: false
  def valid_segment?(segment) when is_binary(segment), do: Regex.match?(@segment, segment)

  defp uuid do
    <<a::48, _version::4, b::12, _variant::2, c::62>> = :crypto.strong_rand_bytes(16)
    <<a::48, 4::4, b::12, 2::2, c::62>> |> Base.encode16(case: :lower) |> format_uuid()
  end

  defp format_uuid(
         <<a::binary-size(8), b::binary-size(4), c::binary-size(4), d::binary-size(4),
           e::binary-size(12)>>
       ),
       do: Enum.join([a, b, c, d, e], "-")
end
