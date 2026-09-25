defmodule Kotoba.Install.Edits do
  @moduledoc false
  # The edits of `mix kotoba.install`, as pure functions on the source of
  # each file. Each edit returns:
  #
  #   * `{:changed, source}` - the new source,
  #   * `:unchanged` - the file already has everything,
  #   * `{:manual, text}` - the edit cannot be made safely; `text` tells
  #     the person what to add.

  @type result :: {:changed, String.t()} | :unchanged | {:manual, String.t()}

  @js_import ~s(import { Kotoba } from "kotoba")
  @css_import ~s(@import "../../deps/kotoba/priv/static/kotoba.css";)
  @sumi_import ~s(/* @import "../../deps/kotoba/priv/static/kotoba-sumi.css"; */)

  ## assets/js/app.js

  @doc false
  @spec app_js(String.t()) :: result()
  def app_js(source) when is_binary(source) do
    # Any import that binds `Kotoba`, from "kotoba" or from another path.
    import? =
      Regex.match?(
        ~r/^import\s*(?:\{[^}]*\bKotoba\b[^}]*\}|Kotoba\b[^\n]*?)\s*from\s*["']/m,
        source
      )

    case hooks(source) do
      :error ->
        {:manual, app_js_manual(import?)}

      {:ok, with_hooks} ->
        new = if import?, do: with_hooks, else: add_js_import(with_hooks)
        if new == source, do: :unchanged, else: {:changed, new}
    end
  end

  @doc false
  @spec app_js_manual(boolean()) :: String.t()
  def app_js_manual(import? \\ false) do
    import_text =
      if import?, do: "", else: "Add the import to assets/js/app.js:\n\n    #{@js_import}\n\n"

    import_text <>
      """
      Add Kotoba to the hooks of the LiveSocket in assets/js/app.js:

          const liveSocket = new LiveSocket("/live", Socket, {
            params: {_csrf_token: csrfToken},
            hooks: {...colocatedHooks, Kotoba},
          })
      """
  end

  # After the line where the last top-level import statement ends (an
  # import can span several lines), else at the top.
  defp add_js_import(source) do
    code = mask(source)

    case Regex.scan(~r/^import(?=[\s{*"'])/m, code, return: :index) |> List.last() do
      nil ->
        @js_import <> "\n" <> source

      [{at, _length}] ->
        at = import_end(code, at)

        line_end =
          if newline = first_match(~r/\n/, rest(code, at)),
            do: at + elem(newline, 0),
            else: byte_size(code)

        splice(source, line_end, 0, "\n" <> @js_import)
    end
  end

  # The index after the module specifier of the import at `at`: its first
  # string, whose text the mask keeps as spaces between the quotes.
  defp import_end(code, at) do
    case Regex.run(~r/["']/, rest(code, at), return: :index) do
      [{open, 1}] ->
        quote_char = binary_part(code, at + open, 1)
        from = at + open + 1

        case :binary.match(code, quote_char, scope: {from, byte_size(code) - from}) do
          {close, 1} -> close + 1
          :nomatch -> byte_size(code)
        end

      nil ->
        byte_size(code)
    end
  end

  defp rest(code, at), do: binary_part(code, at, byte_size(code) - at)

  # Finds the `hooks` of the options of `new LiveSocket(...)`, and adds
  # `Kotoba` to them. Returns `{:ok, source}` (the same source when Kotoba
  # is already there) or `:error`.
  defp hooks(source) do
    code = mask(source)

    with {call, call_length} <- first_match(~r/\bnew\s+LiveSocket\s*\(/, code),
         open when is_integer(open) <- options_open(code, call + call_length),
         close when is_integer(close) <- close(code, open) do
      options = binary_part(code, open + 1, close - open - 1)

      top = top_level(options)

      cond do
        other_hooks_key?(source, open + 1, top) ->
          :error

        match = first_match(~r/(?<![\w$.])hooks\s*:\s*/, top) ->
          hooks_at(source, code, open, match)

        true ->
          {:ok, insert_hooks_key(source, open, options)}
      end
    else
      _other -> :error
    end
  end

  defp hooks_at(source, code, open, {at, length}),
    do: hooks_value(source, code, open + 1 + at + length)

  # A quoted `"hooks":` key, or the `hooks` shorthand, at the top level of
  # the options: the edit cannot see through it, so the person adds Kotoba.
  defp other_hooks_key?(source, offset, top) do
    quoted =
      ~r/(["'])\s{5}\1\s*:/
      |> Regex.scan(top, return: :index)
      |> Enum.any?(fn [{at, _length} | _group] ->
        Regex.match?(~r/^["']hooks["']/, binary_part(source, offset + at, 7))
      end)

    quoted or Regex.match?(~r/(?:^|,)\s*hooks\s*(?:,|$)/, top)
  end

  # The first `{` among the arguments of the call, before its `)`.
  defp options_open(code, from), do: scan_to_brace(code, from, 0)

  defp scan_to_brace(code, at, _depth) when at >= byte_size(code), do: nil

  defp scan_to_brace(code, at, depth) do
    case :binary.at(code, at) do
      ?{ when depth == 0 -> at
      char when char in [?(, ?[, ?{] -> scan_to_brace(code, at + 1, depth + 1)
      ?) when depth == 0 -> nil
      char when char in [?), ?], ?}] -> scan_to_brace(code, at + 1, depth - 1)
      _char -> scan_to_brace(code, at + 1, depth)
    end
  end

  defp insert_hooks_key(source, open, options) do
    {text, replaced} =
      cond do
        String.trim(options) == "" ->
          {"hooks: {Kotoba}", byte_size(options)}

        String.contains?(options, "\n") ->
          [_first, line | _rest] = String.split(options, "\n")
          [indent] = Regex.run(~r/^[ \t]*/, line)
          {"\n" <> indent <> "hooks: {Kotoba},", 0}

        true ->
          {"hooks: {Kotoba}, ", 0}
      end

    splice(source, open + 1, replaced, text)
  end

  defp hooks_value(source, code, at) do
    rest = binary_part(code, at, byte_size(code) - at)

    cond do
      String.starts_with?(rest, "{") ->
        close = close(code, at)
        inner = binary_part(source, at + 1, close - at - 1)

        if Regex.match?(~r/(?<![\w$.])Kotoba\b/, binary_part(code, at + 1, close - at - 1)),
          do: {:ok, source},
          else: {:ok, splice(source, at + 1, close - at - 1, add_to_object(inner))}

      match = Regex.run(~r/^([A-Za-z_$][\w$]*)\s*(?=[,}\n])/, rest) ->
        [whole, name] = match

        if Regex.match?(
             ~r/\b#{Regex.escape(name)}\s*(\.\s*Kotoba|\[\s*["']Kotoba["']\s*\])\s*=/,
             code
           ),
           do: {:ok, source},
           else:
             {:ok,
              splice(source, at, byte_size(String.trim_trailing(whole)), "{...#{name}, Kotoba}")}

      true ->
        :error
    end
  end

  defp add_to_object(inner) do
    trimmed = String.trim_trailing(inner)
    trailing = binary_part(inner, byte_size(trimmed), byte_size(inner) - byte_size(trimmed))

    cond do
      String.trim(inner) == "" ->
        "Kotoba"

      String.contains?(inner, "\n") ->
        last = trimmed |> String.split("\n") |> List.last()
        [indent] = Regex.run(~r/^[ \t]*/, last)
        comma = if String.ends_with?(trimmed, ","), do: "", else: ","
        trimmed <> comma <> "\n" <> indent <> "Kotoba," <> trailing

      String.ends_with?(trimmed, ",") ->
        trimmed <> " Kotoba" <> trailing

      true ->
        trimmed <> ", Kotoba" <> trailing
    end
  end

  defp splice(source, at, length, text) do
    binary_part(source, 0, at) <>
      text <>
      binary_part(source, at + length, byte_size(source) - at - length)
  end

  # Replaces the text of strings and comments with spaces, byte for byte,
  # so that the positions stay the same and brackets in them do not count.
  defp mask(source), do: source |> mask(:code, []) |> IO.iodata_to_binary()

  defp mask(<<>>, _state, acc), do: Enum.reverse(acc)
  defp mask(<<"//", rest::binary>>, :code, acc), do: mask(rest, :line, ["  " | acc])
  defp mask(<<"/*", rest::binary>>, :code, acc), do: mask(rest, :block, ["  " | acc])

  defp mask(<<q, rest::binary>>, :code, acc) when q in [?", ?', ?`],
    do: mask(rest, {:string, q}, [q | acc])

  defp mask(<<c, rest::binary>>, :code, acc), do: mask(rest, :code, [c | acc])
  defp mask(<<?\n, rest::binary>>, :line, acc), do: mask(rest, :code, [?\n | acc])
  defp mask(<<"*/", rest::binary>>, :block, acc), do: mask(rest, :code, ["  " | acc])
  defp mask(<<?\n, rest::binary>>, :block, acc), do: mask(rest, :block, [?\n | acc])

  defp mask(<<_c, rest::binary>>, state, acc) when state in [:line, :block],
    do: mask(rest, state, [?\s | acc])

  defp mask(<<?\\, _c, rest::binary>>, {:string, _q} = state, acc),
    do: mask(rest, state, ["  " | acc])

  defp mask(<<q, rest::binary>>, {:string, q}, acc), do: mask(rest, :code, [q | acc])
  defp mask(<<?\n, rest::binary>>, {:string, _q} = state, acc), do: mask(rest, state, [?\n | acc])
  defp mask(<<_c, rest::binary>>, {:string, _q} = state, acc), do: mask(rest, state, [?\s | acc])

  # The index of the bracket that closes the one at `open`, in masked code.
  defp close(code, open), do: close(code, open + 1, 1)
  defp close(code, at, _depth) when at >= byte_size(code), do: nil

  defp close(code, at, depth) do
    case :binary.at(code, at) do
      char when char in [?(, ?[, ?{] -> close(code, at + 1, depth + 1)
      char when char in [?), ?], ?}] and depth == 1 -> at
      char when char in [?), ?], ?}] -> close(code, at + 1, depth - 1)
      _char -> close(code, at + 1, depth)
    end
  end

  # Masked code with the text inside nested brackets replaced by spaces.
  defp top_level(code) do
    {chars, _depth} =
      code
      |> :binary.bin_to_list()
      |> Enum.map_reduce(0, fn
        char, depth when char in [?(, ?[, ?{] -> {if(depth == 0, do: char, else: ?\s), depth + 1}
        char, depth when char in [?), ?], ?}] -> {if(depth == 1, do: char, else: ?\s), depth - 1}
        ?\n, depth -> {?\n, depth}
        char, 0 -> {char, 0}
        _char, depth -> {?\s, depth}
      end)

    :binary.list_to_bin(chars)
  end

  defp first_match(regex, text) do
    case Regex.run(regex, text, return: :index) do
      [{at, length} | _groups] -> {at, length}
      nil -> nil
    end
  end

  ## assets/css/app.css

  @doc false
  @spec app_css(String.t()) :: result()
  def app_css(source) when is_binary(source) do
    # The Sumi line comes only with the kotoba.css import, so a person who
    # removed it does not get it back.
    if Regex.match?(~r/kotoba\/priv\/static\/kotoba\.css/, source) do
      :unchanged
    else
      lines = String.split(source, "\n")

      added =
        if String.contains?(source, "kotoba-sumi.css"),
          do: [@css_import],
          else: [@css_import, @sumi_import]

      {head, tail} = Enum.split(lines, css_insert_at(lines))
      {:changed, Enum.join(head ++ added ++ tail, "\n")}
    end
  end

  @doc false
  @spec app_css_manual() :: String.t()
  def app_css_manual do
    """
    Add the editor style sheet to assets/css/app.css, and the Sumi theme if you want it:

        #{@css_import}
        #{@sumi_import}
    """
  end

  # After the last top-level @import, else after a @charset, else at the top.
  defp css_insert_at(lines) do
    case last_index(lines, &Regex.match?(~r/^@import\b/, &1)) do
      nil ->
        case last_index(lines, &Regex.match?(~r/^@charset\b/, &1)) do
          nil -> 0
          index -> index + 1
        end

      index ->
        index + 1
    end
  end

  ## config/config.exs

  @doc false
  @spec config(String.t(), atom() | String.t()) :: result()
  def config(source, app \\ :my_app) when is_binary(source) do
    if storage_configured?(source) do
      :unchanged
    else
      block = config_block(app)

      lines = String.split(source, "\n")

      new =
        case Enum.find_index(lines, &Regex.match?(~r/^import_config\b/, &1)) do
          nil ->
            String.trim_trailing(source) <> "\n\n" <> block

          index ->
            # Above the comment that goes with `import_config`.
            at =
              index -
                (lines
                 |> Enum.take(index)
                 |> Enum.reverse()
                 |> Enum.take_while(&String.starts_with?(&1, "#"))
                 |> length())

            {head, tail} = Enum.split(lines, at)
            Enum.join(head ++ String.split(block, "\n") ++ tail, "\n")
        end

      {:changed, new}
    end
  end

  @doc false
  @spec config_block(atom() | String.t()) :: String.t()
  def config_block(app \\ :my_app) do
    """
    # Kotoba stores the files of the editor's uploads with this adapter.
    # Give it a directory in the :prod block of config/runtime.exs, an
    # absolute path outside the release:
    #
    #     if config_env() == :prod do
    #       config :kotoba, Kotoba.Storage.Local,
    #         root: System.get_env("KOTOBA_UPLOADS", "/var/lib/#{app}/uploads"),
    #         url_prefix: "/uploads/kotoba"
    #     end
    #
    # and one for development in config/dev.exs:
    #
    #     config :kotoba, Kotoba.Storage.Local, root: Path.expand("../tmp/uploads", __DIR__)
    config :kotoba, storage: Kotoba.Storage.Local
    """
  end

  # A `config :kotoba, ...` keyword list (not `config :kotoba, Module, ...`)
  # with a `storage:` key.
  defp storage_configured?(source) do
    ~r/^config\s+:kotoba\s*,(?!\s*[A-Z])[^\n]*(?:\n[ \t]+[^\n]*)*/m
    |> Regex.scan(source)
    |> Enum.any?(fn [statement] -> Regex.match?(~r/(?<![\w_])storage:/, statement) end)
  end

  @doc false
  @spec node_path?(String.t()) :: boolean()
  def node_path?(config_source) do
    Regex.match?(~r/"NODE_PATH"\s*=>[^\n]*deps/, config_source)
  end

  ## Diffs

  @doc false
  @spec diff(String.t(), String.t(), String.t()) :: String.t()
  def diff(path, old, new) do
    changes = List.myers_difference(String.split(old, "\n"), String.split(new, "\n"))
    last = length(changes) - 1

    lines =
      changes
      |> Enum.with_index()
      |> Enum.flat_map(fn
        {{:eq, lines}, index} -> context(lines, index == 0, index == last)
        {{:del, lines}, _index} -> Enum.map(lines, &("- " <> &1))
        {{:ins, lines}, _index} -> Enum.map(lines, &("+ " <> &1))
      end)

    Enum.join(["--- #{path}", "+++ #{path}" | lines], "\n") <> "\n"
  end

  # Two lines of context around each change.
  defp context(lines, first?, last?) do
    lines
    |> shown(first?, last?)
    |> Enum.map(fn
      :gap -> "  ..."
      line -> "  " <> line
    end)
  end

  defp shown(_lines, true, true), do: []

  defp shown(lines, true, false),
    do: if(length(lines) > 2, do: [:gap | Enum.take(lines, -2)], else: lines)

  defp shown(lines, false, true),
    do: if(length(lines) > 2, do: Enum.take(lines, 2) ++ [:gap], else: lines)

  defp shown(lines, false, false) when length(lines) <= 5, do: lines
  defp shown(lines, false, false), do: Enum.take(lines, 2) ++ [:gap | Enum.take(lines, -2)]

  defp last_index(list, fun) do
    list
    |> Enum.with_index()
    |> Enum.filter(fn {item, _index} -> fun.(item) end)
    |> List.last()
    |> case do
      nil -> nil
      {_item, index} -> index
    end
  end
end
