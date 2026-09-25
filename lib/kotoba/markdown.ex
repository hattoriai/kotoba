defmodule Kotoba.Markdown do
  @moduledoc false
  # Small helpers for the Markdown output of the built-in nodes.

  # The block syntax at the start of a line (after at most three spaces):
  # an ATX heading, a quote, a bullet, a thematic break or setext underline
  # of `-` or `=`, and an ordered list marker. `*`, `_`, `` ` `` and `~`
  # (bullets, rules and fences too) are escaped everywhere by the inline
  # rule.
  @line_start ~r/^([ \t]{0,3})(?:(\d{1,9})([.)])(?=[ \t]|$)|(\#{1,6}(?=[ \t]|$)|>|[-+](?=[ \t]|$)|-(?=[- \t]*$)|=(?=[= \t]*$)))/m

  @doc """
  Escapes the characters that have a meaning in inline Markdown, and the
  block syntax at the start of a line, so that the text reads as text.
  """
  @spec escape(String.t()) :: String.t()
  def escape(text) do
    text
    |> String.replace(~r/[\\`*_\[\]~<]/, "\\\\\\0")
    |> then(
      &Regex.replace(@line_start, &1, fn _all, lead, digits, mark, symbol ->
        escape_line_start(lead, digits, mark, symbol)
      end)
    )
  end

  defp escape_line_start(lead, "", _mark, symbol), do: lead <> "\\" <> symbol
  defp escape_line_start(lead, digits, mark, _symbol), do: lead <> digits <> "\\" <> mark

  @doc "Returns a code span with a fence that is longer than the backticks in the text."
  @spec code_span(String.t()) :: String.t()
  def code_span(text) do
    fence = String.duplicate("`", longest_run(text, "`") + 1)
    pad = if String.starts_with?(text, "`") or String.ends_with?(text, "`"), do: " ", else: ""
    fence <> pad <> text <> pad <> fence
  end

  @doc "Returns the length of the longest run of `char` in the text."
  @spec longest_run(String.t(), String.t()) :: non_neg_integer()
  def longest_run(text, char) do
    ~r/#{Regex.escape(char)}+/
    |> Regex.scan(text)
    |> Enum.map(fn [run] -> String.length(run) end)
    |> Enum.max(fn -> 0 end)
  end

  @doc "Wraps the text in a marker, with the outer white space outside the marker."
  @spec wrap(String.t(), String.t()) :: String.t()
  def wrap(text, marker) do
    case Regex.run(~r/\A(\s*)(.*?)(\s*)\z/su, text, capture: :all_but_first) do
      [_lead, "", _trail] -> text
      [lead, core, trail] -> lead <> marker <> core <> marker <> trail
    end
  end

  @doc "Returns a URL for a Markdown link destination."
  @spec url(String.t()) :: String.t()
  def url(url) do
    url
    |> String.replace(" ", "%20")
    |> String.replace("(", "%28")
    |> String.replace(")", "%29")
  end
end
