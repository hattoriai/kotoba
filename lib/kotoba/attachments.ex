defmodule Kotoba.Attachments do
  @moduledoc """
  Server-side checks of an uploaded file, before it becomes an attachment
  node.

  The browser's content type is a claim. `describe/2` reads the start of
  the file:

    * A PNG, JPEG, GIF or WebP image gets the type that its bytes show, and
      its width and height when the header has them.
    * A file that the browser calls an image, but whose bytes are not one
      of these four formats (an SVG, say), becomes
      `application/octet-stream`, so that it renders as a download link
      and not as an image.
    * Any other file keeps the browser's type when it is a well-formed
      media type, else it becomes `application/octet-stream`.
  """

  import Bitwise

  alias Kotoba.Nodes.Attachment

  @octet "application/octet-stream"
  @head 65_536
  @max_name 200
  @media_type ~r/\A[a-z0-9][a-z0-9!#$&^_.+\-]{0,62}\/[a-z0-9][a-z0-9!#$&^_.+\-]{0,62}\z/

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
          nil -> {other_type(client_type), nil, nil}
        end

      {:ok, %{content_type: content_type, bytes: bytes, width: width, height: height}}
    end
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
      height: description.height
    }
  end

  @doc """
  Returns a file name for display: control characters removed, at most
  #{@max_name} characters, and `"file"` when nothing is left.

  ## Examples

      iex> Kotoba.Attachments.clean_name("cat\\u0000.png")
      "cat.png"

  """
  @spec clean_name(term()) :: String.t()
  def clean_name(name) when is_binary(name) do
    name =
      if String.valid?(name),
        do: name,
        else: name |> String.codepoints() |> Enum.filter(&String.valid?/1) |> Enum.join()

    name
    |> String.replace(~r/[\x{0000}-\x{001F}\x{007F}-\x{009F}]/u, "")
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

  defp other_type(type) when is_binary(type) do
    type = type |> String.trim() |> String.downcase()

    cond do
      String.starts_with?(type, "image/") -> @octet
      Regex.match?(@media_type, type) -> type
      true -> @octet
    end
  end

  defp other_type(_type), do: @octet

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
