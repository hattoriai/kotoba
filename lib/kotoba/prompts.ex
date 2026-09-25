defmodule Kotoba.Prompts do
  @moduledoc """
  Prompts: a trigger character in the editor opens a menu of results that
  the LiveView finds, for example `@` for people.

  A prompt list has one of two forms:

      # The first prompt has the trigger "@", the second has "#".
      [people: &MyApp.People.search/1, work: &MyApp.Work.search/1]

      # Each trigger given explicitly.
      [{"@", :people, &MyApp.People.search/1}, {"#", :work, &MyApp.Work.search/1}]

  A trigger is exactly one character that is not white space. The name of a
  prompt (an atom or a string) is the `kind` of the mentions that it
  inserts.

  The callback gets the query (the text after the trigger, at most 64
  characters and with no white space) and returns a list of items. A
  callback with arity 2 also gets the socket, for example to scope the
  search to the current user:

      [people: fn query, socket -> MyApp.People.search(socket.assigns.scope, query) end]

  An item is a map with an `:id` (a string or an integer), a `:label` (a
  string) and an optional `:hint` (a string), with atom or string keys, or
  an `{id, label}` tuple. Items that do not have this shape are dropped, and
  at most 50 items are sent. Control characters (such as a tab or a line
  break) are removed from the id, the label and the hint.

  A callback that raises, exits or throws, or that returns anything but a
  list, gives no items: `run/3` logs a warning with the prompt name, and the
  editor shows "No results". The callback runs in the LiveView process, so a
  slow callback blocks the LiveView while it runs.

  The component `Kotoba.Components.kotoba/1` sends the triggers and names to
  the editor; the functions stay in the LiveView. `Kotoba.Live.handle_prompt/3`
  runs them.
  """

  require Logger

  @max_items 50
  @max_query 64
  @max_label 200
  @max_name 200
  @positional ["@", "#"]

  @typedoc "An item as the editor receives it."
  @type item :: %{
          required(:id) => String.t(),
          required(:label) => String.t(),
          optional(:hint) => String.t()
        }

  @typedoc "A prompt callback."
  @type callback :: (String.t() -> list()) | (String.t(), Phoenix.LiveView.Socket.t() -> list())

  @typedoc "A prompt list, in one of the two forms of the module doc."
  @type prompts :: [
          {atom() | String.t(), callback()} | {String.t(), atom() | String.t(), callback()}
        ]

  @typedoc "A prompt, normalized: `{trigger, name, callback}`."
  @type prompt :: {String.t(), String.t(), callback()}

  @doc """
  Normalizes a prompt list to `{trigger, name, callback}` tuples.

  Raises `ArgumentError` when the list is not valid: a trigger that is not
  one character, a name or a trigger that is given twice, a callback that
  is not a function of arity 1 or 2, more than two prompts without explicit
  triggers, or the two forms mixed.

  ## Examples

      iex> [{trigger, name, _fun}] = Kotoba.Prompts.normalize(people: fn _query -> [] end)
      iex> {trigger, name}
      {"@", "people"}

  """
  @spec normalize(prompts() | nil) :: [prompt()]
  def normalize(nil), do: []
  def normalize([]), do: []

  def normalize(prompts) when is_list(prompts) do
    normalized =
      cond do
        Enum.all?(prompts, &match?({_name, _fun}, &1)) -> positional(prompts)
        Enum.all?(prompts, &match?({_trigger, _name, _fun}, &1)) -> Enum.map(prompts, &explicit/1)
        true -> invalid!(prompts, "use [name: fun] or [{trigger, name, fun}], not both")
      end

    check_unique!(normalized, 0, "trigger")
    check_unique!(normalized, 1, "name")
    normalized
  end

  def normalize(other), do: invalid!(other, "a prompt list must be a list")

  defp positional(prompts) when length(prompts) > length(@positional) do
    invalid!(prompts, "give each trigger explicitly for more than two prompts")
  end

  defp positional(prompts) do
    prompts
    |> Enum.zip(@positional)
    |> Enum.map(fn {{name, fun}, trigger} -> explicit({trigger, name, fun}) end)
  end

  defp explicit({trigger, name, fun} = prompt) do
    unless trigger?(trigger), do: invalid!(prompt, "a trigger must be one character")

    unless name?(name),
      do:
        invalid!(
          prompt,
          "a name must be an atom or a non-empty string of at most #{@max_name} characters"
        )

    unless is_function(fun, 1) or is_function(fun, 2),
      do: invalid!(prompt, "a callback must be a function of arity 1 or 2")

    {trigger, to_string(name), fun}
  end

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

  defp check_unique!(prompts, index, what) do
    values = Enum.map(prompts, &elem(&1, index))

    if length(Enum.uniq(values)) != length(values),
      do: invalid!(values, "each #{what} must be given once")
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
    prompts |> normalize() |> Map.new(fn {trigger, name, _fun} -> {trigger, name} end)
  end

  @doc """
  Finds the prompt with a name, in a prompt list.
  """
  @spec find(prompts() | nil, String.t()) :: prompt() | nil
  def find(prompts, name) when is_binary(name) do
    prompts |> normalize() |> Enum.find(fn {_trigger, prompt, _fun} -> prompt == name end)
  end

  @doc """
  Runs the callback of a prompt for a query, and returns the items for the
  editor.

  A query of more than #{@max_query} characters gives no items, and the
  callback is not called.

  A callback that raises, exits or throws, or that does not return a list,
  gives no items, and a warning with the prompt name goes to the log.
  """
  @spec run(prompt(), String.t(), Phoenix.LiveView.Socket.t() | nil) :: [item()]
  def run({_trigger, name, fun}, query, socket \\ nil) when is_binary(query) do
    if String.length(query) > @max_query do
      []
    else
      fun
      |> safe_call(name, query, socket)
      |> Enum.flat_map(&item/1)
      |> Enum.take(@max_items)
    end
  end

  defp safe_call(fun, name, query, socket) do
    case call(fun, query, socket) do
      items when is_list(items) ->
        items

      other ->
        Logger.warning(
          "the Kotoba prompt #{inspect(name)} must return a list of items, got: #{inspect(other)}"
        )

        []
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

    []
  end

  defp call(fun, query, _socket) when is_function(fun, 1), do: fun.(query)
  defp call(fun, query, socket) when is_function(fun, 2), do: fun.(query, socket)

  @doc """
  Normalizes one result item. Returns `[item]`, or `[]` when the item is
  not valid.

  ## Examples

      iex> Kotoba.Prompts.item(%{id: 7, label: "Ada", hint: "Engineering"})
      [%{id: "7", label: "Ada", hint: "Engineering"}]

      iex> Kotoba.Prompts.item({"u1", "Grace"})
      [%{id: "u1", label: "Grace"}]

      iex> Kotoba.Prompts.item(%{label: "No id"})
      []

  """
  @spec item(term()) :: [item()]
  def item({id, label}), do: item(%{id: id, label: label})

  def item(%{} = map) do
    id = fetch(map, :id)
    label = fetch(map, :label)
    hint = fetch(map, :hint)

    with {:ok, id} <- text(id),
         {:ok, label} <- text(label) do
      case text(hint) do
        {:ok, hint} -> [%{id: id, label: label, hint: hint}]
        :error -> [%{id: id, label: label}]
      end
    else
      :error -> []
    end
  end

  def item(_other), do: []

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
end
