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
            {[{"@", :a, &none/1}, {"@", :b, &none/1}], ~r/each trigger/},
            {[{"@", :a, &none/1}, {"#", "a", &none/1}], ~r/each name/},
            {:people, ~r/must be a list/}
          ] do
        assert_raise ArgumentError, message, fn -> Prompts.normalize(prompts) end
      end
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
end
