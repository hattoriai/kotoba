defmodule Kotoba do
  @moduledoc """
  Kotoba (言葉) adds rich text to a Phoenix app.

  It ships a prebuilt editor, an Ecto content type, and safe rendering, so a
  Phoenix app gets a rich-text field with no Node.js build step of its own.

  See the `README` for setup and usage.
  """

  @external_resource "mix.exs"
  @version Mix.Project.config()[:version]

  @doc """
  Returns the current Kotoba version.

  ## Examples

      iex> Kotoba.version()
      "#{@version}"

  """
  @spec version() :: String.t()
  def version, do: @version
end
