defmodule Kotoba.Issho.ToolsTest do
  use ExUnit.Case, async: false

  import Sake.Test

  alias Issho.Participant
  alias Issho.Tool.Context
  alias Kotoba.Collab
  alias Kotoba.Collab.{Document, Store}
  alias Kotoba.Content
  alias Kotoba.Issho.Text

  defmodule MCP do
    @moduledoc false
    use Issho.MCP, name: "kotoba-test", version: "0.0.0", tools: Kotoba.Issho.tools()
  end

  defmodule Policy do
    @moduledoc false
    @behaviour Issho.Policy

    @impl true
    def authorize(_identity, _room, _action), do: :ok

    @impl true
    def document(_identity, _id), do: Collab.document(store: {Store.Memory, :kotoba_mcp_store})
  end

  setup do
    start_supervised!({Store.Memory, name: :kotoba_mcp_store})
    instance = Issho.Test.start!(policy: Policy)
    Application.put_env(:issho, Issho.MCP, instance: instance)
    on_exit(fn -> Application.delete_env(:issho, Issho.MCP) end)

    document = "notebook:#{System.unique_integer([:positive])}/intro"

    :ok =
      Store.Memory.seed(
        :kotoba_mcp_store,
        document,
        Content.from_markdown("Read the docs today\n\nSecond line")
      )

    # Ada, a person in the room, sees what the agent does.
    {:ok, ada} = Issho.join_as(instance, %{id: "ada", name: "Ada"}, Issho.Policy.room(document))
    {:ok, _} = Participant.open(ada, document)

    client =
      connect(Kotoba.Issho.ToolsTest.MCP,
        client_info: %{"name" => "claude-code", "title" => "Claude Code"}
      )

    %{instance: instance, document: document, client: client, ada: ada}
  end

  defp html(ada, document) do
    {:ok, %{"state" => state}} = Participant.read(ada, document)
    {:ok, content} = Document.validate(state)
    content.html
  end

  defp call(client, tool, args) do
    case call_tool(client, tool, args) do
      {:ok, %{is_error: true, text: text}} -> {:error, text}
      {:ok, %{structured: structured}} -> {:ok, structured}
    end
  end

  test "an agent reads the blocks of a document", %{client: client, document: document} do
    assert {:ok,
            %{
              "blocks" => [
                %{"n" => 1, "text" => "Read the docs today"},
                %{"n" => 2, "text" => "Second line"}
              ]
            }} =
             call(client, "read_text", %{"document" => document})
  end

  test "an agent selects text, and the people see its selection", %{
    client: client,
    document: document,
    ada: ada
  } do
    assert {:ok, %{"block" => 1}} =
             call(client, "select_text", %{"document" => document, "text" => "the docs"})

    assert_receive {Participant, ^ada, "aware", %{"states" => states}}, 1_000

    assert [
             %{
               "state" => %{
                 "place" => %{"doc" => ^document, "at" => %{"anchor" => _, "focus" => _}}
               }
             }
           ] = Map.values(states)
  end

  test "selects, then links and formats the selection", %{
    client: client,
    document: document,
    ada: ada
  } do
    {:ok, _} = call(client, "select_text", %{"document" => document, "text" => "the docs"})

    assert {:ok, %{"linked" => "the docs"}} =
             call(client, "link_text", %{"document" => document, "url" => "https://kotoba.dev"})

    assert html(ada, document) =~
             ~s(Read <a href="https://kotoba.dev" rel="noopener nofollow">the docs</a> today)

    assert {:ok, _} =
             call(client, "format_text", %{
               "document" => document,
               "text" => "today",
               "marks" => %{"bold" => true}
             })

    assert html(ada, document) =~ "<strong>today</strong>"
  end

  test "types as a person types, a few characters at a time", %{
    client: client,
    document: document,
    ada: ada
  } do
    assert {:ok, %{"typed" => 14}} =
             call(client, "type_text", %{
               "document" => document,
               "after" => "today",
               "text" => ", and tomorrow"
             })

    assert html(ada, document) =~ "<p>Read the docs today, and tomorrow</p>"
    # Several transactions, one for each few characters.
    transactions = for _ <- 1..3, do: assert_receive({Participant, ^ada, "tx", _}, 1_000)
    assert length(transactions) == 3
  end

  # The places the agent showed Ada, in order, each once: the call returns
  # when the agent is done, so they have all been sent.
  defp places(ada, document, acc \\ []) do
    receive do
      {Participant, ^ada, "aware", %{"states" => states}} ->
        place =
          Enum.find_value(Map.values(states), fn
            %{"state" => %{"place" => %{"doc" => ^document, "at" => at}}} -> at
            _ -> nil
          end)

        places(ada, document, if(place && place != List.first(acc), do: [place | acc], else: acc))
    after
      100 -> Enum.reverse(acc)
    end
  end

  defp indexes(ada, document, places) do
    {:ok, %{"state" => state}} = Participant.read(ada, document)

    for place <- places do
      {:ok, range} = Text.from_place(state, place)
      {range.from, range.to}
    end
  end

  test "it goes to the text, and selects it as a drag does: only where it goes is sent", %{
    client: client,
    document: document,
    ada: ada
  } do
    {:ok, _} = call(client, "select_text", %{"document" => document, "text" => "the docs today"})

    # "Read the docs today": pressed at the start of "the", then dragged to
    # the end; Ada's browser draws the way.
    assert indexes(ada, document, places(ada, document)) == [{5, 5}, {5, 19}]

    {:ok, _} =
      call(client, "type_text", %{
        "document" => document,
        "at" => "start",
        "block" => 2,
        "text" => "A"
      })

    # To block 2, then what it typed there.
    assert [_start, _typed] = places(ada, document)
  end

  test "pace and travel: 0 and false, and the agent is there at once", %{
    client: client,
    document: document,
    ada: ada
  } do
    Application.put_env(:kotoba, Kotoba.Issho, pace: 0, travel: false)
    on_exit(fn -> Application.delete_env(:kotoba, Kotoba.Issho) end)

    {:ok, _} = call(client, "select_text", %{"document" => document, "text" => "today"})
    assert indexes(ada, document, places(ada, document)) == [{14, 19}]

    {:ok, _} =
      call(client, "type_text", %{"document" => document, "after" => "today", "text" => ", and"})

    # One transaction for the whole text.
    assert_receive {Participant, ^ada, "tx", _}, 1_000
    refute_receive {Participant, ^ada, "tx", _}, 200
    assert html(ada, document) =~ "<p>Read the docs today, and</p>"
  end

  test "a block is added as a person adds one: an empty block, then its text typed", %{
    client: client,
    document: document,
    ada: ada
  } do
    {:ok, _} =
      call(client, "add_block", %{
        "document" => document,
        "after" => 1,
        "type" => "quote",
        "text" => "From one thing, know ten thousand things."
      })

    assert html(ada, document) =~
             "<p>Read the docs today</p><blockquote>From one thing, know ten thousand things.</blockquote>"

    transactions = for _ <- 1..4, do: assert_receive({Participant, ^ada, "tx", _}, 1_000)
    assert length(transactions) == 4
  end

  test "replaces and deletes, copies and pastes", %{client: client, document: document, ada: ada} do
    {:ok, _} =
      call(client, "replace_text", %{
        "document" => document,
        "text" => "today",
        "with" => "now",
        "typing" => false
      })

    assert html(ada, document) =~ "<p>Read the docs now</p>"

    {:ok, _} = call(client, "copy_text", %{"document" => document, "text" => "the docs"})
    {:ok, _} = call(client, "paste_text", %{"document" => document, "at" => "end", "block" => 2})
    assert html(ada, document) =~ "<p>Second linethe docs</p>"

    {:ok, _} = call(client, "delete_text", %{"document" => document, "text" => "Second line"})
    assert html(ada, document) =~ "<p>the docs</p>"
  end

  test "adds blocks, and says what is wrong in words", %{
    client: client,
    document: document,
    ada: ada
  } do
    assert {:error, "Select the text first, or quote it."} =
             call(client, "link_text", %{"document" => document, "url" => "https://x.io"})

    {:ok, _} =
      call(client, "add_block", %{
        "document" => document,
        "after" => 0,
        "type" => "h1",
        "text" => "Plan"
      })

    assert html(ada, document) =~ "<h1>Plan</h1><p>Read"

    assert {:error, "The text \"missing\" is not in the document."} =
             call(client, "select_text", %{"document" => document, "text" => "missing"})

    # Its caret is after the new heading: nothing selected to link.
    assert {:error, "Select some text to make a link."} =
             call(client, "link_text", %{"document" => document, "url" => "https://x.io"})
  end

  test "moves a block, as a person drags it", %{client: client, document: document, ada: ada} do
    assert {:ok, %{"moved" => 2, "block" => 1}} =
             call(client, "move_block", %{"document" => document, "block" => 2, "after" => 0})

    assert html(ada, document) =~ "<p>Second line</p><p>Read the docs today</p>"

    assert {:error, "Block 2 is already there."} =
             call(client, "move_block", %{"document" => document, "block" => 2, "after" => 1})
  end

  test "an app's own model uses the same tools, through its API, with no MCP",
       %{instance: instance, document: document, ada: ada} do
    tools = Issho.Tools.room() ++ Kotoba.Issho.tools()
    assert Enum.any?(Issho.Tools.schemas(tools), &(&1["name"] == "link_text"))

    ctx =
      Context.new(instance, %{id: "assistant:ada", name: "Assistant", kind: :agent},
        on_behalf_of: %{id: "ada", name: "Ada"}
      )

    assert {:ok, _} =
             Issho.Tools.call(
               tools,
               "select_text",
               %{"document" => document, "text" => "the docs"},
               ctx
             )

    assert {:ok, _} =
             Issho.Tools.call(
               tools,
               "link_text",
               %{"document" => document, "url" => "https://kotoba.dev"},
               ctx
             )

    assert html(ada, document) =~
             ~s(<a href="https://kotoba.dev" rel="noopener nofollow">the docs</a>)
  end

  test "acts on what a person of the room has selected", %{
    client: client,
    document: document,
    ada: ada
  } do
    # Ada selects "the docs" in her editor.
    {:ok, %{"state" => state}} = Participant.read(ada, document)
    {:ok, range} = Text.find(state, "the docs")
    :ok = Participant.place(ada, %{"doc" => document, "at" => Text.place(range)})

    assert {:ok, %{"selected" => %{"block" => 1, "text" => "the docs"}}} =
             call(client, "read_text", %{"document" => document, "of" => "ada"})

    assert {:ok, _} =
             call(client, "format_text", %{
               "document" => document,
               "of" => "ada",
               "marks" => %{"bold" => true}
             })

    assert html(ada, document) =~ "Read <strong>the docs</strong> today"

    assert {:error, "No one called \"Zed\" is in the room."} =
             call(client, "read_text", %{"document" => document, "of" => "Zed"})
  end
end
