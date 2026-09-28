defmodule Kotoba.CodeLanguagesTest do
  use ExUnit.Case, async: true

  alias Kotoba.CodeLanguages

  doctest Kotoba.CodeLanguages

  test "has the languages of the editor, with the same labels and aliases" do
    source = File.read!(Path.expand("../../assets/src/code_languages.ts", __DIR__))
    [table] = Regex.run(~r/CODE_LANGUAGES[^=]*= \[(.*?)\n\];/s, source, capture: :all_but_first)

    editor =
      for [_, id, label, aliases] <-
            Regex.scan(~r/\{ id: "([^"]+)", label: "([^"]+)", aliases: \[([^\]]*)\] \}/, table) do
        %{
          id: id,
          label: label,
          aliases: Regex.scan(~r/"([^"]+)"/, aliases, capture: :all_but_first) |> List.flatten()
        }
      end

    assert length(editor) >= 20
    assert editor == CodeLanguages.all()
  end

  test "every id and alias is one name" do
    names = Enum.flat_map(CodeLanguages.all(), &[&1.id | &1.aliases])
    assert names == Enum.uniq(names)
    assert Enum.all?(names, &(&1 == String.downcase(&1)))
    refute Enum.any?(names, &(&1 in ~w(plain text txt plaintext)))
  end

  test "find/1 reads an id or an alias in any case" do
    assert CodeLanguages.find("JS").id == "javascript"
    assert CodeLanguages.find("c++").id == "cpp"
    assert CodeLanguages.find("plain") == nil
    assert CodeLanguages.find(nil) == nil
  end

  test "ids!/1 gives ids, once each, and refuses a name that is not a language" do
    assert CodeLanguages.ids!([:elixir, "YAML", "yml"]) == ["elixir", "yaml"]
    assert CodeLanguages.ids!([]) == []

    assert_raise ArgumentError, ~r/unknown Kotoba code language "plain"/, fn ->
      CodeLanguages.ids!(["plain"])
    end
  end
end
