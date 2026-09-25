defmodule Kotoba.Nodes.Attachment do
  @moduledoc """
  A file in the document (type `"attachment"`), for example an image.

    * `key` - the storage key of the file.
    * `url` - the URL of the file.
    * `name` - the file name.
    * `content_type` - the media type, for example `"image/png"`.
    * `bytes` - the size of the file.
    * `width` and `height` - the size of an image in pixels, or `nil`.
  """
  use Kotoba.Node, type: "attachment", kind: :decorator

  field :key, :string, required: true
  field :url, :string, required: true
  field :name, :string, required: true
  field :content_type, :string, required: true
  field :bytes, :integer, required: true
  field :width, :integer, omit_nil: true
  field :height, :integer, omit_nil: true

  @doc """
  Returns `true` when the attachment is an image.

  ## Examples

      iex> Kotoba.Nodes.Attachment.image?(%Kotoba.Nodes.Attachment{content_type: "image/png"})
      true

  """
  @spec image?(t()) :: boolean()
  def image?(%__MODULE__{content_type: "image/" <> _subtype}), do: true
  def image?(%__MODULE__{}), do: false
end
