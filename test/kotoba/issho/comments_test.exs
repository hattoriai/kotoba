defmodule Kotoba.Issho.CommentsTest do
  use ExUnit.Case, async: false

  import Phoenix.LiveViewTest

  alias Kotoba.Collab.Store

  @endpoint KotobaTest.Endpoint

  defmodule Policy do
    @moduledoc false
    @behaviour Issho.Policy

    @impl true
    def authorize(_identity, _document_id, _action), do: :ok

    @impl true
    def document(_identity, _document_id),
      do: Kotoba.Issho.document(store: {Store.Memory, :kotoba_comments_store})
  end

  defmodule CommentsLive do
    @moduledoc false
    # Issho's comments, written in a Kotoba editor, as an app's page has them.
    use Phoenix.LiveView

    on_mount(Issho.Live)

    @impl true
    def mount(_params, %{"instance" => instance, "room" => room}, socket) do
      if connected?(socket),
        do: {:ok, _} = Issho.Live.join(instance, %{id: "ada", name: "Ada"}, room)

      {:ok, assign(socket, room: room, mentionable: [%{key: "user:grace", name: "Grace Hopper"}])}
    end

    @impl true
    def render(assigns) do
      ~H"""
      <Issho.Components.comments
        id="comments"
        room={@room}
        mentionable={@mentionable}
        read={&Kotoba.Issho.read_comment/1}
      >
        <:input :let={input}>
          <Kotoba.Components.kotoba
            field={Kotoba.Issho.comment_field(input, @room, @mentionable)}
            id={input.id}
            label="Comment"
            placeholder={input.placeholder}
            features={[:mentions]}
            prompts={Kotoba.Issho.comment_prompts(@room, @mentionable)}
          />
        </:input>
      </Issho.Components.comments>
      """
    end

    @impl true
    def handle_event("kotoba:prompt", params, socket) do
      prompts = Kotoba.Issho.comment_prompts(socket.assigns.room, socket.assigns.mentionable)
      {:noreply, Kotoba.Live.handle_prompt(socket, params, prompts)}
    end
  end

  defp text(value),
    do: %{
      "type" => "text",
      "version" => 1,
      "text" => value,
      "format" => 0,
      "detail" => 0,
      "mode" => "normal",
      "style" => ""
    }

  defp mention(kind, id, label),
    do: %{"type" => "mention", "version" => 1, "kind" => kind, "id" => id, "label" => label}

  defp body(children) do
    JSON.encode!(%{
      "kotoba" => 1,
      "lexical" => "0.51",
      "root" => %{
        "type" => "root",
        "version" => 1,
        "children" => [%{"type" => "paragraph", "version" => 1, "children" => children}]
      }
    })
  end

  describe "read_comment/1" do
    test "a mention of the @ prompt is the person's @ and name, and their key" do
      json =
        body([
          text("Ask "),
          mention("people", "user:grace", "Grace Hopper"),
          text(" and "),
          mention("people", "user:grace", "Grace Hopper"),
          text(" about "),
          mention("work", "42", "The plan")
        ])

      assert Kotoba.Issho.read_comment(%{"body" => json}) == %{
               body: "Ask @Grace Hopper and @Grace Hopper about The plan",
               mentions: ["user:grace"]
             }
    end

    test "a box with nothing valid in it says nothing" do
      assert Kotoba.Issho.read_comment(%{"body" => "not json"}) == %{body: "", mentions: []}
      assert Kotoba.Issho.read_comment(%{}) == %{body: "", mentions: []}
    end
  end

  test "comment_field/3 starts an edit from the comment as it is" do
    input = %{
      id: "comments-edit-body-c1",
      value: "Ask @Grace Hopper\nand @Nobody",
      field: Phoenix.Component.to_form(%{"body" => "Ask @Grace Hopper\nand @Nobody"})[:body]
    }

    field =
      Kotoba.Issho.comment_field(input, "room:none", [%{key: "user:grace", name: "Grace Hopper"}])

    assert field.name == "body"

    assert %{"root" => %{"children" => [first, second]}} = field.value
    assert [%{"text" => "Ask "}, %{"type" => "mention", "id" => "user:grace"}] = first["children"]
    assert [%{"text" => "and @Nobody"}] = second["children"]

    assert Kotoba.Issho.read_comment(%{"body" => JSON.encode!(field.value)}) == %{
             body: "Ask @Grace Hopper\nand @Nobody",
             mentions: ["user:grace"]
           }
  end

  describe "the comment box of Issho's comments" do
    setup do
      start_supervised!({Store.Memory, name: :kotoba_comments_store})
      # Issho.Presence, for the room's people.
      instance = Issho.Test.start!(policy: Policy, presence: true)
      room = "notebook:#{System.unique_integer([:positive])}"

      {:ok, view, _html} =
        live_isolated(Phoenix.ConnTest.build_conn(), CommentsLive,
          session: %{"instance" => instance, "room" => room}
        )

      %{instance: instance, room: room, view: view}
    end

    test "is a Kotoba editor, and a comment says whom it mentions", %{
      instance: instance,
      room: room,
      view: view
    } do
      assert has_element?(view, ~s(#comments-new-body-0[phx-hook="Kotoba"]))

      view
      |> element("#comments-new-0")
      |> render_submit(%{
        "where" => "page",
        "body" => body([text("Look, "), mention("people", "user:grace", "Grace Hopper")])
      })

      assert {:ok, [%{"comments" => [comment]}]} = Issho.Comments.threads(instance, room)
      assert comment["body"] == "Look, @Grace Hopper"
      assert comment["mentions"] == ["user:grace"]

      # The panel marks the mention, and the next box is a new, empty editor.
      assert view |> element(".issho-comment-body .issho-mention") |> render() =~ "@Grace Hopper"
      assert has_element?(view, ~s(#comments-new-body-1[phx-hook="Kotoba"]))
    end

    test "the @ offers the room's people, here first, and mentionable", %{
      instance: instance,
      room: room,
      view: view
    } do
      {:ok, _ken} = Issho.join_as(instance, %{id: "ken", name: "Ken"}, room)
      assert eventually(fn -> render(view) =~ "&quot;name&quot;:&quot;Ken&quot;" end)

      render_hook(view, "kotoba:prompt", %{
        "v" => 1,
        "id" => "comments-new-body-0",
        "prompt" => "people",
        "query" => ""
      })

      assert_push_event(view, "kotoba:prompt_results", %{prompt: "people", items: items})

      assert Enum.sort_by(items, & &1.id) == [
               %{id: "ada", label: "Ada", hint: "Here"},
               %{id: "ken", label: "Ken", hint: "Here"},
               %{id: "user:grace", label: "Grace Hopper"}
             ]

      assert List.last(items).id == "user:grace"

      render_hook(view, "kotoba:prompt", %{
        "v" => 1,
        "id" => "comments-new-body-0",
        "prompt" => "people",
        "query" => "gra"
      })

      assert_push_event(view, "kotoba:prompt_results", %{items: [%{id: "user:grace"}]})
    end
  end

  defp eventually(fun, tries \\ 50) do
    cond do
      fun.() -> true
      tries == 0 -> false
      true -> Process.sleep(20) && eventually(fun, tries - 1)
    end
  end
end
