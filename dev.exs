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
Code.require_file("dev/lib/kotoba_dev/nodes/callout.ex", __DIR__)

port = "PORT" |> System.get_env("4099") |> String.to_integer()
watch? = System.get_env("KOTOBA_DEV_WATCH") != "false"
uploads = Path.expand("tmp/uploads", __DIR__)

Application.put_env(:phoenix, :json_library, JSON)
Logger.configure(level: :info)
Application.put_env(:kotoba, :nodes, [KotobaDev.Nodes.Tag, KotobaDev.Nodes.Callout])
Application.put_env(:kotoba, :allowed_link_schemes, ~w(http https mailto tel))
Application.put_env(:issho, Issho.MCP, instance: KotobaDev.Issho)
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

  @doc "The `~` prompt: a search that takes a second, in a task (`async: true`)."
  def slow(query) do
    Process.sleep(1_000)
    search(query)
  end
end

defmodule KotobaDev.Assist do
  @moduledoc """
  A fake language model for the Assist menu of the editor page: it answers
  each action with a fixed text, in chunks of four characters, one every
  40 ms, with no API key. The Markdown of an answer is cut anywhere, `**`
  included. "Fail" streams a little, then cancels.
  """

  @actions [
    rewrite: "Rewrite",
    summarize: "Summarize",
    continue: "Continue writing",
    fail: "Fail"
  ]

  def actions, do: @actions

  @doc "The answer, and the stream options, of an action."
  def answer("rewrite", text),
    do: {"A **clearer** version: #{text}", at: :selection, label: "Rewrite"}

  def answer("summarize", text),
    do:
      {"**Summary:** #{text |> String.split() |> Enum.take(3) |> Enum.join(" ")}…",
       at: :after, label: "Summary"}

  def answer("continue", _text),
    do:
      {"## What comes next\n\n- One more point\n- And a _last_ one",
       at: :after, label: "Continue writing"}

  def answer("fail", _text), do: {"This answer will not", at: :selection, label: "Fail"}

  @doc "Starts the stream of an answer, for the editor `id`; `opts` replace the answer's stream options."
  def start(socket, id, ref, action, text, opts \\ []) do
    {answer, answer_opts} = answer(action, text)
    Process.send_after(self(), {:assist_chunk, id, ref, action, answer}, 40)

    socket
    |> Kotoba.Live.stream_start(id, ref, Keyword.merge(answer_opts, opts))
    |> Phoenix.Component.update(:assist_refs, &MapSet.put(&1, ref))
  end

  @doc "Sends the next chunk, or ends the stream (a \"fail\" stream is cancelled after two chunks)."
  def next(socket, id, ref, action, rest) do
    cond do
      ref not in socket.assigns.assist_refs ->
        socket

      rest == "" ->
        socket |> Kotoba.Live.stream_end(id, ref) |> stop(ref)

      action == "fail" and String.length(rest) < 12 ->
        socket |> Kotoba.Live.stream_cancel(id, ref) |> stop(ref)

      true ->
        {chunk, rest} = String.split_at(rest, 4)
        Process.send_after(self(), {:assist_chunk, id, ref, action, rest}, 40)
        Kotoba.Live.stream_chunk(socket, id, ref, chunk)
    end
  end

  @doc "Stops a stream: its next chunks are dropped."
  def stop(socket, ref),
    do: Phoenix.Component.update(socket, :assist_refs, &MapSet.delete(&1, ref))
end

defmodule KotobaDev.Prompts do
  @moduledoc """
  The prompts of the editor page:

    * `@` people, whose query can have spaces ("Ada Lovelace");
    * `!` a search that always fails;
    * `:` emoji, a local list that inserts text;
    * `+` tags, an async search that inserts a Tag node;
    * `~` people again, from a search of a second, in a task.
  """

  @emoji [
    %{id: "tada", label: "tada", hint: "🎉", text: "🎉"},
    %{id: "heart", label: "heart", hint: "❤️", text: "❤️"},
    %{id: "thumbsup", label: "thumbs up", hint: "👍", text: "👍"},
    %{id: "rocket", label: "rocket", hint: "🚀", text: "🚀"},
    %{id: "eyes", label: "eyes", hint: "👀", text: "👀"}
  ]

  @tags ~w(urgent bug design later)

  def list do
    [
      {"@", :people, [search: &KotobaDev.People.search/1, spaces: true]},
      {"!", :broken, &KotobaDev.People.broken/1},
      {":", :emoji, [items: @emoji, insert: :text, label: "Emoji"]},
      {"+", :tags, [search: &tags/1, insert: {:node, "dev-tag"}, async: true, label: "Tags"]},
      {"~", :slow, [search: &KotobaDev.People.slow/1, async: true, min_length: 1]}
    ]
  end

  defp tags(query) do
    for tag <- @tags, String.starts_with?(tag, String.downcase(query)) do
      %{id: tag, label: tag, attrs: %{label: tag}}
    end
  end
end

