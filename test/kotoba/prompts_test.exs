defmodule Kotoba.PromptsTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Kotoba.Prompts

  doctest Kotoba.Prompts

  defp none(_query), do: []

  describe "normalize/1" do
    test "gives @ and # to the keyword form, in order" do
      assert [{"@", "people", _}, {"#", "work", _}] =
               Prompts.normalize(people: &none/1, work: &none/1)
    end

    test "keeps explicit triggers and string names" do
      assert [{"+", "tags", _}, {"é", "work", _}] =
               Prompts.normalize([{"+", :tags, &none/1}, {"é", "work", &none/1}])
    end

    test "takes a callback with a label" do
      assert [{"@", "people", fun}, {"+", "tags", _}] =
               Prompts.normalize([
                 {"@", :people, {&none/1, label: "People"}},
                 {"+", :tags, &none/1}
               ])

      assert is_function(fun, 1)
    end

    test "is empty for nil and []" do
      assert Prompts.normalize(nil) == []
      assert Prompts.normalize([]) == []
    end

    test "raises on a list that is not valid" do
      for {prompts, message} <- [
            {[a: &none/1, b: &none/1, c: &none/1], ~r/more than two/},
            {[{"@", :a, &none/1}, {:b, &none/1}], ~r/not both/},
            {[{"ab", :a, &none/1}], ~r/one character/},
            {[{" ", :a, &none/1}], ~r/one character/},
            {[{"@", nil, &none/1}], ~r/name/},
            {[{"@", String.duplicate("n", 201), &none/1}], ~r/at most 200 characters/},
            {[{"@", :a, fn -> [] end}], ~r/arity 1 or 2/},
            {[a: {fn -> [] end, label: "A"}], ~r/arity 1 or 2/},
            {[a: {&none/1, label: ""}], ~r/non-empty string/},
            {[a: {&none/1, label: "  "}], ~r/non-empty string/},
            {[a: {&none/1, label: :people}], ~r/non-empty string/},
            {[a: {&none/1, label: "A\nB"}], ~r/non-empty string/},
            {[a: {&none/1, label: String.duplicate("l", 201)}], ~r/at most 200 characters/},
            {[a: {&none/1, title: "A"}], ~r/unknown option :title/},
            {[a: {&none/1, label: "A", label: "B"}], ~r/each option must be given once/},
            {[{"@", :a, &none/1}, {"@", :b, &none/1}], ~r/each trigger/},
            {[{"@", :a, &none/1}, {"#", "a", &none/1}], ~r/each name/},
            {:people, ~r/must be a list/}
          ] do
        assert_raise ArgumentError, message, fn -> Prompts.normalize(prompts) end
      end
    end
  end

  describe "labels/1" do
    test "maps the name of each prompt with a label to the label" do
      assert Prompts.labels(people: {&none/1, label: "People in the workshop"}, work: &none/1) ==
               %{"people" => "People in the workshop"}

      assert Prompts.labels([{"+", "tags", {&none/1, label: "Tags"}}]) == %{"tags" => "Tags"}
      assert Prompts.labels(people: &none/1) == %{}
      assert Prompts.labels(nil) == %{}
    end
  end

  describe "run/3" do
    test "normalizes the items and drops the bad ones" do
      prompt =
        {"@", "people",
         fn "a" ->
           [
             %{id: 1, label: "Ada"},
             %{"id" => "g", "label" => "Grace", "hint" => "Navy"},
             {"k", "Katherine"},
             %{id: 2},
             %{id: "x", label: ""},
             %{id: %{}, label: "Map id"},
             "text"
           ]
         end}

      assert Prompts.run(prompt, "a") == [
               %{id: "1", label: "Ada"},
               %{id: "g", label: "Grace", hint: "Navy"},
               %{id: "k", label: "Katherine"}
             ]
    end

    test "sends at most 50 items" do
      prompt = {"@", "n", fn _ -> Enum.map(1..80, &{&1, "n#{&1}"}) end}
      assert length(Prompts.run(prompt, "")) == 50
    end

    test "does not call the callback for a query of more than 64 characters" do
      prompt = {"@", "n", fn _ -> raise "called" end}
      assert Prompts.run(prompt, String.duplicate("q", 65)) == []
    end

    test "removes control characters from the id, the label and the hint" do
      prompt =
        {"@", "people",
         fn _ ->
           [
             %{id: "u\u00001", label: "Ada\tLovelace", hint: "Engi\nneering\u0085"},
             %{id: "u2", label: "\t\n"}
           ]
         end}

      assert Prompts.run(prompt, "") == [%{id: "u1", label: "AdaLovelace", hint: "Engineering"}]
    end

    test "gives no items and logs a warning when the callback raises" do
      log =
        capture_log(fn ->
          assert Prompts.run({"@", "people", fn _ -> raise "db down" end}, "a") == []
        end)

      assert log =~ "[warning]"
      assert log =~ ~s(the Kotoba prompt "people" failed)
      assert log =~ "db down"
    end

    test "gives no items and logs a warning when the callback exits" do
      log =
        capture_log(fn ->
          assert Prompts.run({"@", "people", fn _ -> exit(:no_database) end}, "a") == []
        end)

      assert log =~ ~s(the Kotoba prompt "people" failed)
      assert log =~ "no_database"
    end

    test "gives no items and logs a warning when the callback throws" do
      log =
        capture_log(fn ->
          assert Prompts.run({"@", "people", fn _ -> throw(:nope) end}, "a") == []
        end)

      assert log =~ ~s(the Kotoba prompt "people" failed)
      assert log =~ ":nope"
    end

    test "gives no items and logs a warning when the callback does not return a list" do
      log =
        capture_log(fn ->
          assert Prompts.run({"@", "people", fn _ -> {:ok, []} end}, "a") == []
        end)

      assert log =~ "[warning]"
      assert log =~ ~s(the Kotoba prompt "people" must return a list of items, got: {:ok, []})
    end
  end

  describe "options" do
    test "a keyword list gives a search or items, and the options" do
      assert [spec] =
               Prompts.specs(
                 people: [
                   search: &none/1,
                   spaces: true,
                   min_length: 2,
                   max_length: 100,
                   async: true
                 ]
               )

      assert %{
               trigger: "@",
               name: "people",
               items: nil,
               label: nil,
               spaces: true,
               min_length: 2,
               max_length: 100,
               insert: :mention,
               async: true
             } = spec

      assert [%{insert: {:node, "dev-tag"}, spaces: false, min_length: 0, max_length: 64}] =
               Prompts.specs([{"#", :tags, {&none/1, insert: {:node, "dev-tag"}}}])
    end

    test "raises on options that are not valid" do
      for {spec, message} <- [
            {[spaces: true], ~r/:search callback or :items/},
            {[search: &none/1, items: []], ~r/:search callback or :items/},
            {[items: :all], ~r/must be a list/},
            {{&none/1, search: &none/1}, ~r/not with a callback/},
            {[search: &none/1, spaces: "yes"], ~r/:spaces must be true or false/},
            {[search: &none/1, min_length: -1], ~r/:min_length must be an integer from 0 to 64/},
            {[search: &none/1, max_length: 5, min_length: 6],
             ~r/:min_length must be an integer from 0 to 5/},
            {[search: &none/1, max_length: 201],
             ~r/:max_length must be an integer from 1 to 200/},
            {[search: &none/1, insert: :emoji], ~r/:insert must be/},
            {[search: &none/1, insert: {:node, "no spaces"}], ~r/not a Lexical node type/},
            {[search: fn _query, _socket -> [] end, async: true],
             ~r/async prompt must have arity 1/},
            {[items: [], async: true], ~r/:items is not async/},
            {[search: &none/1, colour: :red], ~r/unknown option :colour/},
            {:people, ~r/a prompt must be/}
          ] do
        assert_raise ArgumentError, message, fn -> Prompts.normalize(people: spec) end
      end
    end

    test "config/1 gives the options that are not the default, and the items" do
      prompts = [
        people: [search: &none/1, spaces: true, min_length: 2, max_length: 80],
        work: &none/1
      ]

      assert Prompts.config(prompts) == %{
               "people" => %{spaces: true, minLength: 2, maxLength: 80}
             }

      assert Prompts.config([
               {":", :emoji,
                [
                  items: [%{id: "tada", label: "tada", hint: "🎉", text: "🎉"}, %{id: 1}],
                  insert: :text
                ]},
               {"#", :tags, [search: &none/1, insert: {:node, "dev-tag"}]}
             ]) == %{
               "emoji" => %{
                 insert: "text",
                 items: [%{id: "tada", label: "tada", hint: "🎉", text: "🎉"}]
               },
               "tags" => %{insert: "node", nodeType: "dev-tag"}
             }

      assert Prompts.config(nil) == %{}
    end

    test "an items prompt keeps at most 500 items, once each, and filters them on the server too" do
      items = Enum.map(1..600, &%{id: rem(&1, 550), label: "item #{&1}"})
      assert [%{items: kept}] = Prompts.specs(n: [items: items])
      assert length(kept) == 500

      assert [{"@", "n", fun}] = Prompts.normalize(n: [items: [{"1", "Ada Lovelace"}]])
      assert fun.("love") == [%{id: "1", label: "Ada Lovelace"}]
      assert fun.("grace") == []
    end
  end

  describe "search/3" do
    test "gives :error when the callback fails, and the items otherwise" do
      capture_log(fn ->
        assert Prompts.search({"@", "people", fn _ -> raise "down" end}, "a") == :error
      end)

      assert Prompts.search({"@", "people", fn _ -> [{1, "Ada"}] end}, "a") ==
               {:ok, [%{id: "1", label: "Ada"}]}
    end

    test "uses the max_length of the prompt" do
      [spec] = Prompts.specs(people: [search: fn _ -> raise "called" end, max_length: 3])
      assert Prompts.search(spec, "abcd") == {:ok, []}

      [spec] = Prompts.specs(people: [search: fn q -> [{q, q}] end, max_length: 100])
      query = String.duplicate("q", 90)
      assert Prompts.search(spec, query) == {:ok, [%{id: query, label: query}]}
    end
  end

  describe "filter/2" do
    test "matches the start of words, with no regard to case or accents, label starts first" do
      items = [
        %{id: "1", label: "José Álvarez", hint: "Design"},
        %{id: "2", label: "Ada Lovelace", hint: "Analyst"},
        %{id: "3", label: "Adam Smith"}
      ]

      assert Enum.map(Prompts.filter(items, "jose al"), & &1.id) == ["1"]
      assert Enum.map(Prompts.filter(items, "des"), & &1.id) == ["1"]
      assert Enum.map(Prompts.filter(items, "ada"), & &1.id) == ["2", "3"]
      assert Enum.map(Prompts.filter(items, "lace"), & &1.id) == []
      assert length(Prompts.filter(items, "")) == 3
    end
  end

  describe "item/1" do
    test "keeps a text and node attrs, and drops the ones that are not valid" do
      assert Prompts.item(%{id: 1, label: "a", text: "🎉", attrs: %{"label" => "x", type: "no"}}) ==
               [%{id: "1", label: "a", text: "🎉", attrs: %{"label" => "x"}}]

      assert Prompts.item(%{id: 1, label: "a", text: "", attrs: [1]}) == [%{id: "1", label: "a"}]

      big = %{"label" => String.duplicate("x", 3000)}
      assert Prompts.item(%{id: 1, label: "a", attrs: big}) == [%{id: "1", label: "a"}]
      assert Prompts.item(%{id: 1, label: "a", attrs: %{pid: self()}}) == [%{id: "1", label: "a"}]
    end
  end
end
