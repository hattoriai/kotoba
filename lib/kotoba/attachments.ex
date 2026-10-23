if Code.ensure_loaded?(Storehouse) do
  defmodule Kotoba.Attachments do
    @moduledoc """
    Server-side checks of an uploaded file, before it becomes an attachment
    node.

    The browser's content type is a claim. `describe/2` keeps only a type
    that the bytes of the file prove, from a short allow-list of passive
    types:

      * PNG, JPEG, GIF and WebP images, from their signatures, with their
        width and height when the header has them (a JPEG's turned as its
        EXIF orientation says, as browsers draw it). The browser's claim does
        not matter: a PNG sent as `text/html` is a PNG.
      * PDF, from `%PDF-`.
      * MP4 video (`video/mp4`), from its `ftyp` box with an MP4 brand
        (`isom`, `mp41`, `mp42`, `avc1`, `M4V `, …), and WebM video
        (`video/webm`), from its EBML header with the `webm` document type.
        A QuickTime (`.mov`), Matroska (`.mkv`) or audio-only (`M4A `) file
        is not in the list.
      * ZIP files (`PK\\x03\\x04`): the Office Open XML and OpenDocument
        types when the browser claims one of them, else `application/zip`.
      * The older Office files (the OLE2 signature): `application/msword`,
        `application/vnd.ms-excel` or `application/vnd.ms-powerpoint` when the
        browser claims one of them.
      * `text/plain`, only when the browser claims it and the start of the
        file is valid UTF-8 with no NUL byte.

    Every other file becomes `application/octet-stream`: `text/html`,
    `application/xhtml+xml`, `image/svg+xml`, JavaScript, and any type that
    is not in the list. Such a file renders as a download link, and its
    storage key ends in `.bin`.

    `extension/1` gives the file extension of each checked type, and
    `inline?/1` tells which types a browser can show in the page (the
    images, PDF and the videos). Serve every other file with
    `Content-Disposition: attachment`.

    `store/2` makes an attachment of a file on the server, as an upload
    does: for seeds, imports, or files an app makes itself.

    The checks and the store are [Storehouse](https://hexdocs.pm/storehouse)'s
    (`Storehouse.Check`, `Storehouse.store/2`): these functions give them as
    attachments.
    """

    alias Kotoba.Nodes.Attachment
    alias Kotoba.{Sanitizer, Storage}

    @typedoc "What `describe/2` finds."
    @type description :: %{
            content_type: String.t(),
            bytes: non_neg_integer(),
            width: pos_integer() | nil,
            height: pos_integer() | nil
          }

    @doc """
    Reads the file at `path` and returns its checked content type, its size
    and, for an image, its width and height.
    """
    @spec describe(Path.t(), String.t() | nil) :: {:ok, description()} | {:error, term()}
    def describe(path, client_type), do: Storehouse.Check.describe(path, client_type)

    @doc """
    Returns the file extension of a checked content type. A type that is
    not in the allow-list gives `".bin"`.

    ## Examples

        iex> Kotoba.Attachments.extension("image/jpeg")
        ".jpg"

        iex> Kotoba.Attachments.extension("text/html")
        ".bin"

    """
    @spec extension(String.t()) :: String.t()
    defdelegate extension(content_type), to: Storehouse.Check

    @doc """
    Returns the checked content type for a file extension (as `extension/1`
    gives it), or `"application/octet-stream"`.

    ## Examples

        iex> Kotoba.Attachments.content_type(".pdf")
        "application/pdf"

        iex> Kotoba.Attachments.content_type(".svg")
        "application/octet-stream"

    """
    @spec content_type(String.t()) :: String.t()
    defdelegate content_type(extension), to: Storehouse.Check

    @doc """
    Returns `true` for a checked type that a browser can show in the page:
    the images, PDF and the videos. Serve every other type with
    `Content-Disposition: attachment`.

    ## Examples

        iex> Kotoba.Attachments.inline?("video/webm")
        true

        iex> Kotoba.Attachments.inline?("application/pdf")
        true

        iex> Kotoba.Attachments.inline?("text/plain")
        false

    """
    @spec inline?(String.t()) :: boolean()
    defdelegate inline?(content_type), to: Storehouse.Check

    @doc """
    Stores the file at `path` and returns its attachment node, as an upload
    of the file would make it.

    The file is checked with `describe/2`, stored with the storage adapter
    under a new key, and its node checked. When the adapter stores the file
    but its result does not make a valid attachment (a URL that is not a
    safe link, say), the stored file is deleted. The file at `path` is left
    where it is.

    Put the node in a document with `Kotoba.Content.from_markdown/2` and
    its `:attachments` option:

        {:ok, shot} = Kotoba.Attachments.store("priv/seeds/timeline.png")

        Kotoba.Content.from_markdown(
          "The timeline:\n\n![Timeline](attachment:timeline)",
          attachments: %{"timeline" => shot}
        )

    ## Options

      * `:name` - the file name. The default is the base name of `path`.
      * `:content_type` - the claimed content type, as a browser sends it.
        The default is the type of the file's extension. Only the bytes of
        the file make an image an image (see `describe/2`).
      * `:storage` - the store (a `Storehouse.Adapter`). The default is
        `Kotoba.Storage.adapter/0`.
      * `:key` - a function of the file name and the checked content type
        that returns a storage key. The default is `&Storehouse.key/2`.
      * `:preview` - a function of the stored attachment and `path` that
        returns the URL of a preview image, or `nil`: as the `:preview`
        option of `Kotoba.Live.consume_uploads/4`.
    """
    @spec store(Path.t(), keyword()) :: {:ok, Attachment.t()} | {:error, term()}
    def store(path, opts \\ []) when is_binary(path) do
      storage = Keyword.get_lazy(opts, :storage, &Storage.adapter/0)
      claim = Keyword.get_lazy(opts, :content_type, fn -> content_type(Path.extname(path)) end)

      store_opts =
        opts
        |> Keyword.take([:name, :key])
        |> Keyword.merge(adapter: storage, content_type: claim, preview: preview(opts[:preview]))

      with {:ok, file} <- Storehouse.store(path, store_opts) do
        node = attachment(file)

        case check_node(node) do
          :ok -> {:ok, node}
          {:error, _reason} = error -> discard(storage, file.key, error)
        end
      end
    end

    # The app's preview function takes the attachment, as it always has.
    defp preview(nil), do: nil
    defp preview(fun), do: fn file, path -> fun.(attachment(file), path) end

    defp attachment(%Storehouse.File{} = file) do
      description = Map.take(file, [:content_type, :bytes, :width, :height])
      node(description, key: file.key, url: file.url, name: file.name, preview: file.preview)
    end

    # When the store kept the file but it makes no valid attachment, the
    # stored file is deleted, so that no file is left that no document
    # points to.
    defp check_node(node) do
      cond do
        (errors = Attachment.validate(node)) != :ok -> {:error, {:invalid_attachment, errors}}
        Sanitizer.link_url(node.url) == nil -> {:error, {:unsafe_url, node.url}}
        true -> :ok
      end
    end

    defp discard(storage, key, error) do
      _result = storage.delete(key)
      error
    end

    @doc """
    Builds an attachment node for a stored file.
    """
    @spec node(description(), keyword()) :: Attachment.t()
    def node(description, attrs) do
      %Attachment{
        key: Keyword.fetch!(attrs, :key),
        url: Keyword.fetch!(attrs, :url),
        name: clean_name(Keyword.fetch!(attrs, :name)),
        content_type: description.content_type,
        bytes: description.bytes,
        width: description.width,
        height: description.height,
        preview: Keyword.get(attrs, :preview)
      }
    end

    @doc """
    Returns a file name for display: control and format characters (bidi
    controls included) removed, at most
    200 characters, and `"file"` when nothing is left.

    ## Examples

        iex> Kotoba.Attachments.clean_name("cat\\u0000.png")
        "cat.png"

        iex> Kotoba.Attachments.clean_name("a\\u202Egnp.exe")
        "agnp.exe"

    """
    @spec clean_name(term()) :: String.t()
    defdelegate clean_name(name), to: Storehouse
  end
end
