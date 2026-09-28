defmodule Kotoba.DocumentTest do
  use ExUnit.Case, async: true

  alias Kotoba.Document
  alias Kotoba.Nodes

  doctest Kotoba.Document

  defmodule Chart do
    use Kotoba.Node, type: "x-chart", kind: :decorator
    field :series, {:array, :integer}, required: true

    @impl Kotoba.Node
    def render_html(_node, _opts), do: {:safe, "<svg></svg>"}

    @impl Kotoba.Node
    def render_text(_node, _opts), do: ""
  end

  @fixtures Path.expand("../fixtures/lexical", __DIR__)

  defp fixture(name) do
    %{"root" => root} = @fixtures |> Path.join(name) |> File.read!() |> JSON.decode!()
    envelope(root)
  end

  defp envelope(root), do: %{"kotoba" => 1, "lexical" => "0.51", "root" => root}

  defp root(children) do
    %{
      "children" => children,
      "direction" => nil,
      "format" => "",
      "indent" => 0,
      "type" => "root",
      "version" => 1
    }
  end

  defp paragraph(children) do
    %{
      "children" => children,
      "direction" => nil,
      "format" => "",
      "indent" => 0,
      "textFormat" => 0,
      "textStyle" => "",
      "type" => "paragraph",
      "version" => 1
    }
  end

  defp text(value, format \\ 0) do
    %{
      "detail" => 0,
      "format" => format,
      "mode" => "normal",
      "style" => "",
      "text" => value,
      "type" => "text",
      "version" => 1
    }
  end

  defp mention(id, label) do
    %{"type" => "mention", "version" => 1, "kind" => "people", "id" => id, "label" => label}
  end

  defp attachment(attrs \\ %{}) do
    Map.merge(
      %{
        "type" => "attachment",
        "version" => 1,
        "key" => "k/cat.png",
        "url" => "/uploads/k/cat.png",
        "name" => "cat.png",
        "contentType" => "image/png",
        "bytes" => 2048,
        "width" => 640,
        "height" => 480
      },
      attrs
    )
  end

  defp parse!(envelope, opts \\ []) do
    {:ok, doc} = Document.parse(envelope, opts)
    doc
  end

  describe "parse/2 of Lexical output" do
    test "reads a heading and a bold paragraph" do
      assert {:ok, %Document{version: 1, lexical: "0.51", root: root}} =
               Document.parse(fixture("heading_and_bold_paragraph.json"))

      assert %Nodes.Root{
               children: [
                 %Nodes.Heading{tag: "h2", children: [%Nodes.Text{text: "Hello", format: 0}]},
                 %Nodes.Paragraph{
                   text_format: 1,
                   children: [%Nodes.Text{text: "bold", format: 1} = bold]
                 }
               ]
             } = root

      assert Nodes.Text.formats(bold) == [:bold]
    end

    test "reads a document that Lexical imported from Markdown" do
      doc = parse!(fixture("markdown_import.json"))

      assert [
               %Nodes.Heading{tag: "h1"},
               %Nodes.List{list_type: "bullet", start: 1, tag: "ul", children: [one, two]},
               %Nodes.Paragraph{
                 children: [
                   %Nodes.Text{format: 16},
                   %Nodes.Text{},
                   %Nodes.Link{url: "https://x.y"}
                 ]
               }
             ] = doc.root.children

      assert %Nodes.ListItem{value: 1, checked: nil, children: [%Nodes.Text{text: "one"}]} = one
      assert %Nodes.ListItem{value: 2, children: [%Nodes.Text{text: "two", format: 1}]} = two
      assert Document.text(doc) == "Title\none\ntwo\ncode and link"
    end

    test "reads every built-in Lexical node" do
      doc = parse!(fixture("all_nodes.json"))

      assert [
               %Nodes.Quote{children: [%Nodes.Text{}, %Nodes.LineBreak{}, %Nodes.Text{}]},
               %Nodes.Paragraph{children: [link, %Nodes.Text{text: " "}, autolink]},
               %Nodes.Code{language: "elixir", children: [keyword, plain]},
               %Nodes.Code{language: nil},
               %Nodes.List{list_type: "check", children: [%Nodes.ListItem{checked: true}]},
               %Nodes.List{list_type: "number", start: 3, tag: "ol"},
               %Nodes.HorizontalRule{}
             ] = doc.root.children

      assert %Nodes.Link{url: "https://a.b", rel: "noopener", target: "_blank", title: "T"} = link
      assert %Nodes.AutoLink{url: "https://c.d", is_unlinked: false, rel: nil} = autolink
      assert %Nodes.CodeHighlight{text: "def", highlight_type: "keyword"} = keyword
      assert %Nodes.CodeHighlight{text: " x", highlight_type: nil} = plain
    end

    test "reads Lexical tables, with the editor's layout keys in extra" do
      doc = parse!(fixture("table.json"))

      assert [%Nodes.Paragraph{}, people, totals, %Nodes.Paragraph{children: []}] =
               doc.root.children

      assert %Nodes.Table{children: [head, ada, grace], extra: extra} = people
      assert extra == %{}
      assert %Nodes.TableRow{children: [name, _role]} = head
      assert %Nodes.TableCell{header_state: 1, col_span: 1, row_span: 1} = name
      assert %Nodes.TableRow{children: [%Nodes.TableCell{header_state: 0}, engineer]} = ada

      assert %Nodes.TableCell{children: [%Nodes.Paragraph{children: [%Nodes.Text{format: 1}]}]} =
               engineer

      assert %Nodes.TableRow{children: [_grace, %Nodes.TableCell{children: [%Nodes.List{}]}]} =
               grace

      assert %Nodes.Table{extra: %{"colWidths" => [90, 60, 60]}, children: [row]} = totals

      assert %Nodes.TableRow{
               children: [
                 %Nodes.TableCell{header_state: 2},
                 %Nodes.TableCell{
                   col_span: 2,
                   extra: %{"backgroundColor" => "#ffeeaa", "width" => 120}
                 }
               ]
             } = row

      assert Document.text(doc) ==
               "Before\nName\tRole\nAda\tEngineer\nGrace\tNavy\nCOBOL\nTotal\t42 | 43\n"
    end

    test "accepts a JSON string" do
      json = "heading_and_bold_paragraph.json" |> fixture() |> JSON.encode!()
      assert {:ok, %Document{}} = Document.parse(json)
    end
  end

  describe "to_json/1" do
    for name <- ~w(heading_and_bold_paragraph.json markdown_import.json all_nodes.json table.json) do
      test "writes the same JSON that Lexical wrote in #{name}" do
        input = fixture(unquote(name))
        assert input |> parse!() |> Document.to_json() == input
      end
    end

    test "writes the same JSON for each built-in node" do
      nodes = [
        mention("u1", "Ada"),
        attachment(),
        attachment(%{"contentType" => "application/pdf"}) |> Map.drop(["width", "height"]),
        %{"type" => "linebreak", "version" => 1},
        text("styled", 3) |> Map.put("style", "color: red")
      ]

      for node <- nodes do
        input = envelope(root([paragraph([node])]))
        assert input |> parse!() |> Document.to_json() == input
      end
    end

    test "keeps the keys that a known node does not declare" do
      node = text("x") |> Map.put("$", %{"state" => 1}) |> Map.put("future", true)
      input = envelope(root([paragraph([node])]))

      assert input |> parse!() |> Document.to_json() == input
    end

    test "writes an element node with no children key with an empty children list" do
      input = envelope(root([Map.delete(paragraph([]), "children")]))

      assert %{"root" => %{"children" => [%{"children" => []}]}} =
               input |> parse!() |> Document.to_json()
    end
  end

  describe "unknown nodes" do
    test "are kept with their raw JSON, children included" do
      unknown = %{
        "type" => "x-chart",
        "version" => 2,
        "series" => [1, 2],
        "children" => [%{"not" => "a node"}]
      }

      input = envelope(root([paragraph([text("a"), unknown]), unknown]))

      doc = parse!(input)

      assert [
               %Nodes.Paragraph{
                 children: [_text, %Nodes.Unknown{type: "x-chart", raw: ^unknown}]
               },
               %Nodes.Unknown{}
             ] =
               doc.root.children

      assert Document.to_json(doc) == input
    end

    test "are read with a node module from the :nodes option" do
      input = envelope(root([%{"type" => "x-chart", "version" => 1, "series" => [1, 2]}]))

      assert [%Chart{series: [1, 2]}] = parse!(input, nodes: [Chart]).root.children
      assert [%Nodes.Unknown{}] = parse!(input).root.children
      assert Document.to_json(parse!(input, nodes: [Chart])) == input
    end
  end

  describe "parse/2 errors" do
    test "checks the envelope" do
      assert {:error, ["the document must be a JSON object"]} = Document.parse([1])
      assert {:error, ["the document is not valid JSON"]} = Document.parse("{")

      assert {:error, messages} = Document.parse(%{"kotoba" => 2, "root" => [], "extra" => 1})

      assert messages == [
               "unknown key \"extra\" in the document",
               "kotoba must be 1",
               "lexical must be a string",
               "root must be an object"
             ]
    end

    test "requires a root node at the top" do
      assert {:error, ["root must be a node of type \"root\""]} =
               Document.parse(envelope(paragraph([])))
    end

    test "refuses a root node below the top" do
      assert {:error, ["root.children[0]: a root node can only be the top node"]} =
               Document.parse(envelope(root([root([])])))
    end

    test "gives the path and the type of each node that is not valid" do
      input =
        envelope(
          root([
            paragraph([text("ok"), Map.delete(text("x"), "text"), "nope"]),
            %{"type" => "heading", "tag" => "h9", "children" => [%{"version" => 1}]},
            %{"type" => "list", "listType" => "bullet", "tag" => "ul", "children" => %{}},
            paragraph([mention(7, "Ada")])
          ])
        )

      assert {:error, messages} = Document.parse(input)

      assert messages == [
               "root.children[0].children[1] (text): text is required",
               "root.children[0].children[2]: a node must be an object",
               "root.children[1] (heading): tag must be one of: h1, h2, h3, h4, h5, h6",
               "root.children[1].children[0]: type must be a string",
               "root.children[2] (list): children must be a list",
               "root.children[3].children[0] (mention): id must be a string"
             ]
    end

    test "checks attachment fields" do
      input =
        envelope(root([attachment(%{"bytes" => "big", "width" => 1.5}) |> Map.delete("url")]))

      assert {:error, messages} = Document.parse(input)

      assert messages == [
               "root.children[0] (attachment): url is required",
               "root.children[0] (attachment): bytes must be an integer",
               "root.children[0] (attachment): width must be an integer"
             ]
    end
  end

  describe "traversal" do
    setup do
      input =
        envelope(
          root([
            paragraph([text("Hi "), mention("u1", "Ada"), text("!")]),
            attachment(),
            %{
              "children" => [
                %{
                  "children" => [
                    text("item"),
                    %{"type" => "linebreak", "version" => 1},
                    text("more")
                  ],
                  "direction" => nil,
                  "format" => "",
                  "indent" => 0,
                  "type" => "listitem",
                  "value" => 1,
                  "version" => 1
                }
              ],
              "direction" => nil,
              "format" => "",
              "indent" => 0,
              "listType" => "bullet",
              "start" => 1,
              "tag" => "ul",
              "type" => "list",
              "version" => 1
            },
            paragraph([mention("u2", "Grace")])
          ])
        )

      %{doc: parse!(input)}
    end

    test "walk/2 visits every node, the parent first", %{doc: doc} do
      Document.walk(doc, &send(self(), {:node, &1.__struct__}))

      types =
        Stream.repeatedly(fn ->
          receive do
            {:node, module} -> module
          after
            0 -> nil
          end
        end)
        |> Enum.take_while(& &1)

      assert types == [
               Nodes.Root,
               Nodes.Paragraph,
               Nodes.Text,
               Nodes.Mention,
               Nodes.Text,
               Nodes.Attachment,
               Nodes.List,
               Nodes.ListItem,
               Nodes.Text,
               Nodes.LineBreak,
               Nodes.Text,
               Nodes.Paragraph,
               Nodes.Mention
             ]
    end

    test "map/2 changes nodes and keeps the tree", %{doc: doc} do
      upcased =
        Document.map(doc, fn
          %Nodes.Text{} = text -> %{text | text: String.upcase(text.text)}
          node -> node
        end)

      assert Document.text(upcased) == "HI Ada!\ncat.png\nITEM\nMORE\nGrace"
    end

    test "map/2 with the identity function gives the same document", %{doc: doc} do
      assert Document.map(doc, & &1) == doc
    end

    test "text/1 joins the text of the blocks and agrees with Renderer.to_text/2", %{
      doc: doc
    } do
      assert Document.text(doc) == "Hi Ada!\ncat.png\nitem\nmore\nGrace"
      assert Document.text(doc) == Kotoba.Renderer.to_text(doc)
    end

    test "text/1 gives no blank line for a root decorator with no text" do
      doc =
        parse!(
          envelope(root([paragraph([text("a")]), %{"type" => "horizontalrule", "version" => 1}]))
        )

      assert Document.text(doc) == "a"
      assert Document.text(doc) == Kotoba.Renderer.to_text(doc)
    end

    test "mentions/1 and attachments/1 return the nodes in document order", %{doc: doc} do
      assert [%Nodes.Mention{id: "u1", label: "Ada"}, %Nodes.Mention{id: "u2"}] =
               Document.mentions(doc)

      assert [%Nodes.Attachment{name: "cat.png", width: 640}] = Document.attachments(doc)
    end
  end

  describe "empty?/1" do
    test "is true for empty blocks and white space" do
      assert Document.empty?(parse!(envelope(root([]))))
      assert Document.empty?(parse!(envelope(root([paragraph([])]))))

      assert Document.empty?(
               parse!(
                 envelope(
                   root([paragraph([text("  "), %{"type" => "linebreak", "version" => 1}])])
                 )
               )
             )
    end

    test "is true for a table of empty cells, as for an empty list" do
      cell = %{
        "type" => "tablecell",
        "headerState" => 1,
        "colSpan" => 1,
        "rowSpan" => 1,
        "children" => [paragraph([])]
      }

      table = %{
        "type" => "table",
        "children" => [%{"type" => "tablerow", "children" => [cell, cell]}]
      }

      assert Document.empty?(parse!(envelope(root([table]))))
    end

    test "is true for a lone tab" do
      tab = %{
        "detail" => 2,
        "format" => 0,
        "mode" => "normal",
        "style" => "",
        "text" => "\t",
        "type" => "tab",
        "version" => 1
      }

      assert Document.empty?(parse!(envelope(root([paragraph([tab])]))))
    end

    test "is false for text, decorators and unknown nodes" do
      refute Document.empty?(parse!(envelope(root([paragraph([text(" a ")])]))))
      refute Document.empty?(parse!(envelope(root([paragraph([mention("u", "U")])]))))
      refute Document.empty?(parse!(envelope(root([attachment()]))))

      refute Document.empty?(
               parse!(envelope(root([%{"type" => "horizontalrule", "version" => 1}])))
             )

      refute Document.empty?(parse!(envelope(root([%{"type" => "x-thing"}]))))
    end
  end
end