defmodule KotobaDev.Sample do
  @moduledoc "The sample documents: the Load sample buttons', and the palette."

  # With `code: true`, a code block in "ex", an alias: the editor shows
  # Elixir and keeps "ex". Only the second editor's sample has it: the editor
  # highlights a loaded code block in an update of its own, which the main
  # editor's "not pushed back" test would count.
  def document(title \\ "Sample", opts \\ []) do
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
          ),
          if(opts[:code],
            do: element("code", [text("defmodule Sample do end")], %{"language" => "ex"})
          ),
          element(
            "table",
            [
              element("tablerow", [cell("Language", 1), cell("Year", 1)], %{}),
              element("tablerow", [cell("Elixir", 0), cell("2012", 0)], %{})
            ],
            %{}
          )
        ])
    }
  end

  @colors ~w(red orange yellow green blue purple gray)

  # The text after the colors: a link, and code with each kind of token.
  @palette_markdown ~S"""
  A [link](https://example.com), **bold** and `inline code`.

  ```elixir
  # A greeting, with each kind of token
  defmodule Greeter do
    @default "world"
    def hello(name \\ @default, times \\ 2) when is_binary(name) do
      String.duplicate("Hello, #{name}! ", times) <> inspect(:ok, pretty: true)
    end
  end
  ```

  ```diff
  @@ -1,2 +1,2 @@
   unchanged line
  -removed line
  +added line
  ```

  ```css
  .note > a:hover { color: #e84a1c; margin: 0 1rem; }
  ```
  """

  @doc """
  Every color of the palette, as text, as a highlight and both, then a
  link and code blocks: what `?sample=palette` shows, to see a theme at a
  glance.
  """
  def palette do
    doc = Kotoba.Content.from_markdown(@palette_markdown).doc

    colors = [
      element("heading", [text("Palette")], %{"tag" => "h2"}),
      paragraph(runs(&"color: var(--kotoba-color-#{&1});", 0)),
      paragraph(
        runs(&"background-color: var(--kotoba-highlight-#{&1});", 128) ++ [text("default", 128)]
      ),
      paragraph(
        runs(
          &"color: var(--kotoba-color-#{&1});background-color: var(--kotoba-highlight-#{&1});",
          128
        )
      )
    ]

    update_in(doc, ["root", "children"], &(colors ++ &1))
  end

  defp runs(style, format),
    do: Enum.flat_map(@colors, &[%{text(&1, format) | "style" => style.(&1)}, text(" ")])

  defp root(children),
    do: %{
      "type" => "root",
      "version" => 1,
      "direction" => nil,
      "format" => "",
      "indent" => 0,
      "children" => Enum.reject(children, &is_nil/1)
    }

  defp paragraph(children),
    do: element("paragraph", children, %{"textFormat" => 0, "textStyle" => ""})

  # A table cell: headerState 1 in the header row, 0 elsewhere.
  defp cell(value, header_state),
    do:
      element("tablecell", [paragraph([text(value)])], %{
        "headerState" => header_state,
        "colSpan" => 1,
        "rowSpan" => 1,
        "backgroundColor" => nil
      })

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
  `?theme=sumi` also loads kotoba-sumi.css; `?sumi=smoke` (any of Sumi's
  seven themes) loads it on that theme of Sumi, to see the editor in each
  (`?sumi=smoke&sample=palette` for every color).
  """
  use Phoenix.Component

  # Sumi's themes, as the editor reads them: the page, the surface, the
  # line, the text, the muted and the secondary text (the text's opacity),
  # the accent, ember, the text on the accent, and warning (the yellow).
  # Sumi's own CSS needs Tailwind, which this app has not; these are its
  # values. info, success and error are the built-in palette's, which has
  # Sumi's dark and light values.
  @sumi_themes [
    {"dark", "Ink",
     [
       "oklch(12% 0.003 270)",
       "oklch(16% 0.004 270)",
       "oklch(20% 0.005 270)",
       "oklch(95% 0.012 85)",
       0.5,
       0.6,
       "#e84a1c",
       "#ff6b3d",
       "oklch(12% 0.003 270)",
       "oklch(72% 0.16 70)"
     ]},
    {"smoke", "Smoke",
     [
       "oklch(27% 0.005 270)",
       "oklch(30.5% 0.006 270)",
       "oklch(34% 0.007 270)",
       "oklch(92% 0.01 85)",
       0.62,
       0.7,
       "oklch(72% 0.13 168)",
       "oklch(78% 0.11 168)",
       "oklch(27% 0.005 270)",
       "oklch(72% 0.16 70)"
     ]},
    {"stone", "Stone",
     [
       "oklch(20% 0.006 70)",
       "oklch(23.5% 0.007 70)",
       "oklch(27% 0.008 70)",
       "oklch(95% 0.01 85)",
       0.52,
       0.62,
       "oklch(78% 0.13 82)",
       "oklch(83% 0.11 85)",
       "oklch(20% 0.006 70)",
       "oklch(72% 0.16 70)"
     ]},
    {"lacquer", "Lacquer",
     [
       "oklch(14% 0.022 25)",
       "oklch(18% 0.026 25)",
       "oklch(22% 0.03 25)",
       "oklch(93% 0.016 75)",
       0.53,
       0.6,
       "oklch(63% 0.21 24)",
       "oklch(70% 0.17 28)",
       "oklch(14% 0.022 25)",
       "oklch(72% 0.16 70)"
     ]},
    {"light", "Paper",
     [
       "oklch(96% 0.01 85)",
       "oklch(93% 0.012 85)",
       "oklch(89% 0.014 80)",
       "oklch(15% 0.003 270)",
       0.65,
       0.7,
       "#e84a1c",
       "#ff6b3d",
       "oklch(12% 0.003 270)",
       "oklch(68% 0.16 70)"
     ]},
    {"snow", "Snow",
     [
       "oklch(99.5% 0.001 270)",
       "oklch(97% 0.003 270)",
       "oklch(92.5% 0.005 270)",
       "oklch(20% 0.006 270)",
       0.65,
       0.7,
       "oklch(50% 0.17 262)",
       "oklch(58% 0.16 262)",
       "oklch(100% 0 0)",
       "oklch(68% 0.16 70)"
     ]},
    {"silk", "Silk",
     [
       "oklch(97.5% 0.012 350)",
       "oklch(95% 0.016 350)",
       "oklch(91.5% 0.02 350)",
       "oklch(22% 0.012 350)",
       0.65,
       0.7,
       "oklch(56% 0.21 358)",
       "oklch(64% 0.2 358)",
       "oklch(100% 0 0)",
       "oklch(68% 0.16 70)"
     ]}
  ]

  defp sumi_style(id) do
    {_, _, [page, surface, line, text, muted, secondary, blade, ember, on_blade, warning]} =
      List.keyfind(@sumi_themes, id, 0)

    """
    :root {
      --color-base-100: #{page}; --color-base-200: #{surface}; --color-base-300: #{line};
      --color-base-content: #{text}; --color-primary-content: #{on_blade};
      --sumi-text-muted: oklch(from #{text} l c h / #{muted});
      --sumi-text-secondary: oklch(from #{text} l c h / #{secondary});
      --color-sumi-blade: #{blade}; --color-sumi-ember: #{ember}; --color-warning: #{warning};
    }
    """
  end

  def root(assigns) do
    look = assigns.conn.params["sumi"]
    look = if List.keymember?(@sumi_themes, look, 0), do: look

    assigns =
      assign(assigns,
        sumi: assigns.conn.params["theme"] == "sumi" or look != nil,
        look: look,
        themes: @sumi_themes
      )

    ~H"""
    <!DOCTYPE html>
    <html lang="en" data-theme={@look}>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()} />
        <title>Kotoba development</title>
        <link rel="stylesheet" href="/assets/kotoba.css" />
        <link rel="stylesheet" href="/vendor/issho/issho.css" />
        <link :if={@sumi} rel="stylesheet" href="/assets/kotoba-sumi.css" />
        {@look && Phoenix.HTML.raw("<style>" <> sumi_style(@look) <> "</style>")}
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
              "kotoba": "/assets/kotoba.esm.js",
              "kotoba/collab": "/assets/kotoba-collab.esm.js",
              "issho": "/vendor/issho/issho.esm.js"
            }
          }
        </script>
        <script type="module">
          import { Socket } from "phoenix"
          import { LiveSocket } from "phoenix_live_view"
          import { Kotoba, registerCollaboration } from "kotoba"
          import { enableCollaboration } from "kotoba/collab"
          import { Hooks as IsshoHooks } from "issho"
          enableCollaboration(registerCollaboration)

          const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
          const liveSocket = new LiveSocket("/live", Socket, {
            hooks: { Kotoba, ...IsshoHooks },
            params: { _csrf_token: csrfToken }
          })
          liveSocket.connect()
          window.liveSocket = liveSocket
        </script>
      </head>
      <body class={@sumi && "sumi"}>
        <main>
          <nav>
            <a href="/">Editor</a><a href="/two">Two editors</a><a href="/nodes">Nodes</a><a href="/embeds">Embeds</a><a href="/collab">Collaboration</a><a href="/?theme=sumi">Sumi theme</a>
          </nav>
          <nav :if={@sumi} aria-label="Sumi's themes">
            Sumi: <a :for={{id, name, _} <- @themes} href={"?sumi=#{id}&sample=palette"} aria-current={@look == id && "page"}>{name}</a>
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
  The editor in a form, with the prompts of `KotobaDev.Prompts`, uploads
  and the Tag node. The `!` prompt always fails, so the menu says "Results
  did not load". The
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

  defp prompts, do: KotobaDev.Prompts.list()

  @impl true
  def mount(params, _session, socket) do
    body =
      case params["sample"] do
        nil -> nil
        "palette" -> KotobaDev.Sample.palette()
        _ -> KotobaDev.Sample.document("Initial")
      end

    {:ok,
     socket
     |> assign(
       form: to_form(%{"body" => body}, as: :post),
       stored: nil,
       readonly: false,
       invalid: false,
       changes: 0,
       push_changes: params["change"] != nil,
       # ?inline=true: the suggestions stream in the text, not in the panel.
       display: if(params["inline"] == "true", do: :inline, else: :panel),
       menu: params["menu"],
       blank_lines: if(params["blank_lines"] == "collapse", do: :collapse, else: :keep),
       validated: 0,
       validated_text: "",
       reverse: params["uploads"] == "reverse",
       hold: false,
       reject_next: false,
       assist_refs: MapSet.new(),
       suggestions: []
     )
     |> allow_upload(:body,
       accept: ~w(.png .jpg .jpeg .gif .webp .pdf .mp4 .webm),
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
        assist={KotobaDev.Assist.actions()}
        selection_menu={@menu == "default"}
        blank_lines={@blank_lines}
      >
        <:selection :if={@menu == "custom"}>
          <.kotoba_selection_menu id="custom-menu" class="custom-menu" label="Quick format">
            <:button command="bold">B</:button>
            <:button command="h2" label="Heading">H</:button>
          </.kotoba_selection_menu>
        </:selection>
      </.kotoba>
      <p :if={@invalid} id="body-error">Say something</p>
      <div class="row">
        <button type="submit" id="submit">Submit</button>
      </div>
    </.form>

    <div class="row" role="group" aria-label="Server events">
      <button type="button" id="load-sample" phx-click="load_sample">Load sample</button>
      <button :if={@stored} type="button" id="load-stored" phx-click="load_stored">
        Load stored
      </button>
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
      <button type="button" id="stream-summary" phx-click="stream_summary">Stream a summary</button>
    </div>
    <p id="suggestion-events">{Enum.join(@suggestions, " ")}</p>

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
    do: {:noreply, Kotoba.Live.handle_prompt(socket, params, prompts())}

  def handle_event("toggle_changes", _params, socket),
    do: {:noreply, update(socket, :push_changes, &(not &1))}

  def handle_event("load_sample", _params, socket),
    do: {:noreply, Kotoba.Live.push_content(socket, @editor, KotobaDev.Sample.document())}

  # The stored document back in the editor, as a page that edits a saved
  # record loads it.
  def handle_event("load_stored", _params, socket),
    do: {:noreply, Kotoba.Live.push_content(socket, @editor, socket.assigns.stored)}

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

  # A suggestion that the person asked for with the Assist menu.
  def handle_event("kotoba:assist", %{"ref" => ref, "action" => action, "text" => text}, socket),
    do:
      {:noreply,
       KotobaDev.Assist.start(socket, @editor, ref, action, text, display: socket.assigns.display)}

  # A suggestion that the server starts by itself, at the end.
  def handle_event("stream_summary", _params, socket) do
    ref = Kotoba.Live.stream_ref()

    socket =
      KotobaDev.Assist.start(socket, @editor, ref, "continue", "",
        at: :end,
        label: "Summary",
        display: socket.assigns.display
      )

    {:noreply, socket}
  end

  # The person accepted, rejected or stopped a suggestion: a stopped one
  # sends no more chunks.
  def handle_event("kotoba:suggestion", %{"ref" => ref, "action" => action}, socket) do
    socket = update(socket, :suggestions, &(&1 ++ [action]))
    {:noreply, if(action == "accept", do: socket, else: KotobaDev.Assist.stop(socket, ref))}
  end

  # The phx-change carries the document too (the hook's formdata listener).
  defp posted_text(%{"post" => %{"body" => body}}) do
    case Kotoba.Content.cast(body) do
      {:ok, content} -> content.text
      :error -> ""
    end
  end

  defp posted_text(_params), do: ""

  @impl true
  def handle_async({:kotoba_prompt, _id, _prompt, _query} = name, result, socket),
    do: {:noreply, Kotoba.Live.handle_prompt_async(socket, name, result)}

  @impl true
  def handle_info({:assist_chunk, id, ref, action, rest}, socket),
    do: {:noreply, KotobaDev.Assist.next(socket, id, ref, action, rest)}

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
          code_languages={~w(elixir erlang sql)}
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
    do:
      {:noreply,
       Kotoba.Live.push_content(socket, @editor, KotobaDev.Sample.document("Second", code: true))}
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

defmodule KotobaDev.EmbedsLive do
  @moduledoc """
  An editor with embeds: live polls of the app's own in the document, a
  picker to insert one (new, or one the app has), full screen, and the
  page that reads the document (`?read=1`). Kotoba renders no poll: the
  LiveView does, and its portals put each poll in its embed.
  """
  use Phoenix.LiveView

  import Kotoba.Components

  @start [
    %{
      id: "lunch",
      title: "Where do we have lunch?",
      options: [{"Ramen", 4}, {"Tacos", 2}, {"Salad", 1}]
    },
    %{id: "launch", title: "When do we launch?", options: [{"This week", 1}, {"Next week", 5}]}
  ]

  @impl true
  def mount(params, _session, socket) do
    doc = %{
      "type" => "root",
      "version" => 1,
      "direction" => nil,
      "format" => "",
      "indent" => 0,
      "children" => [
        paragraph("The team decides, live, in the document:"),
        %{
          "type" => "embed",
          "version" => 1,
          "kind" => "poll",
          "ref" => "lunch",
          "title" => "Where do we have lunch?"
        },
        paragraph("Vote in the poll; open it full screen; insert another from the toolbar.")
      ]
    }

    {:ok,
     assign(socket,
       form: to_form(%{"body" => JSON.encode!(doc)}, as: :doc),
       polls: Map.new(@start, &{&1.id, &1}),
       read: params["read"] == "1"
     )}
  end

  defp paragraph(text) do
    %{
      "type" => "paragraph",
      "version" => 1,
      "direction" => nil,
      "format" => "",
      "indent" => 0,
      "textFormat" => 0,
      "textStyle" => "",
      "children" => [
        %{
          "type" => "text",
          "version" => 1,
          "text" => text,
          "format" => 0,
          "detail" => 0,
          "mode" => "normal",
          "style" => ""
        }
      ]
    }
  end

  @impl true
  def handle_event("vote", %{"poll" => id, "option" => option}, socket) do
    {:noreply,
     update(socket, :polls, fn polls ->
       Map.update!(polls, id, fn poll ->
         %{
           poll
           | options:
               Enum.map(poll.options, fn {o, n} ->
                 if o == option, do: {o, n + 1}, else: {o, n}
               end)
         }
       end)
     end)}
  end

  def handle_event("insert_poll", %{"id" => id}, socket),
    do:
      {:noreply,
       Kotoba.Live.insert_embed(socket, "embeds-body", "poll", id,
         title: socket.assigns.polls[id].title
       )}

  def handle_event("new_poll", _params, socket) do
    id = "poll-#{System.unique_integer([:positive])}"
    poll = %{id: id, title: "A new question", options: [{"Yes", 0}, {"No", 0}]}

    {:noreply,
     socket
     |> update(:polls, &Map.put(&1, id, poll))
     |> Kotoba.Live.insert_embed("embeds-body", "poll", id, title: poll.title)}
  end

  def handle_event("change", _params, socket), do: {:noreply, socket}

  # A link to a poll of this app (…/polls/lunch) is the poll.
  defp resolve(url, polls) do
    with %URI{path: "/polls/" <> id} <- URI.parse(url),
         %{title: title} <- polls[id] do
      %{kind: "poll", ref: id, title: title}
    else
      _other -> nil
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <style>
      .poll { display: flex; flex-direction: column; height: 100%; border: 1px solid var(--kotoba-border); border-radius: 12px; background: var(--kotoba-background); font-family: var(--kotoba-font); }
      .poll header { display: flex; align-items: center; gap: 8px; padding: 10px 10px 10px 16px; border-bottom: 1px solid var(--kotoba-border); }
      .poll header strong { flex: 1; font-weight: 500; }
      .poll header button { display: grid; place-items: center; width: 30px; height: 30px; border: 0; border-radius: 6px; background: none; color: var(--kotoba-muted); cursor: pointer; }
      .poll header button:hover { background: var(--kotoba-surface); color: var(--kotoba-text); }
      .poll ul { list-style: none; margin: 0; padding: 12px 16px; display: grid; gap: 8px; overflow: auto; }
      .poll li button { position: relative; display: flex; justify-content: space-between; width: 100%; padding: 10px 12px; border: 1px solid var(--kotoba-border); border-radius: 8px; background: none; font: inherit; color: inherit; cursor: pointer; overflow: hidden; }
      .poll li button:disabled { cursor: default; }
      .poll li button i { position: absolute; inset: 0 auto 0 0; background: color-mix(in oklab, var(--kotoba-accent) 14%, transparent); }
      .poll li button span { position: relative; }
      .kotoba-embed-slot:has(.poll) { --kotoba-embed-height: 15rem; height: auto; min-height: 12rem; }
    </style>
    <h1>Embeds</h1>
    <p>
      <a href="/embeds">Write</a> · <a href="/embeds?read=1">Read</a>
    </p>
    <.form for={@form} id="embeds-form" phx-change="change">
      <.kotoba
        field={@form[:body]}
        id="embeds-body"
        label="Notes"
        embeds
        readonly={@read}
        show_toolbar={!@read}
      />
    </.form>
    <.kotoba_embeds
      for="embeds-body"
      label="Poll"
      icon="chart"
      picker_title="Insert a poll"
      readonly={@read}
      resolve={&resolve(&1, @polls)}
    >
      <:embed :let={embed}>
        <.poll poll={@polls[embed.ref]} embed={embed} />
      </:embed>
      <:picker>
        <h3>New</h3>
        <.kotoba_embed_option id="new-poll" phx-click="new_poll" title="A new poll" about="Yes or no, to start with">
          <:icon><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M5 12h14" /><path d="M12 5v14" /></svg></:icon>
        </.kotoba_embed_option>
        <h3>Polls</h3>
        <.kotoba_embed_option
          :for={{id, poll} <- @polls}
          phx-click="insert_poll"
          phx-value-id={id}
          title={poll.title}
          about={"#{length(poll.options)} options"}
        >
          <:icon><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M3 3v16a2 2 0 0 0 2 2h16" /><path d="M18 17V9" /><path d="M13 17V5" /><path d="M8 17v-3" /></svg></:icon>
        </.kotoba_embed_option>
      </:picker>
    </.kotoba_embeds>
    """
  end

  attr :poll, :map, default: nil
  attr :embed, :map, required: true

  defp poll(%{poll: nil} = assigns), do: ~H"<p class=\"poll\">This poll is gone.</p>"

  defp poll(assigns) do
    assigns =
      assign(
        assigns,
        :total,
        assigns.poll.options |> Enum.map(&elem(&1, 1)) |> Enum.sum() |> max(1)
      )

    ~H"""
    <section class="poll" id={"poll-" <> @embed.id} data-full={to_string(@embed.full)}>
      <header>
        <strong>{@poll.title}</strong>
        <button
          type="button"
          class="poll-full"
          phx-click={@embed.toggle_full}
          aria-label={if @embed.full, do: "Exit full screen", else: "Full screen"}
        >
          <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true">
            <path :if={!@embed.full} d="M15 3h6v6M21 3l-7 7M3 21l7-7M9 21H3v-6" />
            <path :if={@embed.full} d="m14 10 7-7M20 10h-6V4M3 21l7-7M4 14h6v6" />
          </svg>
        </button>
      </header>
      <ul>
        <li :for={{option, votes} <- @poll.options}>
          <button
            type="button"
            phx-click="vote"
            phx-value-poll={@poll.id}
            phx-value-option={option}
            disabled={@embed.readonly}
          >
            <i style={"width: #{round(votes * 100 / @total)}%"}></i>
            <span>{option}</span>
            <span>{votes}</span>
          </button>
        </li>
      </ul>
    </section>
    """
  end
end

defmodule KotobaDev.ExtensionsLive do
  @moduledoc """
  Features and extensions. The comment editor has four features and the
  example extension (a callout); its changeset refuses a document with
  another feature. The notes editor has every feature and no extension.
  The formats editor has the text formats, in a toolbar of the app that
  has subscript and superscript.
  `?case=broken` adds an extension whose register throws and one that does
  not load: the editor still mounts, with the callout.
  """
  use Phoenix.LiveView

  import Kotoba.Components

  @features ~w(bold italic links lists)
  @callout "/assets/nodes/callout.js"
  @broken ["/assets/nodes/broken_extension.js", "/assets/nodes/missing_extension.js"]

  @impl true
  def mount(params, _session, socket) do
    extensions = if params["case"] == "broken", do: @broken ++ [@callout], else: [@callout]

    {:ok,
     assign(socket,
       form: to_form(%{"body" => nil}, as: :comment),
       notes: to_form(%{"body" => nil}, as: :notes),
       formats: to_form(%{"body" => nil}, as: :formats),
       extensions: extensions,
       shown: true,
       error: nil,
       saved: nil
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h1>Features and extensions</h1>
    <.form :if={@shown} for={@form} id="comment-form" phx-change="validate" phx-submit="save">
      <label id="comment-label" class="label">Comment</label>
      <.kotoba
        field={@form[:body]}
        id="comment_editor"
        label_id="comment-label"
        features={features()}
        extensions={@extensions}
      />
      <p :if={@error} id="comment-error">{@error}</p>
      <p :if={@saved} id="comment-saved">{@saved}</p>
      <button type="submit" id="comment-submit">Save</button>
    </.form>
    <div class="row">
      <button type="button" id="toggle-comment" phx-click="toggle">Toggle the comment editor</button>
      <button type="button" id="load-comment" phx-click="load">Load the sample</button>
    </div>
    <.form for={@notes} id="notes-form">
      <label id="notes-label" class="label">Notes</label>
      <.kotoba field={@notes[:body]} id="notes_editor" label_id="notes-label" />
    </.form>
    <.form for={@formats} id="formats-form">
      <label id="formats-label" class="label">Formats</label>
      <.kotoba
        field={@formats[:body]}
        id="formats_editor"
        label_id="formats-label"
        features={~w(bold italic underline strikethrough highlight subscript superscript)}
      >
        <:toolbar>
          <.kotoba_toolbar commands={
            ~w(bold italic underline strikethrough highlight subscript superscript code undo)
          } />
        </:toolbar>
      </.kotoba>
    </.form>
    """
  end

  defp features, do: @features

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("save", %{"comment" => %{"body" => body}}, socket) do
    changeset =
      {%{}, %{body: Kotoba.Content}}
      |> Ecto.Changeset.cast(%{"body" => body}, [:body])
      |> Kotoba.Content.validate_features(:body, @features)

    case Ecto.Changeset.apply_action(changeset, :insert) do
      {:ok, %{body: content}} ->
        {:noreply, assign(socket, error: nil, saved: content && content.text)}

      {:error, changeset} ->
        [{:body, {message, keys}} | _] = changeset.errors

        {:noreply,
         assign(socket, saved: nil, error: String.replace(message, "%{names}", keys[:names]))}
    end
  end

  def handle_event("toggle", _params, socket), do: {:noreply, update(socket, :shown, &(not &1))}

  def handle_event("load", _params, socket),
    do:
      {:noreply, Kotoba.Live.push_content(socket, "comment_editor", KotobaDev.Sample.document())}
end

defmodule KotobaDev.BlocksLive do
  @moduledoc """
  The block handles (the `blocks` feature). The first editor has the
  block features and the example extension (a callout, which Turn into
  offers); the second has no headings, so its menu offers none; the third
  has no `blocks`, and no handles.
  """
  use Phoenix.LiveView

  import Kotoba.Components

  @sample """
  # Plan

  First paragraph

  Second paragraph

  - One
  - Two

  > A quote

  | Language | Year |
  | --- | --- |
  | Elixir | 2012 |
  """

  @features ~w(bold italic links headings quotes lists check_lists code_blocks horizontal_rules tables blocks)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       blocks: to_form(%{"body" => Kotoba.Content.from_markdown(@sample)}, as: :blocks),
       plain:
         to_form(%{"body" => Kotoba.Content.from_markdown("One\n\nTwo\n\nThree")}, as: :plain),
       none: to_form(%{"body" => Kotoba.Content.from_markdown("One\n\nTwo")}, as: :none)
     )}
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :features, @features)

    ~H"""
    <h1>Blocks</h1>
    <.form for={@blocks} id="blocks-form">
      <label id="blocks-label" class="label">Blocks</label>
      <.kotoba
        field={@blocks[:body]}
        id="blocks_editor"
        label_id="blocks-label"
        features={@features}
        extensions={["/assets/nodes/callout.js"]}
      />
    </.form>
    <.form for={@plain} id="plain-form">
      <label id="plain-label" class="label">No headings</label>
      <.kotoba field={@plain[:body]} id="plain_editor" label_id="plain-label" features={~w(bold italic lists blocks)} />
    </.form>
    <.form for={@none} id="none-form">
      <label id="none-label" class="label">No blocks</label>
      <.kotoba field={@none[:body]} id="none_editor" label_id="none-label" features={~w(bold italic lists)} />
    </.form>
    """
  end
