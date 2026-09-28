# The Kotoba development server: `mix dev`, then http://localhost:4099.
#
# One Phoenix endpoint with the editor on a few LiveViews, the built bundle
# from priv/static, the local storage adapter under tmp/uploads, and an app
# node (`KotobaDev.Nodes.Tag`, made with `mix kotoba.gen.node`). The browser
# tests in e2e/ run against it.
#
# The node modules of dev/assets are built into tmp/dev/nodes and served at
# /assets/nodes; they never go to priv/static, which holds only the files of
# the package.
#
# The bundle and the node modules rebuild and the page reloads on a change.
# `dev/lib` is loaded once when the server starts: restart `mix dev` after a
# change there.
#
# Environment:
#
#   * PORT - the HTTP port (4099).
#   * KOTOBA_DEV_WATCH - "false" starts no esbuild watchers and no live
#     reload, for the browser tests; the bundle must be built first.

Code.require_file("dev/lib/kotoba_dev/nodes/tag.ex", __DIR__)

port = "PORT" |> System.get_env("4099") |> String.to_integer()
watch? = System.get_env("KOTOBA_DEV_WATCH") != "false"
uploads = Path.expand("tmp/uploads", __DIR__)

Application.put_env(:phoenix, :json_library, JSON)
Logger.configure(level: :info)
Application.put_env(:kotoba, :nodes, [KotobaDev.Nodes.Tag])
Application.put_env(:kotoba, :allowed_link_schemes, ~w(http https mailto tel))
Application.put_env(:kotoba, :storage, Kotoba.Storage.Local)
Application.put_env(:kotoba, Kotoba.Storage.Local, root: uploads, url_prefix: "/uploads/kotoba")

Application.put_env(:kotoba, KotobaDev.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  check_origin: false,
  code_reloader: watch?,
  debug_errors: true,
  http: [ip: {127, 0, 0, 1}, port: port],
  live_view: [signing_salt: "kotoba-dev-live-view-salt"],
  pubsub_server: KotobaDev.PubSub,
  render_errors: [formats: [html: KotobaDev.ErrorHTML], layout: false],
  secret_key_base: String.duplicate("kotoba-development-secret-", 3),
  server: true,
  url: [host: "localhost"],
  watchers:
    if(watch?,
      do: [
        kotoba_esm: {Esbuild, :install_and_run, [:kotoba_esm, ~w(--watch)]},
        kotoba_dev_nodes: {Esbuild, :install_and_run, [:kotoba_dev_nodes, ~w(--watch)]}
      ],
      else: []
    ),
  live_reload: [
    patterns: [
      ~r"priv/static/.*\.(js|css)$",
      ~r"tmp/dev/nodes/.*\.js$",
      ~r"lib/kotoba/.*\.ex$"
    ]
  ]
)

defmodule KotobaDev.People do
  @moduledoc "A fixed list of people for the `@` prompt."

  @people [
    %{id: 1, label: "Ada Lovelace", hint: "Analyst"},
    %{id: 2, label: "Alan Turing", hint: "Mathematician"},
    %{id: 3, label: "Grace Hopper", hint: "Admiral"},
    %{id: 4, label: "Katherine Johnson", hint: "Mathematician"},
    %{id: 5, label: "Margaret Hamilton", hint: "Engineer"},
    %{id: 6, label: "Barbara Liskov", hint: "Computer scientist"}
  ]

  def search(query) do
    query = String.downcase(query)
    Enum.filter(@people, &String.contains?(String.downcase(&1.label), query))
  end

  @doc "The `!` prompt: a search that always fails, as a database that is down."
  def broken(_query), do: raise("the search is down")
end

