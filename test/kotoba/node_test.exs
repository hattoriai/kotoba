defmodule Kotoba.NodeTest do
  use ExUnit.Case, async: true

  alias Kotoba.Node.Field
  alias Kotoba.Nodes.CodeHighlight

  defmodule Pointer do
    use Kotoba.Node, type: "pointer", kind: :inline

    field :ref, :string, required: true
    field :excerpt, :string, omit_nil: true
    field :weight, :integer, default: 0
    field :pinned, :boolean
    field :meta, :map
    field :tags, {:array, :string}
    field :shade, :string, in: ~w(light dark)

    @impl Kotoba.Node
    def render_html(node, _opts), do: Phoenix.HTML.html_escape(inspect(node))

    @impl Kotoba.Node
    def render_text(_node, _opts), do: ""
  end

  defmodule Box do
    use Kotoba.Node, type: "box", kind: :block, element: true

    field :label, :string

    @impl Kotoba.Node
    def validate(node) do
      with :ok <- super(node) do
        if node.label == "forbidden", do: {:error, ["label is forbidden"]}, else: :ok
      end
    end

    @impl Kotoba.Node
    def render_html(node, _opts), do: Phoenix.HTML.html_escape(inspect(node))

    @impl Kotoba.Node
    def render_text(_node, _opts), do: ""
  end

  describe "use Kotoba.Node" do
    test "defines type/0, kind/0 and element?/0" do
      assert Pointer.type() == "pointer"
      assert Pointer.kind() == :inline
      refute Pointer.element?()
      assert Box.element?()
    end

    test "defines a struct with defaults, a version and an extra map" do
      assert %Pointer{ref: nil, weight: 0, version: 1, extra: %{}} = %Pointer{}
      assert %Box{children: [], direction: nil, format: "", indent: 0} = %Box{}
    end

    test "fields/0 lists the declared fields, then the element fields and the version" do
      assert Enum.map(Pointer.fields(), & &1.name) ==
               [:ref, :excerpt, :weight, :pinned, :meta, :tags, :shade, :version]

      assert Enum.map(Box.fields(), & &1.name) == [:label, :direction, :format, :indent, :version]

      assert [%Field{name: :ref, key: "ref", type: :string, required: true} | _rest] =
               Pointer.fields()
    end

    test "raises for a reserved field name" do
      assert_raise ArgumentError, ~r/reserved/, fn ->
        defmodule Reserved do
          use Kotoba.Node, type: "reserved", kind: :inline
          field :children, :string
        end
      end
    end

    test "raises for a reserved JSON key" do
      for key <- ~w(type children version) do
        assert_raise ArgumentError, ~r/the JSON key "#{key}" is reserved/, fn ->
          Code.compile_string("""
          defmodule Kotoba.NodeTest.ReservedKey do
            use Kotoba.Node, type: "reserved", kind: :inline
            field :label, :string, key: #{inspect(key)}
          end
          """)
        end
      end
    end

    test "raises when two fields have the same JSON key" do
      assert_raise ArgumentError, ~r/the JSON key "label" is used by more than one field/, fn ->
        defmodule SameKey do
          use Kotoba.Node, type: "same", kind: :inline
          field :label, :string
          field :caption, :string, key: "label"
        end
      end

      assert_raise ArgumentError, ~r/the JSON key "indent" is used by more than one field/, fn ->
        defmodule ElementKey do
          use Kotoba.Node, type: "same", kind: :block, element: true
          field :depth, :integer, key: "indent"
        end
      end
    end

    test "defines a render_markdown/2 that calls render_text/2" do
      assert CodeHighlight.render_markdown(%CodeHighlight{text: "x"}, []) == "x"

      assert Pointer.render_markdown(%Pointer{ref: "r"}, []) == ""
    end

    test "raises for a field type that is not supported" do
      assert_raise ArgumentError, ~r/invalid type/, fn ->
        defmodule BadType do
          use Kotoba.Node, type: "bad", kind: :inline
          field :at, :datetime
        end
      end
    end

    test "raises for an unknown field option" do
      assert_raise ArgumentError, ~r/unknown options/, fn ->
        defmodule BadOption do
          use Kotoba.Node, type: "bad", kind: :inline
          field :at, :string, nullable: true
        end
      end
    end

    test "raises for a kind that is not supported" do
      assert_raise ArgumentError, ~r/:kind/, fn ->
        defmodule BadKind do
          use Kotoba.Node, type: "bad", kind: :section
        end
      end
    end
  end

  describe "validate/1" do
    test "accepts a valid node" do
      assert :ok =
               Pointer.validate(%Pointer{
                 ref: "a",
                 tags: ["x"],
                 meta: %{},
                 pinned: true,
                 shade: "dark"
               })
    end

    test "requires the required fields" do
      assert {:error, ["ref is required"]} = Pointer.validate(%Pointer{})
    end

    test "checks the type of each field" do
      node = %Pointer{ref: 1, weight: "2", pinned: "yes", meta: [], tags: ["a", 1], version: nil}

      assert {:error, messages} = Pointer.validate(node)

      assert messages == [
               "ref must be a string",
               "weight must be an integer",
               "pinned must be a boolean",
               "meta must be an object",
               "tags must be a list of strings",
               "version is required"
             ]
    end

    test "checks the permitted values" do
      assert {:error, ["shade must be one of: light, dark"]} =
               Pointer.validate(%Pointer{ref: "a", shade: "red"})
    end

    test "can be overridden and call super" do
      assert :ok = Box.validate(%Box{label: "ok"})
      assert {:error, ["label is forbidden"]} = Box.validate(%Box{label: "forbidden"})

      assert {:error, ["direction must be one of: ltr, rtl"]} =
               Box.validate(%Box{direction: "up"})
    end
  end

  describe "from_json/1 and to_json/1" do
    test "read the declared keys and keep the other keys in extra" do
      json = %{
        "type" => "pointer",
        "version" => 1,
        "ref" => "r1",
        "weight" => 3,
        "$" => %{"a" => 1}
      }

      node = Pointer.from_json(json)

      assert %Pointer{ref: "r1", weight: 3, excerpt: nil, extra: %{"$" => %{"a" => 1}}} = node

      assert Pointer.to_json(node) ==
               Map.merge(json, %{"pinned" => nil, "meta" => nil, "tags" => nil, "shade" => nil})
    end

    test "use the default for a key that is not in the JSON" do
      assert %Pointer{weight: 0, version: 1} =
               Pointer.from_json(%{"type" => "pointer", "ref" => "r"})
    end

    test "do not write an omit_nil field that is nil" do
      json = Pointer.to_json(%Pointer{ref: "r"})
      refute Map.has_key?(json, "excerpt")
      assert Map.has_key?(json, "pinned")
    end

    test "keep a null for an omit_nil field that was in the JSON" do
      json = %{"type" => "pointer", "version" => 1, "ref" => "r", "excerpt" => nil}
      node = Pointer.from_json(json)

      assert Map.fetch!(Pointer.to_json(node), "excerpt") == nil
      assert Pointer.to_json(%{node | excerpt: "set"})["excerpt"] == "set"
    end

    test "write the children of an element node" do
      node = %Box{label: "b", children: [%Pointer{ref: "r"}]}

      assert %{"type" => "box", "children" => [%{"type" => "pointer", "ref" => "r"}]} =
               Box.to_json(node)
    end

    test "from_json/1 of an element node does not read the children" do
      assert %Box{children: [], extra: extra} =
               Box.from_json(%{"type" => "box", "children" => [%{}]})

      assert extra == %{}
    end
  end

  test "node_module?/1" do
    assert Kotoba.Node.node_module?(Pointer)
    assert Kotoba.Node.node_module?(Kotoba.Nodes.Text)
    refute Kotoba.Node.node_module?(Kotoba.Nodes.Unknown)
    refute Kotoba.Node.node_module?(String)
    refute Kotoba.Node.node_module?("text")
  end
end