end

defmodule KotobaDev.InsertLive do
  @moduledoc """
  The insert menu: a prompt with `insert: :command`. The first editor has
  the built-in items of its features, the example extension's callout, and
  the app's own (a tag node, a snippet), in groups, and the block handles,
  whose `+` opens the menu. The second has fewer features, so fewer items,
  and turns a block with text into the new one. The third searches on the
  server.
  """
  use Phoenix.LiveView

  import Kotoba.Components

  @features ~w(bold italic links headings quotes lists check_lists code_blocks horizontal_rules tables blocks)
  @small ~w(bold lists)

  @menu [
    items: [
      :builtin,
      :extensions,
      %{
        id: "tag",
        label: "Tag",
        group: "The app's",
        node: %{type: "dev-tag", label: "from the menu"},
        keywords: ["label"]
      },
      %{
        id: "signature",
        label: "Signature",
        group: "The app's",
        text: "— Ada",
        keywords: ["sign"]
      },
      %{id: "continue", label: "Continue writing", group: "Assist", assist: "continue"},
      %{
        id: "summarize",
        label: "Summarize",
        group: "Assist",
        assist: "summarize",
        keywords: ["ai"]
      }
    ],
    insert: :command,
    label: "Insert"
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       insert: to_form(%{"body" => Kotoba.Content.from_markdown("First paragraph")}, as: :insert),
       small: to_form(%{"body" => Kotoba.Content.from_markdown("Some text")}, as: :small),
       search: to_form(%{"body" => nil}, as: :search),
       assist_refs: MapSet.new()
     )}
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, features: @features, small_features: @small, menu: @menu)

    ~H"""
    <h1>Insert menu</h1>
    <.form for={@insert} id="insert-form">
      <label id="insert-label" class="label">Insert</label>
      <.kotoba
        field={@insert[:body]}
        id="insert_editor"
        label_id="insert-label"
        features={@features}
        extensions={["/assets/nodes/callout.js"]}
        nodes={[{KotobaDev.Nodes.Tag, "/assets/nodes/tag.js"}]}
        prompts={[{"/", :insert, @menu}]}
        assist={true}
      />
    </.form>
    <.form for={@small} id="small-form">
      <label id="small-label" class="label">Fewer features</label>
      <.kotoba
        field={@small[:body]}
        id="small_editor"
        label_id="small-label"
        features={@small_features}
        prompts={[{"/", :insert, insert: :command, with_text: :turn_into}]}
      />
    </.form>
    <.form for={@search} id="search-form">
      <label id="search-label" class="label">Server search</label>
      <.kotoba field={@search[:body]} id="search_editor" label_id="search-label" prompts={search()} />
    </.form>
    """
  end

  # The built-in items of an editor with every feature, found on the server.
  defp search,
    do: [
      {"/", :insert,
       [
         search: fn query -> Kotoba.Prompts.filter(Kotoba.Prompts.commands(), query) end,
         insert: :command
       ]}
    ]

  @impl true
  def handle_event("kotoba:prompt", params, socket),
    do: {:noreply, Kotoba.Live.handle_prompt(socket, params, search())}

  # An Assist item of the menu: the fake model streams its answer after the
  # block where "/" was.
  def handle_event("kotoba:assist", %{"ref" => ref, "action" => action} = params, socket),
    do:
      {:noreply,
       KotobaDev.Assist.start(socket, "insert_editor", ref, action, params["block"] || "",
         at: :after
       )}

  def handle_event("kotoba:suggestion", %{"ref" => ref, "action" => action}, socket),
    do: {:noreply, if(action == "accept", do: socket, else: KotobaDev.Assist.stop(socket, ref))}

  @impl true
  def handle_info({:assist_chunk, id, ref, action, rest}, socket),
    do: {:noreply, KotobaDev.Assist.next(socket, id, ref, action, rest)}