defmodule KotobaDev.Sample do
  @moduledoc "The sample document of the Load sample buttons."

  def document(title \\ "Sample") do
    %{
      "kotoba" => 1,
      "lexical" => "0.51",
      "root" =>
        root([
          element("heading", [text(title)], %{"tag" => "h2"}),
          paragraph([
            text("Loaded from the "),
            text("server", 1),
            text(" with a "),
            %{"type" => "dev-tag", "version" => 1, "label" => "sample"},
            text(" tag and "),
            %{
              "type" => "mention",
              "version" => 1,
              "kind" => "people",
              "id" => "1",
              "label" => "Ada Lovelace"
            },
            text(".")
          ]),
          element(
            "list",
            [element("listitem", [text("One")], %{"value" => 1, "checked" => nil})],
            %{"listType" => "bullet", "start" => 1, "tag" => "ul"}
          )
        ])
    }
  end

  defp root(children),
    do: %{
      "type" => "root",
      "version" => 1,
      "direction" => nil,
      "format" => "",
      "indent" => 0,
      "children" => children
    }

  defp paragraph(children),
    do: element("paragraph", children, %{"textFormat" => 0, "textStyle" => ""})

  defp element(type, children, extra) do
    Map.merge(
      %{
        "type" => type,
        "version" => 1,
        "direction" => nil,
        "format" => "",
        "indent" => 0,
        "children" => children
      },
      extra
    )
  end

  defp text(text, format \\ 0),
    do: %{
      "type" => "text",
      "version" => 1,
      "detail" => 0,
      "format" => format,
      "mode" => "normal",
      "style" => "",
      "text" => text
    }
end

