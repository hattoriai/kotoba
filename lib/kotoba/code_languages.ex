defmodule Kotoba.CodeLanguages do
  @languages [
    {"bash", "Bash", ~w(sh shell zsh)},
    {"c", "C", []},
    {"cpp", "C++", ~w(c++)},
    {"css", "CSS", []},
    {"diff", "Diff", ~w(patch)},
    {"dockerfile", "Dockerfile", ~w(docker)},
    {"elixir", "Elixir", ~w(ex exs)},
    {"erlang", "Erlang", ~w(erl)},
    {"go", "Go", ~w(golang)},
    {"graphql", "GraphQL", ~w(gql)},
    {"html", "HTML", ~w(htm markup)},
    {"java", "Java", []},
    {"javascript", "JavaScript", ~w(js mjs cjs)},
    {"json", "JSON", []},
    {"kotlin", "Kotlin", ~w(kt kts)},
    {"markdown", "Markdown", ~w(md)},
    {"objectivec", "Objective-C", ~w(objc)},
    {"php", "PHP", []},
    {"powershell", "PowerShell", ~w(ps1 pwsh)},
    {"python", "Python", ~w(py)},
    {"ruby", "Ruby", ~w(rb)},
    {"rust", "Rust", ~w(rs)},
    {"sql", "SQL", []},
    {"swift", "Swift", []},
    {"toml", "TOML", []},
    {"typescript", "TypeScript", ~w(ts)},
    {"xml", "XML", ~w(svg)},
    {"yaml", "YAML", ~w(yml)}
  ]

  @moduledoc """
  The code languages of the editor: the ones that it highlights and that its
  language picker offers.

  | Id | Label | Aliases |
  | -- | ----- | ------- |
  #{Enum.map_join(@languages, "\n", fn {id, label, aliases} -> "| `#{id}` | #{label} | #{Enum.map_join(aliases, ", ", &"`#{&1}`")} |" end)}

  A code block stores the name of its language: an id, an alias (a block
  pasted or imported with `yml` keeps `yml`), or any other name. The
  editor highlights the ids and the aliases; the picker shows the language
  of an alias, and writes the id when the person picks a language. A block
  with no language, or with `plain` (`text`, `txt`, `plaintext`), is plain
  text. A name that is not a language is kept, and it is not highlighted:
  the picker shows it as "(not highlighted)". Prism knows the names in lower
  case: a block with `Elixir` is kept and shown as Elixir, but not
  highlighted.

  `Kotoba.Components.kotoba/1` takes a `code_languages` list of ids, the
  languages of its picker. The editor's `assets/src/code_languages.ts` has
  the same table; a test compares the two.
  """

  @typedoc "A code language: its id, its label and its aliases."
  @type language :: %{id: String.t(), label: String.t(), aliases: [String.t()]}

  @all Enum.map(@languages, fn {id, label, aliases} ->
         %{id: id, label: label, aliases: aliases}
       end)
  @ids Enum.map(@all, & &1.id)
  @by_name for language <- @all,
               name <- [language.id | language.aliases],
               into: %{},
               do: {name, language}

  @doc """
  Returns the languages, in the order of the picker.

  ## Examples

      iex> length(Kotoba.CodeLanguages.all()) >= 20
      true

  """
  @spec all() :: [language()]
  def all, do: @all

  @doc """
  Returns the ids of the languages, in the order of the picker.

  ## Examples

      iex> "elixir" in Kotoba.CodeLanguages.ids()
      true

  """
  @spec ids() :: [String.t()]
  def ids, do: @ids

  @doc """
  Returns the language of a name, an id or an alias in any case, or `nil`
  for a name that is not a language (plain text included).

  ## Examples

      iex> Kotoba.CodeLanguages.find("yml").id
      "yaml"

      iex> Kotoba.CodeLanguages.find("Elixir").label
      "Elixir"

      iex> Kotoba.CodeLanguages.find("cobol")
      nil

  """
  @spec find(String.t() | nil) :: language() | nil
  def find(name) when is_binary(name), do: Map.get(@by_name, String.downcase(name))
  def find(_name), do: nil

  @doc """
  Returns the ids for a list of ids or aliases, in order and once each, for
  the `code_languages` attribute of `Kotoba.Components.kotoba/1`.

  Raises `ArgumentError` for a name that is not a language.

  ## Examples

      iex> Kotoba.CodeLanguages.ids!(["elixir", "js", "ex"])
      ["elixir", "javascript"]

  """
  @spec ids!([String.t() | atom()]) :: [String.t()]
  def ids!(names) when is_list(names) do
    names
    |> Enum.map(fn name ->
      case find(to_string(name)) do
        %{id: id} ->
          id

        nil ->
          raise ArgumentError,
                "unknown Kotoba code language #{inspect(name)}, use one of #{inspect(@ids)}"
      end
    end)
    |> Enum.uniq()
  end
end
