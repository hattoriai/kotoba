defmodule Kotoba.Prompts do
  @moduledoc """
  Prompts: a trigger character in the editor opens a menu of results, for
  example `@` for people. A result inserts a mention, text (an emoji, a
  snippet) or a node of the app. See the [Prompts](prompts.md) guide.

  A prompt list has one of two forms:

      # The first prompt has the trigger "@", the second has "#".
      [people: &MyApp.People.search/1, work: &MyApp.Work.search/1]

      # Each trigger given explicitly.
      [{"@", :people, &MyApp.People.search/1}, {"#", :work, &MyApp.Work.search/1}]

  A trigger is exactly one character that is not white space. The name of a
  prompt (an atom or a string) is the `kind` of the mentions that it
  inserts.

  ## A prompt

  A prompt is a search callback, a callback with options, or a keyword list
  with the callback (`:search`) or a list of items (`:items`):

      people: &MyApp.People.search/1
      people: {&MyApp.People.search/1, label: "People in the workshop"}
      people: [search: &MyApp.People.search/1, spaces: true, min_length: 2]
      emoji: [items: MyApp.Emoji.items(), insert: :text]

  The options:

    * `:label` - the accessible name of the menu, "<name> suggestions"
      otherwise. A non-empty string of at most 200 characters.
    * `:spaces` - `true` to let the query have spaces ("Ada Lovelace"). A
      query ends at two spaces in a row, and cannot start with a space. The
      default is `false`: a space closes the menu.
    * `:min_length` - the characters of the query before the first search
      (0 to the `:max_length`, default 0). A shorter query shows "Keep
      typing".
    * `:max_length` - the longest query, 1 to 200 characters (default 64).
      A longer one closes the menu.
    * `:insert` - what a result inserts: `:mention` (the default), `:text`
      (the item's `:text`, or its label), `{:node, type}`: a node of the
      editor of that Lexical type, from the item's `:attrs`, or `:command`:
      the item's command, see "The insert menu" below.
    * `:with_text` - for an `insert: :command` prompt, what a block command
      does in a block that has text: `:below` (the default) makes a new
      block below it, `:turn_into` turns the block into the new one. In an
      empty paragraph it always turns it into the new block.
    * `:async` - `true` to run the search in a task of the LiveView, so
      that a slow search does not block it. The LiveView then needs a
      `handle_async/3` clause, see `Kotoba.Live.handle_prompt_async/3`. The
      callback of an async prompt takes only the query (arity 1).

  ## Searches

  A `:search` callback gets the query (the text after the trigger) and
  returns a list of items. A callback with arity 2 also gets the socket,
  for example to scope the search to the current user:

      [people: fn query, socket -> MyApp.People.search(socket.assigns.scope, query) end]

  A callback that raises, exits or throws, or that returns anything but a
  list, fails: `search/3` logs a warning with the prompt name, and the
  editor says "Results did not load". A callback runs in the LiveView
  process, so a slow one blocks the LiveView while it runs (see `:async`).

  ## Items

  With `:items`, the editor has the items (at most 500) and filters them as
  the person types, with no request to the server: each word of the query
  must start a word of the label or the hint, with no regard to case or
  accents.

  An item is a map with an `:id` (a string or an integer), a `:label` (a
  string) and these optional keys, with atom or string keys, or an
  `{id, label}` tuple:

    * `:hint` - a string shown next to the label;
    * `:text` - the text that an `insert: :text` prompt inserts (the label
      when there is none);
    * `:attrs` - the attributes of the node that an `insert: {:node, type}`
      prompt inserts: a map that encodes to JSON in at most 2048 bytes.

  Items that do not have this shape are dropped, and at most 50 results go
  to the menu. Control characters (such as a tab or a line break) are
  removed from the id, the label, the hint and the text.

  ## The insert menu

  A prompt with `insert: :command` is an insert menu: its items run a
  command of the editor on the block of the caret, as one undo step, after
  the trigger and the query are removed:

      prompts={[{"/", :insert, insert: :command}]}

  Its items are the app's. Two atoms in its `:items` stand for the editor's
  own, at their place: `:builtin`, the built-in items of the field's
  features (`commands/1`), and `:extensions`, the insert items of the
  editor's extensions. With no `:items` and no `:search`, the items are
  `[:builtin, :extensions]`. An item of an insert menu has one of:

    * `:command` - a built-in command (`commands/1` lists them: "h2",
      "table", "upload"...), the block of an extension (`"ext:<type>"`), or
      an extension's insert item (`"<extension>:<command>"`);
    * `:node` - a node to insert, as a document has it (a map with a
      `"type"`, at most 2048 bytes in JSON): an embed, a node of the app;
    * `:text` - text to insert (a snippet);
    * `:assist` - the action of a suggestion to ask for, as the Assist menu
      does (`kotoba:assist`, with the text of the block as `"block"`): the
      app streams the answer, which the person accepts or rejects. Only in
      an editor with `assist`. See the [Suggestions](suggestions.md) guide.

  and may have a `:group` (the menu shows a heading where the group
  changes: "Basic", "Media", "Embeds", the app's own) and `:keywords`, more
  words that find it (`/title` finds Heading 1). The editor leaves out an
  item whose command or node needs a feature the field does not have.

  The component `Kotoba.Components.kotoba/1` sends the triggers, the names,
  the options and the items to the editor; the search callbacks stay in the
  LiveView. `Kotoba.Live.handle_prompt/3` runs them.
  """

  require Logger

  @max_items 50
  @max_local_items 500
  @max_query 64
  @max_query_limit 200
  @max_label 200
  @max_name 200
  @max_attrs 2048
  @positional ["@", "#"]
  @options [
    :search,
    :items,
    :label,
    :spaces,
    :min_length,
    :max_length,
    :insert,
    :with_text,
    :async
  ]
  @markers [:builtin, :extensions]
  @command ~r/\A[a-z][a-z0-9-]{0,99}(:[A-Za-z][A-Za-z0-9_-]{0,99})?\z/
  @max_keywords 20
  @node_type ~r/\A[A-Za-z][A-Za-z0-9_-]{0,99}\z/

  @typedoc "An item as the editor receives it."
  @type item :: %{
          required(:id) => String.t(),
          required(:label) => String.t(),
          optional(:hint) => String.t(),
          optional(:text) => String.t(),
          optional(:attrs) => map(),
          optional(:command) => String.t(),
          optional(:node) => map(),
          optional(:group) => String.t(),
          optional(:keywords) => [String.t()],
          optional(:assist) => String.t()
        }

  @typedoc "A prompt callback."
  @type callback :: (String.t() -> list()) | (String.t(), Phoenix.LiveView.Socket.t() -> list())

  @typedoc "What a result inserts."
  @type insert :: :mention | :text | {:node, String.t()} | :command

  @typedoc "A prompt: a callback, a callback with options, or a keyword list."
  @type spec :: callback() | {callback(), keyword()} | keyword()

  @typedoc "A prompt list, in one of the two forms of the module doc."
  @type prompts :: [
          {atom() | String.t(), spec()} | {String.t(), atom() | String.t(), spec()}
        ]

  @typedoc "A prompt, normalized: `{trigger, name, callback}`."
  @type prompt :: {String.t(), String.t(), callback()}

  @typedoc "A prompt with its options, normalized."
  @type options :: %{
          trigger: String.t(),
          name: String.t(),
          search: callback(),
          items: [item() | :builtin | :extensions] | nil,
          label: String.t() | nil,
          spaces: boolean(),
          min_length: non_neg_integer(),
          max_length: pos_integer(),
          insert: insert(),
          with_text: :below | :turn_into,
          async: boolean()
        }

  @doc """
  Normalizes a prompt list to `{trigger, name, callback}` tuples. The
  callback of an `:items` prompt filters its items.

  Raises `ArgumentError` when the list is not valid: a trigger that is not
  one character, a name or a trigger that is given twice, a callback that
  is not a function of arity 1 or 2, an option that is not one of the
  module doc or that has a value that is not valid, more than two prompts
  without explicit triggers, or the two forms mixed.

  ## Examples

      iex> [{trigger, name, _fun}] = Kotoba.Prompts.normalize(people: fn _query -> [] end)
      iex> {trigger, name}
      {"@", "people"}

  """
  @spec normalize(prompts() | nil) :: [prompt()]
  def normalize(prompts) do
    prompts |> specs() |> Enum.map(&{&1.trigger, &1.name, &1.search})
  end

  @doc """
  Normalizes a prompt list to its prompts with their options (see
  `normalize/1` for the errors).
  """
  @spec specs(prompts() | nil) :: [options()]
  def specs(nil), do: []
  def specs([]), do: []

  def specs(prompts) when is_list(prompts) do
    normalized =
      cond do
        Enum.all?(prompts, &match?({_name, _spec}, &1)) ->
          positional(prompts)

        Enum.all?(prompts, &match?({_trigger, _name, _spec}, &1)) ->
          Enum.map(prompts, &explicit/1)

        true ->
          invalid!(prompts, "use [name: fun] or [{trigger, name, fun}], not both")
      end

    check_unique!(normalized, :trigger)
    check_unique!(normalized, :name)
    normalized
  end

  def specs(other), do: invalid!(other, "a prompt list must be a list")

  defp positional(prompts) when length(prompts) > length(@positional) do
    invalid!(prompts, "give each trigger explicitly for more than two prompts")
  end

  defp positional(prompts) do
    prompts
    |> Enum.zip(@positional)
    |> Enum.map(fn {{name, spec}, trigger} -> explicit({trigger, name, spec}) end)
  end

  defp explicit({trigger, name, spec} = prompt) do
    unless trigger?(trigger), do: invalid!(prompt, "a trigger must be one character")

    unless name?(name),
      do:
        invalid!(
          prompt,
          "a name must be an atom or a non-empty string of at most #{@max_name} characters"
        )

    opts = options!(prompt, spec)
    Map.merge(%{trigger: trigger, name: to_string(name)}, opts)
  end

  # The options of a spec: a callback, `{callback, opts}` or a keyword list.
  defp options!(prompt, fun) when is_function(fun), do: options!(prompt, search: fun)

  defp options!(prompt, {fun, opts}) when is_list(opts) do
    unless Keyword.keyword?(opts), do: invalid!(prompt, "the options must be a keyword list")

    if Keyword.has_key?(opts, :search) or Keyword.has_key?(opts, :items),
      do: invalid!(prompt, "give :search or :items in a keyword list, not with a callback")

    options!(prompt, [{:search, fun} | opts])
  end

  defp options!(prompt, opts) when is_list(opts) and opts != [] do
    unless Keyword.keyword?(opts), do: invalid!(prompt, "a prompt must be a callback or options")

    case Enum.find(Keyword.keys(opts), &(&1 not in @options)) do
      nil -> :ok
      key -> invalid!(prompt, "unknown option #{inspect(key)}, use one of #{inspect(@options)}")
    end

    if length(Keyword.keys(opts)) != length(Enum.uniq(Keyword.keys(opts))),
      do: invalid!(prompt, "each option must be given once")

    max_length = integer!(prompt, opts, :max_length, @max_query, 1..@max_query_limit)
    async = boolean!(prompt, opts, :async)
    insert = insert!(prompt, Keyword.get(opts, :insert, :mention))
    {search, items} = source!(prompt, opts, async, insert)

    %{
      search: search,
      items: items,
      label: label!(prompt, opts),
      spaces: boolean!(prompt, opts, :spaces),
      min_length: integer!(prompt, opts, :min_length, 0, 0..max_length),
      max_length: max_length,
      insert: insert,
      with_text: with_text!(prompt, opts, insert),
      async: async
    }
  end

  defp options!(prompt, _spec),
    do: invalid!(prompt, "a prompt must be a callback, {callback, opts} or options")

  defp source!(prompt, opts, async, insert) do
    case {Keyword.fetch(opts, :search), Keyword.fetch(opts, :items)} do
      {{:ok, fun}, :error} -> {search!(prompt, fun, async), nil}
      {:error, {:ok, items}} -> local_items!(prompt, items, async, insert)
      # An insert menu with no items has the editor's own.
      {:error, :error} when insert == :command -> local_items!(prompt, @markers, async, insert)
      _other -> invalid!(prompt, "a prompt has a :search callback or :items, and not both")
    end
  end

  defp with_text!(prompt, opts, insert) do
    case Keyword.fetch(opts, :with_text) do
      :error ->
        :below

      {:ok, value} when value in [:below, :turn_into] and insert == :command ->
        value

      {:ok, _value} ->
        invalid!(prompt, ":with_text is :below or :turn_into, with insert: :command")
    end
  end

  defp search!(prompt, fun, async) do
    unless is_function(fun, 1) or is_function(fun, 2),
      do: invalid!(prompt, "a callback must be a function of arity 1 or 2")

    if async and not is_function(fun, 1),
      do: invalid!(prompt, "the callback of an async prompt must have arity 1")

    fun
  end

  defp local_items!(prompt, items, async, insert) do
    unless is_list(items), do: invalid!(prompt, "the items of a prompt must be a list")
    if async, do: invalid!(prompt, "a prompt with :items is not async")

    if insert != :command and Enum.any?(items, &(&1 in @markers)),
      do: invalid!(prompt, ":builtin and :extensions are items of an insert: :command prompt")

    # The editor's own items (:builtin, :extensions) stay as atoms, once each.
    items =
      items
      |> Enum.flat_map(fn
        marker when marker in @markers -> [marker]
        other -> item(other)
      end)
      |> Enum.uniq_by(fn
        marker when is_atom(marker) -> marker
        item -> item.id
      end)
      |> Enum.take(@max_local_items)

    own = Enum.reject(items, &is_atom/1)
    {fn query -> filter(own, query) end, items}
  end

  defp label!(prompt, opts) do
    case Keyword.fetch(opts, :label) do
      :error ->
        nil

      {:ok, label} ->
        unless label?(label),
          do:
            invalid!(
              prompt,
              "a label must be a non-empty string of at most #{@max_name} characters"
            )

        label
    end
  end

  defp boolean!(prompt, opts, key) do
    case Keyword.get(opts, key, false) do
      value when is_boolean(value) -> value
      _other -> invalid!(prompt, "#{inspect(key)} must be true or false")
    end
  end

  defp integer!(prompt, opts, key, default, first..last//1) do
    case Keyword.get(opts, key, default) do
      value when is_integer(value) and value >= first and value <= last ->
        value

      _other ->
        invalid!(prompt, "#{inspect(key)} must be an integer from #{first} to #{last}")
    end
  end

  defp insert!(_prompt, insert) when insert in [:mention, :text, :command], do: insert

  defp insert!(prompt, {:node, type}) when is_binary(type) do
    if Regex.match?(@node_type, type),
      do: {:node, type},
      else: invalid!(prompt, "the node type #{inspect(type)} is not a Lexical node type")
  end

  defp insert!(prompt, _insert),
    do: invalid!(prompt, ":insert must be :mention, :text, {:node, type} or :command")

  defp label?(label) when is_binary(label) do
    String.valid?(label) and String.trim(label) != "" and String.length(label) <= @max_name and
      not String.match?(label, ~r/\p{Cc}/u)
  end

  defp label?(_label), do: false

  defp trigger?(trigger) when is_binary(trigger) do
    String.valid?(trigger) and length(String.to_charlist(trigger)) == 1 and
      not String.match?(trigger, ~r/\s/u)
  end

  defp trigger?(_trigger), do: false

  defp name?(name) when is_atom(name) and not is_nil(name) and not is_boolean(name),
    do: String.length(Atom.to_string(name)) <= @max_name

  defp name?(name) when is_binary(name),
    do: String.trim(name) != "" and String.length(name) <= @max_name

  defp name?(_name), do: false

  defp check_unique!(prompts, key) do
    values = Enum.map(prompts, &Map.fetch!(&1, key))

    if length(Enum.uniq(values)) != length(values),
      do: invalid!(values, "each #{key} must be given once")
  end

  defp invalid!(value, message),
    do: raise(ArgumentError, "invalid Kotoba prompts #{inspect(value)}: #{message}")

  @doc """
  Returns the map from trigger to name that the editor reads
  (`data-prompts`).

  ## Examples

      iex> Kotoba.Prompts.triggers(people: fn _ -> [] end, work: fn _ -> [] end)
      %{"#" => "work", "@" => "people"}

  """
  @spec triggers(prompts() | nil) :: %{String.t() => String.t()}
  def triggers(prompts) do
    prompts |> specs() |> Map.new(&{&1.trigger, &1.name})
  end

  @doc """
  Returns the map from name to label, for the prompts that have a label,
  that the editor reads (`data-prompt-labels`).

  ## Examples

      iex> Kotoba.Prompts.labels(people: {fn _ -> [] end, label: "People"}, work: fn _ -> [] end)
      %{"people" => "People"}

  """
  @spec labels(prompts() | nil) :: %{String.t() => String.t()}
  def labels(prompts) do
    for %{name: name, label: label} <- specs(prompts), label != nil, into: %{}, do: {name, label}
  end

  @doc """
  Returns the options that the editor reads (`data-prompt-config`): for each
  prompt with an option that is not the default, a map of the options that
  are not, and the items of an `:items` prompt.

  ## Examples

      iex> Kotoba.Prompts.config(
      ...>   people: [search: fn _ -> [] end, spaces: true],
      ...>   emoji: [items: [%{id: "tada", label: "tada", text: "🎉"}], insert: :text]
      ...> )
      %{
        "emoji" => %{insert: "text", items: [%{id: "tada", label: "tada", text: "🎉"}]},
        "people" => %{spaces: true}
      }

  """
  @spec config(prompts() | nil, keyword()) :: %{String.t() => map()}
  def config(prompts, context \\ []) do
    prompts
    |> specs()
    |> Enum.map(&{&1.name, spec_config(&1, context)})
    |> Enum.reject(fn {_name, config} -> config == %{} end)
    |> Map.new()
  end

  defp spec_config(spec, context) do
    {items, extensions_at} = expand(spec.items, context)

    [
      spaces: spec.spaces,
      minLength: spec.min_length != 0 && spec.min_length,
      maxLength: spec.max_length != @max_query && spec.max_length,
      insert: insert_config(spec.insert),
      nodeType: match?({:node, _type}, spec.insert) && elem(spec.insert, 1),
      withText: spec.with_text == :turn_into && "turn_into",
      items: items,
      extensionsAt: extensions_at
    ]
    |> Enum.reject(fn {_key, value} -> value in [false, nil] end)
    |> Map.new()
  end

  # The items of an insert menu: :builtin becomes the built-in items, and
  # :extensions the place of the extensions' items, which the editor has.
  defp expand(nil, _context), do: {nil, nil}

  defp expand(items, context) do
    Enum.reduce(items, {[], nil}, fn
      :builtin, {acc, at} -> {acc ++ commands(context), at}
      :extensions, {acc, _at} -> {acc, length(acc)}
      item, {acc, at} -> {acc ++ [item], at}
    end)
  end

  defp insert_config(:mention), do: nil
  defp insert_config(:text), do: "text"
  defp insert_config({:node, _type}), do: "node"
  defp insert_config(:command), do: "command"

  # The built-in items of an insert menu: {command, label, group, feature, keywords}.
  @commands [
    {"paragraph", "Text", "Basic", nil, ~w(paragraph plain body)},
    {"h1", "Heading 1", "Basic", :headings, ~w(h1 title heading)},
    {"h2", "Heading 2", "Basic", :headings, ~w(h2 subtitle heading)},
    {"h3", "Heading 3", "Basic", :headings, ~w(h3 heading)},
    {"h4", "Heading 4", "Basic", :headings, ~w(h4 heading)},
    {"quote", "Quote", "Basic", :quotes, ~w(blockquote citation)},
    {"bullet", "Bulleted list", "Basic", :lists, ~w(ul unordered bullets)},
    {"number", "Numbered list", "Basic", :lists, ~w(ol ordered numbers)},
    {"check", "Check list", "Basic", :check_lists, ~w(todo tasks checkbox)},
    {"code-block", "Code block", "Basic", :code_blocks, ~w(pre snippet)},
    {"table", "Table", "Basic", :tables, ~w(grid rows columns)},
    {"rule", "Divider", "Basic", :horizontal_rules, ~w(hr horizontal rule line separator)},
    {"upload", "Image or file", "Media", :attachments,
     ~w(image photo picture file attachment upload)},
    {"embed", "Embed", "Embeds", :embeds, ~w(canvas board)}
  ]

  @doc """
  Returns the built-in items of an insert menu, for the field's features:
  the blocks of text (Text, Heading 1 to 4, Quote, the lists, Code block),
  Table, Divider, Image or file and Embed, each with its `:command`,
  `:group` and `:keywords`. An item of a feature that the field does not
  have is left out, Image or file without `uploads: true`, and Embed
  without `embeds: true`.

  The options: `:features` (every feature but `blocks` by default, see
  `Kotoba.Features`), `:uploads` and `:embeds` (booleans, `false` by
  default). `<.kotoba>` gives the field's own.

  ## Examples

      iex> Kotoba.Prompts.commands(features: [:bold, :headings]) |> Enum.map(& &1.command)
      ["paragraph", "h1", "h2", "h3", "h4"]

  """
  @spec commands(keyword()) :: [item()]
  def commands(opts \\ []) do
    features =
      opts
      |> Keyword.get_lazy(:features, fn -> Kotoba.Features.all() end)
      |> Kotoba.Features.names!()

    for {command, label, group, feature, keywords} <- @commands,
        feature == nil or feature in features,
        command != "upload" or Keyword.get(opts, :uploads, false),
        command != "embed" or Keyword.get(opts, :embeds, false) do
      %{id: command, label: label, command: command, group: group, keywords: keywords}
    end
  end

  @doc """
  Finds the prompt with a name, in a prompt list.
  """
  @spec find(prompts() | nil, String.t()) :: prompt() | nil
  def find(prompts, name) when is_binary(name) do
    prompts |> normalize() |> Enum.find(fn {_trigger, prompt, _fun} -> prompt == name end)
  end

  @doc """
  Finds the prompt with a name, with its options, in a prompt list.
  """
  @spec find_spec(prompts() | nil, String.t()) :: options() | nil
  def find_spec(prompts, name) when is_binary(name) do
    prompts |> specs() |> Enum.find(&(&1.name == name))
  end

  @doc """
  Runs the callback of a prompt for a query, and returns the items for the
  editor, or `[]` when the callback fails. See `search/3`.
  """
  @spec run(prompt() | options(), String.t(), Phoenix.LiveView.Socket.t() | nil) :: [item()]
  def run(prompt, query, socket \\ nil) when is_binary(query) do
    case search(prompt, query, socket) do
      {:ok, items} -> items
      :error -> []
    end
  end

  @doc """
  Runs the callback of a prompt for a query. Returns `{:ok, items}`, or
  `:error` when the callback fails.

  A query that is longer than the prompt's `:max_length` gives no items,
  and the callback is not called.

  A callback that raises, exits or throws, or that does not return a list,
  fails, and a warning with the prompt name goes to the log.
  """
  @spec search(prompt() | options(), String.t(), Phoenix.LiveView.Socket.t() | nil) ::
          {:ok, [item()]} | :error
  def search(prompt, query, socket \\ nil)

  def search({_trigger, name, fun}, query, socket) when is_binary(query),
    do: do_search(name, fun, @max_query, query, socket)

  def search(%{name: name, search: fun, max_length: max_length}, query, socket)
      when is_binary(query),
      do: do_search(name, fun, max_length, query, socket)

  defp do_search(name, fun, max_length, query, socket) do
    if String.length(query) > max_length do
      {:ok, []}
    else
      with {:ok, items} <- safe_call(fun, name, query, socket) do
        {:ok, items |> Enum.flat_map(&item/1) |> Enum.take(@max_items)}
      end
    end
  end

  defp safe_call(fun, name, query, socket) do
    case call(fun, query, socket) do
      items when is_list(items) ->
        {:ok, items}

      other ->
        Logger.warning(
          "the Kotoba prompt #{inspect(name)} must return a list of items, got: #{inspect(other)}"
        )

        :error
    end
  rescue
    exception ->
      warn_failure(name, :error, exception, __STACKTRACE__)
  catch
    kind, reason when kind in [:exit, :throw] ->
      warn_failure(name, kind, reason, __STACKTRACE__)
  end

  defp warn_failure(name, kind, reason, stacktrace) do
    Logger.warning(
      "the Kotoba prompt #{inspect(name)} failed, so it gives no items:\n" <>
        Exception.format(kind, reason, stacktrace)
    )

    :error
  end

  defp call(fun, query, _socket) when is_function(fun, 1), do: fun.(query)
  defp call(fun, query, socket) when is_function(fun, 2), do: fun.(query, socket)

  @doc """
  Filters items for a query as the editor does for an `:items` prompt: each
  word of the query must start a word of the label, the hint or the
  keywords, with no
  regard to case or accents. The items whose label starts with the query
  come first.

  ## Examples

      iex> items = [%{id: "1", label: "Ada Lovelace"}, %{id: "2", label: "Grace Hopper"}]
      iex> Kotoba.Prompts.filter(items, "lov ad")
      [%{id: "1", label: "Ada Lovelace"}]

  """
  @spec filter([item()], String.t()) :: [item()]
  def filter(items, query) do
    words = words(query)

    items
    |> Enum.filter(fn item ->
      haystack =
        words(
          "#{item.label} #{Map.get(item, :hint, "")} #{Enum.join(Map.get(item, :keywords, []), " ")}"
        )

      Enum.all?(words, fn word -> Enum.any?(haystack, &String.starts_with?(&1, word)) end)
    end)
    |> Enum.sort_by(&(not String.starts_with?(fold(&1.label), fold(query))))
    |> Enum.take(@max_items)
  end

  defp words(text), do: text |> fold() |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)

  defp fold(text) do
    text
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
  end

  @doc """
  Normalizes one result item. Returns `[item]`, or `[]` when the item is
  not valid. An optional key that is not valid is dropped.

  ## Examples

      iex> Kotoba.Prompts.item(%{id: 7, label: "Ada", hint: "Engineering"})
      [%{id: "7", label: "Ada", hint: "Engineering"}]

      iex> Kotoba.Prompts.item({"u1", "Grace"})
      [%{id: "u1", label: "Grace"}]

      iex> Kotoba.Prompts.item(%{id: "tada", label: "tada", text: "🎉"})
      [%{id: "tada", label: "tada", text: "🎉"}]

      iex> Kotoba.Prompts.item(%{id: 1, label: "urgent", attrs: %{label: "#urgent"}})
      [%{id: "1", label: "urgent", attrs: %{"label" => "#urgent"}}]

      iex> Kotoba.Prompts.item(%{label: "No id"})
      []

  """
  @spec item(term()) :: [item()]
  def item({id, label}), do: item(%{id: id, label: label})

  def item(%{} = map) do
    with {:ok, id} <- text(fetch(map, :id)),
         {:ok, label} <- text(fetch(map, :label)) do
      item =
        %{id: id, label: label}
        |> put_ok(:hint, text(fetch(map, :hint)))
        |> put_ok(:text, text(fetch(map, :text)))
        |> put_ok(:attrs, attrs(fetch(map, :attrs)))
        |> put_ok(:command, command(fetch(map, :command)))
        |> put_ok(:node, node_json(fetch(map, :node)))
        |> put_ok(:group, text(fetch(map, :group)))
        |> put_ok(:keywords, keywords(fetch(map, :keywords)))
        |> put_ok(:assist, text(fetch(map, :assist)))

      [item]
    else
      :error -> []
    end
  end

  def item(_other), do: []

  defp put_ok(map, key, {:ok, value}), do: Map.put(map, key, value)
  defp put_ok(map, _key, :error), do: map

  defp fetch(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp text(value) when is_integer(value), do: {:ok, Integer.to_string(value)}

  defp text(value) when is_binary(value) do
    if String.valid?(value), do: value |> strip_controls() |> checked_text(), else: :error
  end

  defp text(_value), do: :error

  defp strip_controls(value), do: String.replace(value, ~r/\p{Cc}/u, "")

  defp checked_text(value) do
    if String.trim(value) != "" and String.length(value) <= @max_label,
      do: {:ok, value},
      else: :error
  end

  # The attributes of a node: a map with atom or string keys that encodes
  # to JSON in at most 2048 bytes. Its keys become strings, and "type",
  # "version" and "children" are the editor's.
  defp attrs(%{} = attrs) when not is_struct(attrs) do
    attrs =
      attrs
      |> Map.new(fn {key, value} -> {to_string(key), value} end)
      |> Map.drop(["type", "version", "children", "$"])

    if byte_size(JSON.encode!(attrs)) <= @max_attrs, do: {:ok, attrs}, else: :error
  rescue
    _error -> :error
  end

  defp attrs(_attrs), do: :error

  defp command(value) when is_binary(value) do
    if Regex.match?(@command, value), do: {:ok, value}, else: :error
  end

  defp command(_value), do: :error

  # A node to insert, as a document has it: a map with a Lexical "type".
  defp node_json(%{} = node) when not is_struct(node) do
    node = Map.new(node, fn {key, value} -> {to_string(key), value} end)

    with type when is_binary(type) <- node["type"],
         true <- Regex.match?(@node_type, type),
         true <- byte_size(JSON.encode!(node)) <= @max_attrs do
      {:ok, Map.delete(node, "$")}
    else
      _other -> :error
    end
  rescue
    _error -> :error
  end

  defp node_json(_node), do: :error

  defp keywords(list) when is_list(list) do
    keywords = list |> Enum.flat_map(&keyword/1) |> Enum.take(@max_keywords)
    if keywords == [], do: :error, else: {:ok, keywords}
  end

  defp keywords(_list), do: :error

  defp keyword(value) when is_binary(value) do
    case text(value) do
      {:ok, word} -> [word]
      :error -> []
    end
  end

  defp keyword(_value), do: []
end