defmodule KotobaDev.Layouts do
  @moduledoc """
  The root layout: the style sheets, the import map and the LiveSocket.
  `?theme=sumi` also loads kotoba-sumi.css.
  """
  use Phoenix.Component

  def root(assigns) do
    assigns = assign(assigns, :sumi, assigns.conn.params["theme"] == "sumi")

    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()} />
        <title>Kotoba development</title>
        <link rel="stylesheet" href="/assets/kotoba.css" />
        <link :if={@sumi} rel="stylesheet" href="/assets/kotoba-sumi.css" />
        <style>
          body { font-family: system-ui, sans-serif; margin: 0; background: #fafaf9; color: #1c1917; }
          body.sumi { background: var(--kotoba-background); color: var(--kotoba-text); }
          main { max-width: 48rem; margin: 0 auto; padding: 2rem 1rem; }
          nav a { margin-right: 1rem; }
          .label { display: block; font-weight: 600; margin: 1rem 0 0.5rem; }
          .row { display: flex; flex-wrap: wrap; gap: 0.5rem; margin: 1rem 0; }
          dl { display: grid; grid-template-columns: max-content 1fr; gap: 0.25rem 1rem; }
          pre { white-space: pre-wrap; word-break: break-all; font-size: 0.75rem; }
          .stored { border-top: 1px solid #d6d3d1; margin-top: 2rem; }
        </style>
        <script type="importmap">
          {
            "imports": {
              "phoenix": "/vendor/phoenix/phoenix.mjs",
              "phoenix_live_view": "/vendor/phoenix_live_view/phoenix_live_view.esm.js",
              "kotoba": "/assets/kotoba.esm.js"
            }
          }
        </script>
        <script type="module">
          import { Socket } from "phoenix"
          import { LiveSocket } from "phoenix_live_view"
          import { Kotoba } from "kotoba"

          const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
          const liveSocket = new LiveSocket("/live", Socket, {
            hooks: { Kotoba },
            params: { _csrf_token: csrfToken }
          })
          liveSocket.connect()
          window.liveSocket = liveSocket
        </script>
      </head>
      <body class={@sumi && "sumi"}>
        <main>
          <nav>
            <a href="/">Editor</a><a href="/two">Two editors</a><a href="/nodes">Nodes</a><a href="/?theme=sumi">Sumi theme</a>
          </nav>
          {@inner_content}
        </main>
      </body>
    </html>
    """
  end
end

defmodule KotobaDev.EditorLive do
  @moduledoc """
  The editor in a form, with the `@` prompt, uploads and the Tag node. The
  `!` prompt always fails, so the menu shows "No results". The
  buttons under the form send each server event. After Submit, the stored
  content renders below.

  Query params: `sample` starts with the sample document; `change` starts
  with "Push changes" on (the editor's `change` attribute, so it pushes
  `kotoba:change`); `uploads=reverse`
  stores the finished uploads in reverse order, so that the attachments
  reach the editor in the opposite order of their markers.

  "Hold uploads" keeps the finished uploads pending (not stored) until
  Release. "Reject next upload" makes the next upload that Release stores
  fail, so the server removes its marker.
  """
  use Phoenix.LiveView

  import Kotoba.Components

  alias Kotoba.{Attachments, Storage}

  @editor "post_body_editor"

  @prompts [
    {"@", :people, &KotobaDev.People.search/1},
    {"!", :broken, &KotobaDev.People.broken/1}
  ]

  defp prompts, do: @prompts

  @impl true
  def mount(params, _session, socket) do
    body = if params["sample"], do: KotobaDev.Sample.document("Initial")

    {:ok,
     socket
     |> assign(
       form: to_form(%{"body" => body}, as: :post),
       stored: nil,
       readonly: false,
       invalid: false,
       changes: 0,
       push_changes: params["change"] != nil,
       validated: 0,
       validated_text: "",
       reverse: params["uploads"] == "reverse",
       hold: false,
       reject_next: false
     )
     |> allow_upload(:body,
       accept: ~w(.png .jpg .jpeg .gif .webp .pdf),
       max_entries: 4,
       max_file_size: 5_000_000,
       auto_upload: true,
       progress: &handle_progress/3
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h1>Kotoba</h1>
    <.form for={@form} id="post-form" phx-change="validate" phx-submit="save">
      <label id="body-label" class="label">Body</label>
      <.kotoba
        field={@form[:body]}
        label_id="body-label"
        placeholder="Write something…"
        prompts={prompts()}
        uploads={@uploads.body}
        readonly={@readonly}
        change={@push_changes}
        aria-invalid={@invalid}
        aria-describedby={if @invalid, do: "body-error"}
        nodes={[{KotobaDev.Nodes.Tag, "/assets/nodes/tag.js"}]}
      />
      <p :if={@invalid} id="body-error">Say something</p>
      <div class="row">
        <button type="submit" id="submit">Submit</button>
      </div>
    </.form>

    <div class="row" role="group" aria-label="Server events">
      <button type="button" id="load-sample" phx-click="load_sample">Load sample</button>
      <button
        type="button"
        id="toggle-readonly"
        phx-click="toggle_readonly"
        aria-pressed={to_string(@readonly)}
      >
        Readonly
      </button>
      <button
        type="button"
        id="toggle-invalid"
        phx-click="toggle_invalid"
        aria-pressed={to_string(@invalid)}
      >
        Invalid
      </button>
      <button type="button" id="push-lock" phx-click="set_readonly" phx-value-readonly="true">
        Lock (push)
      </button>
      <button type="button" id="push-unlock" phx-click="set_readonly" phx-value-readonly="false">
        Unlock (push)
      </button>
      <button type="button" id="push-focus" phx-click="focus">Focus editor</button>
      <button type="button" id="insert-tag" phx-click="insert_tag">Insert tag</button>
    </div>

    <div class="row" role="group" aria-label="Changes">
      <label>
        <input
          type="checkbox"
          id="push-changes"
          phx-click="toggle_changes"
          checked={@push_changes}
        /> Push changes
      </label>
    </div>

    <div class="row" role="group" aria-label="Uploads">
      <label>
        <input type="checkbox" id="hold-uploads" phx-click="toggle_hold" checked={@hold} />
        Hold uploads
      </label>
      <label>
        <input type="checkbox" id="reject-next" phx-click="toggle_reject" checked={@reject_next} />
        Reject next upload
      </label>
      <button type="button" id="release-uploads" phx-click="release">Release</button>
    </div>

    <p :if={message = Phoenix.Flash.get(@flash, :error)} id="flash-error" role="alert">
      {message}
    </p>

    <dl>
      <dt>Pushed changes (kotoba:change)</dt>
      <dd id="change-count">{@changes}</dd>
      <dt>Form changes</dt>
      <dd id="validate-count">{@validated}</dd>
      <dt>Finished uploads, not stored</dt>
      <dd id="held-count">{Enum.count(@uploads.body.entries, & &1.done?)}</dd>
      <dt>Text in the last form change</dt>
      <dd id="validated-text">{@validated_text}</dd>
    </dl>

    <section :if={@stored} id="stored" class="stored">
      <h2>Stored</h2>
      <.kotoba_content content={@stored} id="stored-content" />
      <h3>Text</h3>
      <pre id="stored-text">{@stored.text}</pre>
      <h3>Document</h3>
      <pre id="stored-json">{JSON.encode!(@stored.doc)}</pre>
    </section>
    """
  end

  @impl true
  def handle_event("validate", params, socket) do
    socket =
      socket
      |> update(:validated, &(&1 + 1))
      |> assign(validated_text: posted_text(params))

    {:noreply,
     if(socket.assigns.reverse or socket.assigns.hold, do: socket, else: consume(socket))}
  end

  def handle_event("save", %{"post" => %{"body" => body}}, socket) do
    case Kotoba.Content.cast(body) do
      {:ok, content} -> {:noreply, socket |> clear_flash() |> assign(stored: content)}
      :error -> {:noreply, put_flash(socket, :error, "The document is not valid")}
    end
  end

  def handle_event("kotoba:change", %{"id" => @editor}, socket),
    do: {:noreply, update(socket, :changes, &(&1 + 1))}

  def handle_event("kotoba:prompt", params, socket),
    do: {:noreply, Kotoba.Live.handle_prompt(socket, params, @prompts)}

  def handle_event("toggle_changes", _params, socket),
    do: {:noreply, update(socket, :push_changes, &(not &1))}

  def handle_event("load_sample", _params, socket),
    do: {:noreply, Kotoba.Live.push_content(socket, @editor, KotobaDev.Sample.document())}

  def handle_event("toggle_readonly", _params, socket),
    do: {:noreply, update(socket, :readonly, &(not &1))}

  def handle_event("toggle_invalid", _params, socket),
    do: {:noreply, update(socket, :invalid, &(not &1))}

  def handle_event("set_readonly", %{"readonly" => value}, socket),
    do: {:noreply, Kotoba.Live.set_readonly(socket, @editor, value == "true")}

  def handle_event("focus", _params, socket),
    do: {:noreply, Kotoba.Live.focus(socket, @editor)}

  def handle_event("toggle_hold", _params, socket),
    do: {:noreply, update(socket, :hold, &(not &1))}

  def handle_event("toggle_reject", _params, socket),
    do: {:noreply, update(socket, :reject_next, &(not &1))}

  def handle_event("release", _params, socket),
    do: {:noreply, socket |> assign(hold: false) |> release()}

  def handle_event("insert_tag", _params, socket),
    do:
      {:noreply, Kotoba.Live.insert_node(socket, @editor, %KotobaDev.Nodes.Tag{label: "urgent"})}

  # The phx-change carries the document too (the hook's formdata listener).
  defp posted_text(%{"post" => %{"body" => body}}) do
    case Kotoba.Content.cast(body) do
      {:ok, content} -> content.text
      :error -> ""
    end
  end

  defp posted_text(_params), do: ""

  defp handle_progress(:body, %{done?: true}, socket) do
    cond do
      socket.assigns.hold -> {:noreply, socket}
      socket.assigns.reverse -> {:noreply, consume_reversed(socket)}
      true -> {:noreply, consume(socket)}
    end
  end

  defp handle_progress(:body, _entry, socket), do: {:noreply, socket}

  defp consume(socket), do: Kotoba.Live.consume_uploads(socket, :body, @editor)

  # Stores the held uploads in the order of their entries. With "Reject next
  # upload", the key function gives no key for the first of them, so it is
  # not stored and its marker is removed (`Kotoba.Live.consume_uploads/4`).
  defp release(socket) do
    reject =
      with true <- socket.assigns.reject_next,
           %{ref: ref} <- Enum.find(socket.assigns.uploads.body.entries, & &1.done?),
           do: ref

    key = fn entry, type -> if entry.ref != reject, do: Storage.key(entry.client_name, type) end

    socket
    |> assign(reject_next: socket.assigns.reject_next and reject == nil)
    |> Kotoba.Live.consume_uploads(:body, @editor, key: key)
  end

  # Waits for every entry, then stores them last first. Each attachment
  # carries its entry's ref, so it still takes the place of its own marker.
  defp consume_reversed(socket) do
    entries = socket.assigns.uploads.body.entries

    if entries != [] and Enum.all?(entries, & &1.done?) do
      entries
      |> Enum.reverse()
      |> Enum.reduce(socket, fn entry, socket ->
        node = consume_uploaded_entry(socket, entry, &{:ok, store(&1.path, entry)})
        Kotoba.Live.insert_node(socket, @editor, node, ref: entry.ref)
      end)
    else
      socket
    end
  end

  defp store(path, entry) do
    name = Attachments.clean_name(entry.client_name)
    {:ok, description} = Attachments.describe(path, entry.client_type)
    key = Storage.key(name, description.content_type)
    meta = %{name: name, content_type: description.content_type, bytes: description.bytes}
    {:ok, url} = Storage.Local.put(key, path, meta)
    Attachments.node(description, key: key, url: url, name: name)
  end
end

defmodule KotobaDev.PanelComponent do
  @moduledoc """
  A LiveComponent with its own editor. The editor has
  `phx-target={@myself}`, so its events come here and not to the LiveView.
  """
  use Phoenix.LiveComponent

  import Kotoba.Components

  @editor "b_editor"

  # A label names the prompt's menu: "People in the workshop", not
  # "people suggestions".
  @prompts [people: {&KotobaDev.People.search/1, label: "People in the workshop"}]

  defp prompts, do: @prompts

  @impl true
  def mount(socket),
    do: {:ok, assign(socket, form: to_form(%{"body" => nil}, as: :b), changes: 0)}

  @impl true
  def render(assigns) do
    ~H"""
    <section id="panel">
      <.form for={@form} id="b-form" phx-target={@myself} phx-change="validate">
        <label id="b-label" class="label">Second editor (in a LiveComponent)</label>
        <.kotoba
          field={@form[:body]}
          id="b_editor"
          label_id="b-label"
          prompts={prompts()}
          change
          phx-target={@myself}
        />
      </.form>
      <div class="row">
        <button type="button" id="load-b" phx-click="load" phx-target={@myself}>
          Load the second editor
        </button>
      </div>
      <dl>
        <dt>Changes in the component</dt>
        <dd id="panel-changes">{@changes}</dd>
      </dl>
    </section>
    """
  end

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("kotoba:change", %{"id" => @editor}, socket),
    do: {:noreply, update(socket, :changes, &(&1 + 1))}

  def handle_event("kotoba:prompt", params, socket),
    do: {:noreply, Kotoba.Live.handle_prompt(socket, params, @prompts)}

  def handle_event("load", _params, socket),
    do: {:noreply, Kotoba.Live.push_content(socket, @editor, KotobaDev.Sample.document("Second"))}
end

defmodule KotobaDev.TwoEditorsLive do
  @moduledoc """
  Two editors on one page: one in the LiveView, one in a LiveComponent.
  Every push names its editor, so the other editor ignores it.
  """
  use Phoenix.LiveView

  import Kotoba.Components

  @impl true
  def mount(_params, _session, socket),
    do: {:ok, assign(socket, form: to_form(%{"body" => nil}, as: :a), change_ids: [])}

  @impl true
  def render(assigns) do
    ~H"""
    <h1>Two editors</h1>
    <.form for={@form} id="a-form" phx-change="validate">
      <label id="a-label" class="label">First editor</label>
      <.kotoba field={@form[:body]} id="a_editor" label_id="a-label" change />
    </.form>
    <div class="row">
      <button type="button" id="load-a" phx-click="load">Load the first editor</button>
    </div>
    <dl>
      <dt>Changes in the LiveView</dt>
      <dd id="parent-changes">{Enum.join(Enum.uniq(@change_ids), ",")}</dd>
    </dl>
    <.live_component module={KotobaDev.PanelComponent} id="panel" />
    """
  end

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("kotoba:change", %{"id" => id}, socket),
    do: {:noreply, update(socket, :change_ids, &(&1 ++ [id]))}

  def handle_event("load", _params, socket),
    do:
      {:noreply, Kotoba.Live.push_content(socket, "a_editor", KotobaDev.Sample.document("First"))}
end

defmodule KotobaDev.NodesLive do
  @moduledoc """
  An editor with app node modules that the editor must refuse:
  `?case=missing` names a module that does not exist, `?case=builtin` a
  module whose node has the type of a built-in node.
  """
  use Phoenix.LiveView

  import Kotoba.Components

  @modules %{
    "missing" => "/assets/nodes/missing.js",
    "builtin" => "/assets/nodes/mention_clash.js"
  }

  @impl true
  def mount(params, _session, socket) do
    url = Map.get(@modules, params["case"], "/assets/nodes/tag.js")
    {:ok, assign(socket, form: to_form(%{"body" => nil}, as: :nodes), url: url)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h1>Node modules</h1>
    <p>Module: <code id="module-url">{@url}</code></p>
    <.form for={@form} id="nodes-form">
      <label id="nodes-label" class="label">Body</label>
      <.kotoba field={@form[:body]} label_id="nodes-label" nodes={[@url]} />
    </.form>
    """
  end
end

defmodule KotobaDev.Router do
  use Phoenix.Router

  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:protect_from_forgery)
    plug(:put_root_layout, html: {KotobaDev.Layouts, :root})
  end

  scope "/" do
    pipe_through(:browser)

    live("/", KotobaDev.EditorLive)
    live("/two", KotobaDev.TwoEditorsLive)
    live("/nodes", KotobaDev.NodesLive)
  end
end

defmodule KotobaDev.ErrorHTML do
  def render(template, _assigns), do: Phoenix.Controller.status_message_from_template(template)
end

defmodule KotobaDev.Endpoint do
  use Phoenix.Endpoint, otp_app: :kotoba

  @session [store: :cookie, key: "_kotoba_dev", signing_salt: "kotoba-dev"]

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session]])

  if System.get_env("KOTOBA_DEV_WATCH") != "false" do
    socket("/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket)
    plug(Phoenix.LiveReloader)
    plug(Phoenix.CodeReloader)
  end

  # The node modules, then the editor bundle and its style sheets.
  plug(Plug.Static, at: "/assets/nodes", from: Path.expand("tmp/dev/nodes", __DIR__))
  plug(Plug.Static, at: "/assets", from: Path.expand("priv/static", __DIR__))
  plug(Plug.Static, at: "/vendor/phoenix", from: {:phoenix, "priv/static"})
  plug(Plug.Static, at: "/vendor/phoenix_live_view", from: {:phoenix_live_view, "priv/static"})

  # The uploaded files, from tmp/uploads.
  plug(Kotoba.Storage.Local.Plug)

  plug(Plug.Parsers, parsers: [:urlencoded, :json], pass: ["*/*"], json_decoder: JSON)
  plug(Plug.Session, @session)
  plug(KotobaDev.Router)
end

# The script's process ends after this file, so the server runs in a task
# that stays alive; `mix run --no-halt` keeps the VM up.
Task.async(fn ->
  if watch?, do: {:ok, _apps} = Application.ensure_all_started(:esbuild)
  File.mkdir_p!(uploads)

  {:ok, _pid} =
    Supervisor.start_link(
      [{Phoenix.PubSub, name: KotobaDev.PubSub}, KotobaDev.Endpoint],
      strategy: :one_for_one
    )

  IO.puts("Kotoba development server: http://localhost:#{port}")
  Process.sleep(:infinity)
end)
