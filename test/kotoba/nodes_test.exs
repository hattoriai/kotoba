defmodule Kotoba.NodesTest do
  use ExUnit.Case, async: false

  alias Kotoba.Nodes

  doctest Kotoba.Nodes.Text
  doctest Kotoba.Nodes.Attachment

  defmodule Chip do
    use Kotoba.Node, type: "mention", kind: :decorator
    field :label, :string, required: true
  end

  test "the registry maps each built-in type to its module" do
    registry = Nodes.registry()

    assert Map.keys(registry) |> Enum.sort() ==
             Enum.sort(
               ~w(root paragraph heading quote list listitem text linebreak link autolink code
                          code-highlight horizontalrule attachment mention)
             )

    assert registry["listitem"] == Nodes.ListItem
  end

  test "a given node replaces the built-in node of the same type" do
    assert Nodes.registry([Chip])["mention"] == Chip
  end

  test "the registry reads the application config" do
    Application.put_env(:kotoba, :nodes, [Chip])
    on_exit(fn -> Application.delete_env(:kotoba, :nodes) end)

    assert Nodes.registry()["mention"] == Chip
  end

  test "the registry refuses a module that is not a node" do
    assert_raise ArgumentError, ~r/not a Kotoba.Node module/, fn -> Nodes.registry([String]) end
  end

  describe "Kotoba.Nodes.Text" do
    test "formats/1 reads every bit" do
      assert Nodes.Text.formats(255) ==
               [
                 :bold,
                 :italic,
                 :strikethrough,
                 :underline,
                 :code,
                 :subscript,
                 :superscript,
                 :highlight
               ]

      assert Nodes.Text.formats(0) == []
    end

    test "bitmask/1 is the reverse of formats/1" do
      for bitmask <- 0..255,
          do: assert(Nodes.Text.bitmask(Nodes.Text.formats(bitmask)) == bitmask)
    end
  end
end