end

defmodule KotobaDev.Writer do
  @moduledoc """
  The recipe of the Suggestions guide, "A stream that outlives the page":
  a fake model that writes a long answer (four characters every 40 ms) in
  a process of the app's, not of the LiveView. It keeps the text so far and
  broadcasts each chunk on `KotobaDev.PubSub`, so that a LiveView that
  mounts while it writes resumes it. It goes on while no page is open, and
  waits a minute after its end for the person to come back and accept it.

  Its key is the app's: here the page's `?key=` (a user and a document in
  an app), so that one person's answer never shows to another.
  """
  use GenServer, restart: :temporary

  @answer "## Summary\n\n" <>
            String.duplicate("The plan holds, and the **next step** is clear. ", 8)
  @wait :timer.minutes(1)

  def topic(key), do: "writer:" <> key

  @doc "Starts the answer of `ref` for `key`, asked at `place` (the request's)."
  def start(key, ref, place) do
    DynamicSupervisor.start_child(
      KotobaDev.Writers,
      {__MODULE__, %{key: key, ref: ref, place: place}}
    )
  end

  @doc "The answer of `key`, if one is writing or waits to be accepted."
  def lookup(key) do
    case Registry.lookup(KotobaDev.WriterRegistry, key) do
      [{pid, _}] -> {:ok, GenServer.call(pid, :state)}
      [] -> :none
    end
  catch
    :exit, _reason -> :none
  end

  @doc "Stops the answer of `key`: the person accepted, rejected or stopped it."
  def stop(key) do
    case Registry.lookup(KotobaDev.WriterRegistry, key) do
      [{pid, _}] -> GenServer.stop(pid)
      [] -> :ok
    end
  catch
    :exit, _reason -> :ok
  end

  def start_link(%{key: key} = args),
    do:
      GenServer.start_link(__MODULE__, args,
        name: {:via, Registry, {KotobaDev.WriterRegistry, key}}
      )

  @impl true
  def init(args) do
    Process.send_after(self(), :write, 40)
    {:ok, Map.merge(args, %{text: "", rest: @answer, done: false})}
  end

  @impl true
  def handle_call(:state, _from, state),
    do: {:reply, Map.take(state, [:ref, :place, :text, :done]), state}

  @impl true
  def handle_info(:write, %{rest: ""} = state) do
    Phoenix.PubSub.broadcast(KotobaDev.PubSub, topic(state.key), {:writer, state.ref, :end})
    Process.send_after(self(), :expire, @wait)
    {:noreply, %{state | done: true}}
  end

  def handle_info(:write, state) do
    {chunk, rest} = String.split_at(state.rest, 4)

    Phoenix.PubSub.broadcast(
      KotobaDev.PubSub,
      topic(state.key),
      {:writer, state.ref, {:chunk, chunk}}
    )

    Process.send_after(self(), :write, 40)
    {:noreply, %{state | text: state.text <> chunk, rest: rest}}
  end

  def handle_info(:expire, state), do: {:stop, :normal, state}
