defmodule Kotoba.Attachments do
  @moduledoc """
  Server-side checks of an uploaded file, before it becomes an attachment
  node.

  The browser's content type is a claim. `describe/2` keeps only a type
  that the bytes of the file prove, from a short allow-list of passive
  types:

    * PNG, JPEG, GIF and WebP images, from their signatures, with their
      width and height when the header has them. The browser's claim does
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
  """

  import Bitwise

  alias Kotoba.Nodes.Attachment

  @octet "application/octet-stream"
  @head 65_536
  @max_name 200

  @extensions %{
    "image/png" => ".png",
    "image/jpeg" => ".jpg",
    "image/gif" => ".gif",
    "image/webp" => ".webp",
    "application/pdf" => ".pdf",
    "video/mp4" => ".mp4",
    "video/webm" => ".webm",
    "text/plain" => ".txt",
    "application/zip" => ".zip",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document" => ".docx",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" => ".xlsx",
    "application/vnd.openxmlformats-officedocument.presentationml.presentation" => ".pptx",
    "application/vnd.oasis.opendocument.text" => ".odt",
    "application/vnd.oasis.opendocument.spreadsheet" => ".ods",
    "application/vnd.oasis.opendocument.presentation" => ".odp",
    "application/msword" => ".doc",
    "application/vnd.ms-excel" => ".xls",
    "application/vnd.ms-powerpoint" => ".ppt",
    @octet => ".bin"
  }

  @zip_types [
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
    "application/vnd.openxmlformats-officedocument.presentationml.presentation",
    "application/vnd.oasis.opendocument.text",
    "application/vnd.oasis.opendocument.spreadsheet",
    "application/vnd.oasis.opendocument.presentation"
  ]

  @ole_types ["application/msword", "application/vnd.ms-excel", "application/vnd.ms-powerpoint"]

  @inline [
    "image/png",
    "image/jpeg",
    "image/gif",
    "image/webp",
    "application/pdf",
    "video/mp4",
    "video/webm"
  ]

  # The major and compatible brands of an MP4 file's `ftyp` box. QuickTime
  # (`qt  `), audio-only (`M4A `, `M4B `) and HEIF/AVIF image brands are not
  # MP4 video.
  @mp4_brands [
    "isom",
    "iso2",
    "iso3",
    "iso4",
    "iso5",
    "iso6",
    "mp41",
    "mp42",
    "avc1",
    "dash",
    "mmp4",
    "M4V ",
    "M4VH",
    "M4VP",
    "msnv"
  ]
  @not_video_brands ["qt  ", "M4A ", "M4B ", "M4P ", "heic", "heix", "mif1", "msf1", "avif"]

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
  def describe(path, client_type) do
    with {:ok, %File.Stat{size: bytes}} <- File.stat(path),
         {:ok, head} <- read_head(path) do
      {content_type, width, height} =
        case image(head) do
          {type, width, height} -> {type, width, height}
          nil -> {other_type(head, claim(client_type)), nil, nil}
        end

      {:ok, %{content_type: content_type, bytes: bytes, width: width, height: height}}
    end
  end

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
  def extension(content_type), do: Map.get(@extensions, content_type, ".bin")

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
  def content_type(extension) do
    extension = String.downcase(extension)

    Enum.find_value(@extensions, @octet, fn {type, ext} -> if ext == extension, do: type end)
  end

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
  def inline?(content_type), do: content_type in @inline

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
  #{@max_name} characters, and `"file"` when nothing is left.

  ## Examples

      iex> Kotoba.Attachments.clean_name("cat\\u0000.png")
      "cat.png"

      iex> Kotoba.Attachments.clean_name("a\\u202Egnp.exe")
      "agnp.exe"

  """
  @spec clean_name(term()) :: String.t()
  def clean_name(name) when is_binary(name) do
    name =
      if String.valid?(name),
        do: name,
        else: name |> String.codepoints() |> Enum.filter(&String.valid?/1) |> Enum.join()

    name
    |> String.replace(~r/[\p{Cc}\p{Cf}]/u, "")
    |> String.trim()
    |> String.slice(0, @max_name)
    |> case do
      "" -> "file"
      clean -> clean
    end
  end

  def clean_name(_name), do: "file"

  defp read_head(path) do
    case File.open(path, [:read, :binary], &IO.binread(&1, @head)) do
      {:ok, :eof} -> {:ok, ""}
      {:ok, {:error, reason}} -> {:error, reason}
      {:ok, head} -> {:ok, head}
      {:error, reason} -> {:error, reason}
    end
  end

  # The browser's type, without parameters, in lower case.
  defp claim(type) when is_binary(type) do
    type |> String.split(";", parts: 2) |> hd() |> String.trim() |> String.downcase()
  end

  defp claim(_type), do: ""

  defp other_type(<<"%PDF-", _rest::binary>>, _claim), do: "application/pdf"

  defp other_type(<<size::32, "ftyp", major::binary-size(4), _minor::32, rest::binary>>, _claim)
       when size >= 16 do
    cond do
      major in @not_video_brands -> @octet
      Enum.any?([major | brands(rest, size - 16)], &(&1 in @mp4_brands)) -> "video/mp4"
      true -> @octet
    end
  end

  defp other_type(<<0x1A, 0x45, 0xDF, 0xA3, rest::binary>> = _head, _claim) do
    if ebml_doc_type(rest) == "webm", do: "video/webm", else: @octet
  end

  defp other_type(<<"PK", 3, 4, _rest::binary>>, claim),
    do: if(claim in @zip_types, do: claim, else: "application/zip")

  defp other_type(<<0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, _rest::binary>>, claim),
    do: if(claim in @ole_types, do: claim, else: @octet)

  defp other_type(head, "text/plain") do
    if text?(head), do: "text/plain", else: @octet
  end

  defp other_type(_head, _claim), do: @octet

  # The compatible brands of an `ftyp` box: 4 bytes each, in `length` bytes.
  defp brands(rest, length) do
    available = min(length, byte_size(rest))
    whole = available - rem(available, 4)
    for <<brand::binary-size(4) <- binary_part(rest, 0, whole)>>, do: brand
  end

  # The EBML header: its size, then elements; the DocType element (ID 0x4282)
  # names the format. Sizes are variable-length integers.
  defp ebml_doc_type(rest) do
    with {size, body} <- vint(rest),
         true <- byte_size(body) >= size do
      doc_type(binary_part(body, 0, size))
    else
      _other -> nil
    end
  end

  defp doc_type(<<0x42, 0x82, rest::binary>>) do
    case element_value(rest) do
      {value, _next} -> value
      nil -> nil
    end
  end

  defp doc_type(<<id, rest::binary>>) when id >= 0x80, do: skip_element(rest)
  defp doc_type(<<id, _second, rest::binary>>) when id >= 0x40, do: skip_element(rest)
  defp doc_type(_other), do: nil

  defp skip_element(rest) do
    case element_value(rest) do
      {_value, next} -> doc_type(next)
      nil -> nil
    end
  end

  # The value of an element (after its ID): its size, then that many bytes.
  defp element_value(rest) do
    with {size, data} when byte_size(data) >= size <- vint(rest) do
      <<value::binary-size(size), next::binary>> = data
      {value, next}
    else
      _other -> nil
    end
  end

  # An EBML variable-length integer: the number of leading zero bits of the
  # first byte gives its length. Returns the value and the rest.
  defp vint(<<first, _rest::binary>> = data) when first > 0 do
    length = 9 - bit_length(first)

    case data do
      <<value::size(length * 8), rest::binary>> ->
        {value &&& (1 <<< (7 * length)) - 1, rest}

      _short ->
        nil
    end
  end

  defp vint(_data), do: nil

  defp bit_length(byte), do: byte |> Integer.digits(2) |> length()

  # The head can end inside a UTF-8 sequence: up to three bytes at the end
  # may be cut off.
  defp text?(head) do
    not String.contains?(head, <<0>>) and
      Enum.any?(0..min(3, byte_size(head)), fn cut ->
        String.valid?(binary_part(head, 0, byte_size(head) - cut)) and
          (cut == 0 or byte_size(head) == @head)
      end)
  end

  # PNG: the IHDR chunk comes first.
  defp image(<<0x89, "PNG\r\n", 0x1A, "\n", _length::32, "IHDR", w::32, h::32, _rest::binary>>),
    do: {"image/png", dimension(w), dimension(h)}

  defp image(<<0x89, "PNG\r\n", 0x1A, "\n", _rest::binary>>), do: {"image/png", nil, nil}

  defp image(<<"GIF8", v, "a", w::little-16, h::little-16, _rest::binary>>) when v in [?7, ?9],
    do: {"image/gif", dimension(w), dimension(h)}

  defp image(<<"RIFF", _size::little-32, "WEBP", chunk::binary>>) do
    {width, height} = webp(chunk)
    {"image/webp", width, height}
  end

  defp image(<<0xFF, 0xD8, 0xFF, rest::binary>>) do
    {width, height} = jpeg(<<0xFF, rest::binary>>)
    {"image/jpeg", width, height}
  end

  defp image(_head), do: nil

  defp webp(
         <<"VP8 ", _size::little-32, _frame::binary-size(3), 0x9D, 0x01, 0x2A, w::little-16,
           h::little-16, _rest::binary>>
       ) do
    {dimension(w &&& 0x3FFF), dimension(h &&& 0x3FFF)}
  end

  defp webp(<<"VP8L", _size::little-32, 0x2F, bits::little-32, _rest::binary>>) do
    {dimension((bits &&& 0x3FFF) + 1), dimension((bits >>> 14 &&& 0x3FFF) + 1)}
  end

  defp webp(<<"VP8X", _size::little-32, _flags::32, w::little-24, h::little-24, _rest::binary>>),
    do: {dimension(w + 1), dimension(h + 1)}

  defp webp(_chunk), do: {nil, nil}

  # JPEG: walk the markers up to a start-of-frame marker.
  defp jpeg(<<0xFF, marker, _length::16, _precision, h::16, w::16, _rest::binary>>)
       when marker in 0xC0..0xCF and marker not in [0xC4, 0xC8, 0xCC],
       do: {dimension(w), dimension(h)}

  defp jpeg(<<0xFF, 0xFF, rest::binary>>), do: jpeg(<<0xFF, rest::binary>>)

  defp jpeg(<<0xFF, marker, rest::binary>>) when marker in 0xD0..0xD9 or marker == 0x01,
    do: jpeg(rest)

  defp jpeg(<<0xFF, _marker, length::16, rest::binary>>) when length >= 2 do
    skip = length - 2

    case rest do
      <<_segment::binary-size(^skip), next::binary>> -> jpeg(next)
      _short -> {nil, nil}
    end
  end

  defp jpeg(_other), do: {nil, nil}

  defp dimension(value) when is_integer(value) and value > 0, do: value
  defp dimension(_value), do: nil
end