end

defmodule KotobaDev.ResumeLive do
  @moduledoc """
  A suggestion that outlives the page: Summarize asks `KotobaDev.Writer`;
  leave the page while it writes, come back (`?key=` the same), and the
  answer is further on, still streaming or waiting to be accepted.
  """
  use Phoenix.LiveView

  import Kotoba.Components

  @editor "resume_editor"
  @document "Meeting notes\n\nWe agreed on the plan for the launch."

  @impl true
  def mount(params, _session, socket) do
    key = Map.get(params, "key", "demo")

    socket =
      assign(socket,
        key: key,
        form: to_form(%{"body" => Kotoba.Content.from_markdown(@document)}, as: :resume)
      )

    {:ok, if(connected?(socket), do: resume(socket), else: socket)}
  end

  # Subscribes to the person's answers, and resumes the one that writes or
  # waits: its text so far, after the block it was asked at.
  defp resume(socket) do
    Phoenix.PubSub.subscribe(KotobaDev.PubSub, KotobaDev.Writer.topic(socket.assigns.key))

    case KotobaDev.Writer.lookup(socket.assigns.key) do
      {:ok, answer} ->
        socket =
          Kotoba.Live.stream_resume(socket, @editor, answer.ref, answer.text,
            at: :after,
            block: block(answer.place),
            label: "Summary"
          )

        if answer.done, do: Kotoba.Live.stream_end(socket, @editor, answer.ref), else: socket

      :none ->
        socket
    end
  end

  # The request's place: the shared id in a shared document, else the number.
  defp block(%{"id" => id}), do: id
  defp block(%{"block" => n}), do: n
  defp block(_place), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <h1>A stream that outlives the page</h1>
    <.form for={@form} id="resume-form">
      <.kotoba
        field={@form[:body]}
        id="resume_editor"
        label="Notes"
        assist={[summarize: "Summarize"]}
      />
    </.form>
    <.link navigate="/blocks" id="leave">Go to another page</.link>
    """
  end

  @impl true
  def handle_event("kotoba:assist", %{"ref" => ref} = params, socket) do
    KotobaDev.Writer.stop(socket.assigns.key)
    {:ok, _pid} = KotobaDev.Writer.start(socket.assigns.key, ref, params["place"])
    {:noreply, Kotoba.Live.stream_start(socket, @editor, ref, at: :after, label: "Summary")}
  end

  # An editor that went away (the person left the page) does not stop the
  # answer: it waits for them. Accept, Reject and Stop do.
  def handle_event("kotoba:suggestion", %{"gone" => true}, socket), do: {:noreply, socket}

  def handle_event("kotoba:suggestion", _params, socket) do
    KotobaDev.Writer.stop(socket.assigns.key)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:writer, ref, {:chunk, text}}, socket),
    do: {:noreply, Kotoba.Live.stream_chunk(socket, @editor, ref, text)}

  def handle_info({:writer, ref, :end}, socket),
    do: {:noreply, Kotoba.Live.stream_end(socket, @editor, ref)}
end

defmodule KotobaDev.Collaboration do
  @moduledoc false
  # The Issho policy. Demo only: production authorization consults the
  # application's own permissions for the identity (`key` is the user's id).
  @behaviour Issho.Policy

  @impl true
  def authorize(_identity, _document_id, _action), do: :ok

  @impl true
  def document(_identity, _document_id),
    do: Kotoba.Issho.document(store: {Kotoba.Collab.Store.Memory, KotobaDev.CollabStore})
end

defmodule KotobaDev.IsshoChannel do
  use Issho.Channel, instance: KotobaDev.Issho
end

defmodule KotobaDev.CollabSocket do
  use Phoenix.Socket
  channel("issho:*", KotobaDev.IsshoChannel)
  def connect(_params, socket, _connect_info), do: {:ok, socket}
  def id(_socket), do: nil
end

# A collaboration socket with a small channel limit, for the e2e tests of socket sharing.
defmodule KotobaDev.SmallCollabSocket do
  use Phoenix.Socket, max_channels_per_transport: 5
  channel("issho:*", KotobaDev.IsshoChannel)
  def connect(_params, socket, _connect_info), do: {:ok, socket}
  def id(_socket), do: nil
end

defmodule KotobaDev.CollabLive do
  use Phoenix.LiveView
  on_mount(Issho.Live)
  import Kotoba.Components

  def mount(params, _session, socket) do
    id = Map.get(params, "document", "demo")
    name = Map.get(params, "name", "Ada")
    user = %{id: name, name: name, color: if(name == "Ada", do: "#2563eb", else: "#be185d")}
    role = if params["role"] == "read", do: :read, else: :write

    issho = [
      instance: KotobaDev.Issho,
      document: id,
      can: role,
      follow: params["follow"] != "false"
    ]

    socket =
      assign(socket,
        document_id: id,
        user: user,
        role: role,
        issho: issho,
        # ?blocks=true: the block handles, with every feature.
        features: if(params["blocks"] == "true", do: Kotoba.Features.all()),
        form: to_form(%{"body" => nil}, as: :shared),
        saved: nil,
        assist_refs: MapSet.new(),
        room: Issho.Policy.room(id),
        # Whom a comment may mention besides the people here.
        mentionable: [%{key: "Linus", name: "Linus"}],
        events: []
      )

    # Issho's streams for this person, as suggestions in the editor.
    socket = Kotoba.Issho.suggestions(socket, user, %{"shared_editor" => issho})

    # The document's changes, as the room's events (Kotoba.Issho.events/2).
    if connected?(socket),
      do: Issho.Live.subscribe(socket.assigns.room, :self, events: ["text.*"])

    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <h1>Shared document</h1>
    <p>Open this document in another tab with a different <code>?name=</code> to collaborate.</p>
    <.form for={@form} id="collab-form" phx-submit="save">
      <.kotoba field={@form[:body]} id="shared_editor" label="Shared document" issho={@issho} user={@user} nodes={["/assets/nodes/tag.js"]} features={@features} assist={[summarize: "Summarize"]} />
      <button type="submit" id="collab-save">Publish accepted revision</button>
    </.form>
    <button id="collab-insert" phx-click="insert">Insert tag</button>
    <button id="collab-attach" phx-click="attach">Insert image</button>
    <button id="collab-summary" phx-click="summary">Stream a summary in the text</button>
    <.kotoba_content :if={@saved} content={@saved} id="collab-saved" />
    <p :if={@saved} id="collab-saved-text">{@saved.text}</p>
    <h2>Changes</h2>
    <ol id="collab-events" aria-label="Changes">
      <li :for={event <- @events}>{event.name}: {event.data.type} {event.data[:n]}</li>
    </ol>
    <Issho.Components.comments id="comments" room={@room} mentionable={@mentionable} read={&Kotoba.Issho.read_comment/1}>
      <:input :let={input}>
        <.kotoba
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

  # The @ of a comment: the room's people, and mentionable.
  def handle_event("kotoba:prompt", params, socket) do
    prompts = Kotoba.Issho.comment_prompts(socket.assigns.room, socket.assigns.mentionable)
    {:noreply, Kotoba.Live.handle_prompt(socket, params, prompts)}
  end

  def handle_event("save", %{"kotoba_collab" => %{"shared_editor" => json}}, socket) do
    with {:ok, revision} <- JSON.decode(json),
         {:ok, content} <-
           Kotoba.Collab.content(KotobaDev.Issho, socket.assigns.document_id, revision) do
      {:noreply, assign(socket, saved: content)}
    else
      _ -> {:noreply, put_flash(socket, :error, "The revision is unavailable")}
    end
  end

  def handle_event("insert", _params, socket),
    do:
      {:noreply,
       Kotoba.Live.insert_node(socket, "shared_editor", %KotobaDev.Nodes.Tag{label: "shared"})}

  # A suggestion in the text: only this person sees it, until they accept it.
  def handle_event("summary", _params, socket),
    do:
      {:noreply,
       KotobaDev.Assist.start(socket, "shared_editor", Kotoba.Live.stream_ref(), "continue", "",
         at: :end,
         label: "Summary",
         display: :inline
       )}

  def handle_event("kotoba:suggestion", %{"ref" => ref, "action" => action}, socket),
    do: {:noreply, if(action == "accept", do: socket, else: KotobaDev.Assist.stop(socket, ref))}

  # Summarize writes an Issho stream for this person, after the block of the
  # request, in a task of its own: the page shows it with
  # Kotoba.Issho.suggestions/4, and finds it again after going away.
  def handle_event("kotoba:assist", %{"place" => %{"id" => block}}, socket) do
    %{user: user, document_id: document} = socket.assigns
    place = %{"doc" => document, "at" => %{"node" => block}}

    Task.start(fn ->
      {:ok, stream} =
        Issho.Streams.start(KotobaDev.Issho, Issho.Policy.room(document),
          kind: "summary",
          for: user,
          place: place,
          meta: %{"label" => "Summary"}
        )

      for chunk <- ["Resumed ", "after ", "its ", "block"] do
        Process.sleep(300)
        :ok = Issho.Streams.append(stream, chunk)
      end

      Issho.Streams.finish(stream)
    end)

    {:noreply, socket}
  end

  def handle_info({:assist_chunk, id, ref, action, rest}, socket),
    do: {:noreply, KotobaDev.Assist.next(socket, id, ref, action, rest)}

  # The last changes of the document, newest first; the room's other messages.
  def handle_info({Issho.Live, "event", _room, %Issho.Event{} = event}, socket),
    do: {:noreply, assign(socket, events: Enum.take([event | socket.assigns.events], 5))}

  def handle_info({Issho.Live, _event, _key, _payload}, socket), do: {:noreply, socket}

  # An image attachment, for the shared caption (its file is not stored).
  def handle_event("attach", _params, socket),
    do:
      {:noreply,
       Kotoba.Live.insert_node(socket, "shared_editor", %Kotoba.Nodes.Attachment{
         key: "dev/shared.png",
         url: "/uploads/kotoba/dev/shared.png",
         name: "shared.png",
         content_type: "image/png",
         bytes: 1024,
         width: 160,
         height: 90
       })}
end

defmodule KotobaDev.ManyCollabLive do
  @moduledoc false
  # Many shared editors on one page, as in a document of many text blocks:
  # /collab/many?document=ID&count=20&name=Ada. ?repeat=1 adds a last editor of
  # the first editor's document; ?socket=small signs for KotobaDev.SmallCollabSocket.
  use Phoenix.LiveView
  on_mount(Issho.Live)
  import Kotoba.Components

  # Nested (KotobaDev.NestedCollabLive): the page's query comes in the session.
  def mount(:not_mounted_at_router, %{"params" => params}, socket), do: mount(params, %{}, socket)

  def mount(params, _session, socket) do
    prefix = Map.get(params, "document", "many")
    count = params |> Map.get("count", "3") |> String.to_integer() |> max(1) |> min(120)
    name = Map.get(params, "name", "Ada")
    user = %{id: name, name: name}
    ids = Enum.map(1..count, &"#{prefix}-#{&1}")
    # Each editor is {document id, number}; the number makes its DOM id.
    editors = Enum.with_index(ids, 1)
    editors = if params["repeat"], do: editors ++ [{hd(ids), count + 1}], else: editors

    signing =
      if params["socket"] == "small",
        do: [socket: "/issho/small-socket", max_channels: 5],
        else: []

    {:ok,
     assign(socket,
       prefix: prefix,
       editors: editors,
       next: length(editors) + 1,
       signing: signing,
       user: user,
       form: to_form(%{}, as: :many)
     )}
  end

  def render(assigns) do
    ~H"""
    <h1>Many shared editors</h1>
    <button id="many-remove" phx-click="remove">Remove the last editor</button>
    <button id="many-add" phx-click="add">Add an editor</button>
    <.form for={@form} id="many-form">
      <div :for={{id, index} <- @editors} style="min-height: 60vh">
        <.kotoba field={@form["body_#{index}"]} id={"editor_#{index}"} label={"Block #{index}"} issho={[instance: KotobaDev.Issho, document: id] ++ @signing} user={@user} />
      </div>
    </.form>
    """
  end

  def handle_event("remove", _params, socket),
    do: {:noreply, assign(socket, editors: Enum.drop(socket.assigns.editors, -1))}

  def handle_event("add", _params, socket) do
    # A document no editor of the page has had.
    n = socket.assigns.next
    id = "#{socket.assigns.prefix}-#{n}"

    {:noreply, assign(socket, editors: socket.assigns.editors ++ [{id, n}], next: n + 1)}
  end
end

defmodule KotobaDev.NestedCollabLive do
  @moduledoc false
  # The many-editors page as a nested LiveView, under a page with a shared
  # editor of its own: /collab/nested?document=ID&count=3&name=Ada.
  use Phoenix.LiveView
  on_mount(Issho.Live)
  import Kotoba.Components

  def mount(params, _session, socket) do
    prefix = Map.get(params, "document", "nested")
    name = Map.get(params, "name", "Ada")
    id = "#{prefix}-parent"
    user = %{id: name, name: name}

    {:ok,
     assign(socket,
       params: params,
       document_id: id,
       user: user,
       form: to_form(%{}, as: :parent)
     )}
  end

  def render(assigns) do
    ~H"""
    <h1>Nested shared editors</h1>
    <.kotoba field={@form[:body]} id="parent_editor" label="Parent" issho={[instance: KotobaDev.Issho, document: @document_id]} user={@user} />
    {live_render(@socket, KotobaDev.ManyCollabLive, id: "nested", session: %{"params" => @params})}
    """
  end
end

defmodule KotobaDev.NotebookLive do
  @moduledoc false
  # Two shared editors of one room, as two blocks of a notebook:
  # /collab/notebook?document=ID&name=Ada. A person's cursor goes from one
  # to the other.
  use Phoenix.LiveView
  on_mount(Issho.Live)
  import Kotoba.Components

  @blocks ~w(one two)

  def mount(params, _session, socket) do
    notebook = Map.get(params, "document", "notebook")
    name = Map.get(params, "name", "Ada")
    user = %{id: name, name: name, color: if(name == "Ada", do: "#2563eb", else: "#be185d")}

    # The page lists the people, once: the editors do not.
    issho =
      Map.new(
        @blocks,
        &{&1,
         [
           instance: KotobaDev.Issho,
           document: "#{notebook}/#{&1}",
           people: false,
           undo: if(params["undo"] == "false", do: false, else: :page)
         ]}
      )

    {:ok,
     assign(socket,
       notebook: notebook,
       user: user,
       issho: issho,
       grant: Issho.Live.grant(KotobaDev.Issho, user, notebook),
       form: to_form(%{}, as: :notebook)
     )}
  end

  def render(assigns) do
    assigns = assign(assigns, :blocks, @blocks)

    ~H"""
    <h1>Notebook</h1>
    <Issho.Components.people id="notebook-people" grant={@grant} />
    <Issho.Components.pointers id="notebook-pointers" grant={@grant} />
    <.form for={@form} id="notebook-form">
      <.kotoba :for={block <- @blocks} field={@form[block]} id={"notebook_#{block}"} label={"Block #{block}"} issho={@issho[block]} user={@user} />
    </.form>
    <p id="notebook-note">A note beside the editors, in plain HEEx.</p>
    <p id="notebook-secret" data-issho-private>Only for you.</p>
    """
  end
end

defmodule KotobaDev.ApartLive do
  @moduledoc false
  # Two shared editors of two rooms on one page, independent of each
  # other: /collab/apart?first=ID&second=ID&name=Ada. Each lists its own
  # people, and a cursor stays in its own editor.
  use Phoenix.LiveView
  on_mount(Issho.Live)
  import Kotoba.Components

  def mount(params, _session, socket) do
    name = Map.get(params, "name", "Ada")
    user = %{id: name, name: name, color: if(name == "Ada", do: "#2563eb", else: "#be185d")}

    rooms = %{
      "first" => Map.get(params, "first", "notes"),
      "second" => Map.get(params, "second", "drafts")
    }

    issho =
      Map.new(rooms, fn {block, room} -> {block, [instance: KotobaDev.Issho, document: room]} end)

    {:ok, assign(socket, issho: issho, user: user, form: to_form(%{}, as: :apart))}
  end

  def render(assigns) do
    ~H"""
    <h1>Two rooms</h1>
    <.form for={@form} id="apart-form">
      <.kotoba :for={block <- ~w(first second)} field={@form[block]} id={"apart_#{block}"} label={"The #{block} room"} issho={@issho[block]} user={@user} />
    </.form>
    """
  end
end

defmodule KotobaDev.MCP do
  @moduledoc false
  # MCP for agents: Issho's room tools and Kotoba's text tools, at /mcp,
  # with no authorization (development only): an agent is named for its
  # client and acts as itself. Claude Code connects with
  # `claude mcp add --transport http kotoba-dev http://localhost:4099/mcp`.
  use Issho.MCP,
    name: "kotoba-dev",
    version: "0.0.0",
    tools: Issho.Tools.room() ++ Kotoba.Issho.tools()
end

defmodule KotobaDev.AgentPlug do
  @moduledoc false
  # For the browser tests: calls a tool of /mcp as an MCP client does, over
  # HTTP, with Sake's client. POST {"tool": ..., "arguments": {...}}.
  @behaviour Plug

  def init(opts), do: opts

  def call(conn, _opts) do
    %{"tool" => tool, "arguments" => arguments} = conn.body_params
    url = "http://127.0.0.1:#{conn.port}/mcp"

    {:ok, session} =
      Sake.Client.connect(url, client_info: %{"name" => "claude-code", "title" => "Claude Code"})

    reply =
      case Sake.Client.call_tool(session, tool, arguments) do
        {:ok, %{is_error: true, text: text}, _session} -> %{"error" => text}
        {:ok, result, _session} -> %{"result" => result.structured || result.text}
        {:error, reason, _session} -> %{"error" => inspect(reason)}
      end

    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(200, JSON.encode!(reply))
  end
end

defmodule KotobaDev.Router do
  use Phoenix.Router

  import Phoenix.LiveView.Router
  import Sake.Router

  pipeline :browser do
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:protect_from_forgery)
    plug(:put_root_layout, html: {KotobaDev.Layouts, :root})
  end

  scope "/" do
    sake_endpoint("/mcp", server: KotobaDev.MCP, secret: String.duplicate("kotoba-dev-mcp-", 4))
    post("/dev/agent", KotobaDev.AgentPlug, [])
  end

  scope "/" do
    pipe_through(:browser)

    live("/", KotobaDev.EditorLive)
    live("/two", KotobaDev.TwoEditorsLive)
    live("/nodes", KotobaDev.NodesLive)
    live("/extensions", KotobaDev.ExtensionsLive)
    live("/blocks", KotobaDev.BlocksLive)
    live("/insert", KotobaDev.InsertLive)
    live("/resume", KotobaDev.ResumeLive)
    live("/embeds", KotobaDev.EmbedsLive)
    live("/collab", KotobaDev.CollabLive)
    live("/collab/many", KotobaDev.ManyCollabLive)
    live("/collab/nested", KotobaDev.NestedCollabLive)
    live("/collab/notebook", KotobaDev.NotebookLive)
    live("/collab/apart", KotobaDev.ApartLive)
  end
end

defmodule KotobaDev.ErrorHTML do
  def render(template, _assigns), do: Phoenix.Controller.status_message_from_template(template)
end

defmodule KotobaDev.Endpoint do
  use Phoenix.Endpoint, otp_app: :kotoba

  @session [store: :cookie, key: "_kotoba_dev", signing_salt: "kotoba-dev"]

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session]])
  socket("/issho/socket", KotobaDev.CollabSocket, websocket: [max_frame_size: 1_000_000])

  socket("/issho/small-socket", KotobaDev.SmallCollabSocket,
    websocket: [max_frame_size: 1_000_000]
  )

  if System.get_env("KOTOBA_DEV_WATCH") != "false" do
    socket("/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket)
    plug(Phoenix.LiveReloader)
    plug(Phoenix.CodeReloader)
  end

  # The node modules, then the editor bundle and its style sheets.
  plug(Plug.Static, at: "/assets/nodes", from: Path.expand("tmp/dev/nodes", __DIR__))
  plug(Plug.Static, at: "/vendor/issho", from: Path.expand("deps/issho/priv/static", __DIR__))
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
      [
        {Phoenix.PubSub, name: KotobaDev.PubSub},
        {Registry, keys: :unique, name: KotobaDev.WriterRegistry},
        {DynamicSupervisor, name: KotobaDev.Writers},
        {Kotoba.Collab.Store.Memory, name: KotobaDev.CollabStore},
        # Issho's own documents: a room's comments.
        {Issho.Store.Memory, name: KotobaDev.IsshoStore},
        {Issho,
         name: KotobaDev.Issho,
         pubsub: KotobaDev.PubSub,
         endpoint: KotobaDev.Endpoint,
         policy: KotobaDev.Collaboration,
         store: {Issho.Store.Memory, KotobaDev.IsshoStore}},
        KotobaDev.Endpoint
      ],
      strategy: :one_for_one
    )

  IO.puts("Kotoba development server: http://localhost:#{port}")
  Process.sleep(:infinity)
end)
