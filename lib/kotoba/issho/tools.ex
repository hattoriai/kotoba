if Code.ensure_loaded?(Issho.Tool) do
  defmodule Kotoba.Issho.Tools.Doc do
    @moduledoc false
    # A tool call on a shared Kotoba document, as the caller's agent: the
    # document open, its text, where the agent's selection is, and its
    # changes committed as its own, seen by everyone as they happen.

    alias Issho.Participant
    alias Issho.Tool.Context
    alias Kotoba.Issho.Text

    defstruct [:ctx, :participant, :room, :document, :state]

    def open(ctx, document) do
      room = Issho.Policy.room(document)

      with {:ok, participant, ^document, snapshot} <- Context.open(ctx, room, document) do
        {:ok,
         %__MODULE__{
           ctx: ctx,
           participant: participant,
           room: room,
           document: document,
           state: snapshot["state"]
         }}
      end
    end

    # The document as it is now.
    def refresh(%__MODULE__{} = doc) do
      case Participant.read(doc.participant, doc.document) do
        {:ok, %{"state" => state}} -> %{doc | state: state}
        _ -> doc
      end
    end

    def commit(%__MODULE__{} = doc, []), do: {:ok, doc}

    def commit(%__MODULE__{} = doc, ops) do
      case Participant.transact(doc.participant, doc.document, ops) do
        {:ok, _receipt} -> {:ok, refresh(doc)}
        {:error, reason} -> Context.error(reason)
      end
    end

    # Shows the others the agent's selection, or caret.
    def point(%__MODULE__{} = doc, range_or_caret) do
      place = %{"doc" => doc.document, "at" => Text.place(range_or_caret)}
      Participant.place(doc.participant, place)
    end

    # How an agent moves in a document (`config :kotoba, Kotoba.Issho`):
    # `pace`, the milliseconds it takes to type a character (0: text appears
    # at once), and `travel`, whether it goes to where it works and selects
    # as a person would (false: it is there at once). It moves with Issho's
    # motion (`Issho.Motion`): only where it goes is sent, each browser draws
    # the way there (its caret glides, a selection sweeps), and it moves
    # only for someone who sees it.
    def pace, do: Keyword.get(Application.get_env(:kotoba, Kotoba.Issho, []), :pace, 25)
    def travel?, do: Keyword.get(Application.get_env(:kotoba, Kotoba.Issho, []), :travel, true)

    @hold 300
    # The longest an agent types one text for: a longer one, in larger pieces.
    @typing 8_000

    # Goes to a caret, or to a range: pressed at its start, then dragged to
    # its end. Nothing to do where it is already (it selected the text before).
    def reach(%__MODULE__{} = doc, %{from: _} = range) do
      if there?(doc, range),
        do: :ok,
        else:
          Issho.Motion.drag(
            doc.participant,
            target(doc, %{block: range.block, index: range.from}),
            target(doc, range),
            travel: travel?()
          )
    end

    def reach(%__MODULE__{} = doc, caret) do
      if there?(doc, caret),
        do: :ok,
        else: Issho.Motion.go(doc.participant, target(doc, caret), travel: travel?())
    end

    defp target(doc, range_or_caret),
      do: %{"doc" => doc.document, "at" => Text.place(range_or_caret)}

    defp there?(doc, target) do
      case selection(doc) do
        {:ok, %{block: %{id: id}, from: from, to: to}} ->
          {id, from, to} ==
            {target.block.id, Map.get(target, :from, target[:index]),
             Map.get(target, :to, target[:index])}

        _ ->
          false
      end
    end

    # A moment on what is selected before it changes, so that the people see what will.
    def hold(%__MODULE__{} = doc),
      do: Issho.Motion.pause(doc.participant, %{"doc" => doc.document}, @hold, travel: travel?())

    # Whether someone sees the agent type, so that it types at a person's pace.
    defp seen?(doc),
      do:
        travel?() and Issho.Motion.travel?() and
          Issho.Motion.watched?(doc.participant, %{"doc" => doc.document})

    # The agent's selection in this document, as a range.
    def selection(%__MODULE__{} = doc) do
      case Participant.awareness(doc.participant) do
        %{"place" => %{"doc" => document, "at" => at}} when document == doc.document ->
          Text.from_place(doc.state, at)

        _ ->
          {:error, "Select the text first, or quote it."}
      end
    end

    # The range a call names: quoted text, a person's selection (`of`), or
    # the agent's own.
    def range(%__MODULE__{} = doc, args) do
      cond do
        args[:text] ->
          Text.find(doc.state, args.text, occurrence: args[:occurrence], block: args[:block])

        args[:of] ->
          selection_of(doc, args.of)

        true ->
          selection(doc)
      end
    end

    # What a person of the room has selected in this document.
    def selection_of(%__MODULE__{} = doc, who) do
      with {:ok, at, name} <- Issho.Tools.place_of(doc.participant, doc.document, who) do
        case Text.from_place(doc.state, at) do
          {:ok, %{from: same, to: same}} ->
            {:error, "#{name} has no text selected, only a caret."}

          {:ok, range} ->
            {:ok, range}

          {:error, _reason} ->
            {:error, "#{name}'s selection is not in one block of the text."}
        end
      end
    end

    # The text of a range.
    def text_of(%{block: block, from: from, to: to}),
      do: block.chars |> Enum.slice(from, to - from) |> Enum.map_join(& &1.text)

    # The caret a call names: after or before quoted text, the start or end
    # of a block or of the document, else the end of the agent's selection.
    def caret(%__MODULE__{} = doc, args) do
      cond do
        args[:after] ->
          with {:ok, r} <- find(doc, args[:after], args),
               do: {:ok, %{block: r.block, index: r.to}}

        args[:before] ->
          with {:ok, r} <- find(doc, args[:before], args),
               do: {:ok, %{block: r.block, index: r.from}}

        args[:at] == "start" ->
          Text.caret(doc.state, {:start, args[:block] || 1})

        args[:at] == "end" and args[:block] ->
          Text.caret(doc.state, {:end, args[:block]})

        args[:at] == "end" ->
          Text.caret(doc.state, :end)

        true ->
          with {:ok, r} <- selection(doc), do: {:ok, %{block: r.block, index: r.to}}
      end
    end

    defp find(doc, quote, args),
      do: Text.find(doc.state, quote, occurrence: args[:occurrence], block: args[:block])

    # Types text at a caret, a few characters at a time when `typing` (at
    # the `pace`), so that the people see it written, the agent's caret
    # moving with it.
    def type(%__MODULE__{} = doc, caret, text, marks, typing?) do
      per_char =
        if typing? and seen?(doc),
          do: min(pace(), div(@typing, max(String.length(text), 1))),
          else: 0

      chunks = if per_char > 0, do: chunks(text), else: [text]
      type_chunks(doc, caret, chunks, marks, per_char)
    end

    defp type_chunks(doc, caret, [], _marks, _per_char), do: {:ok, doc, caret}

    defp type_chunks(doc, caret, [chunk | chunks], marks, per_char) do
      with {:ok, ops, _state, after_caret} <- Text.insert(doc.state, caret, chunk, marks),
           {:ok, doc} <- commit(doc, ops),
           caret = Text.caret_in(doc.state, after_caret),
           :ok <- point(doc, caret) do
        if chunks != [], do: Process.sleep(per_char * String.length(chunk))
        type_chunks(doc, caret, chunks, marks, per_char)
      end
    end

    # Types runs of text, each with its own marks (what was copied), at once.
    def type_runs(doc, caret, []), do: {:ok, doc, caret}

    def type_runs(doc, caret, [{text, marks} | runs]) do
      with {:ok, doc, caret} <- type(doc, caret, text, marks, false),
           do: type_runs(doc, caret, runs)
    end

    # Pieces of a few characters, at word boundaries where there are some.
    defp chunks(text) do
      ~r/\S{1,6}\s*|\s+/u
      |> Regex.scan(text)
      |> List.flatten()
    end

    def remember(%__MODULE__{} = doc, name, value),
      do: Context.remember(doc.ctx, doc.room, name, value)

    def recall(%__MODULE__{} = doc, name), do: Context.recall(doc.ctx, doc.room, name)

    def error({:error, reason}), do: Context.error(reason)
  end

  defmodule Kotoba.Issho.Tools.Read do
    @moduledoc false
    use Issho.Tool,
      name: "read_text",
      description: """
      Reads a shared rich text document: its blocks (paragraphs, headings,
      list items, quotes, code), numbered from 1, each with its text and
      links. Quote this text to select or change it. With `of`, a person
      in the room, also what they have selected: act on it with the other
      tools' `of`.
      """,
      annotations: [read_only: true, idempotent: true]

    arg :document, :string, required: true, description: "The document's id: \"notebook:7/intro\""
    arg :of, :string, description: "A person in the room, by name: what they have selected"

    alias Kotoba.Issho.{Text, Tools.Doc}

    @impl true
    def call(%{document: document} = args, ctx) do
      with {:ok, doc} <- Doc.open(ctx, document),
           read = %{"document" => document, "blocks" => Text.read(doc.state)},
           {:ok, read} <- selected(read, doc, args[:of]) do
        {:ok, read}
      else
        error -> Doc.error(error)
      end
    end

    defp selected(read, _doc, nil), do: {:ok, read}

    defp selected(read, doc, who) do
      with {:ok, range} <- Doc.selection_of(doc, who),
           do:
             {:ok,
              Map.put(read, "selected", %{"block" => range.block.n, "text" => Doc.text_of(range)})}
    end
  end

  defmodule Kotoba.Issho.Tools.Select do
    @moduledoc false
    use Issho.Tool,
      name: "select_text",
      description: """
      Selects text, as a person does with the mouse: the others see your
      selection, in your colour, and the tools that change text change it
      when you do not quote text to them.
      """,
      annotations: [idempotent: true]

    arg :document, :string, required: true
    arg :text, :string, required: true, description: "The text, quoted exactly"
    arg :occurrence, :integer, min: 1, description: "Which occurrence (1, the first)"
    arg :block, :integer, min: 1, description: "Only in this block"

    alias Kotoba.Issho.Tools.Doc

    @impl true
    def call(args, ctx) do
      with {:ok, doc} <- Doc.open(ctx, args.document),
           {:ok, range} <- Doc.range(doc, args),
           :ok <- Doc.reach(doc, range) do
        {:ok, %{"selected" => args.text, "block" => range.block.n}}
      else
        error -> Doc.error(error)
      end
    end
  end

  defmodule Kotoba.Issho.Tools.Type do
    @moduledoc false
    use Issho.Tool,
      name: "type_text",
      description: """
      Types text into a shared document, as a person types: the others see
      it written, a few characters at a time. Where: `after` or `before`
      quoted text, `at` the "start" or "end" of a block (or of the
      document), else at the end of your selection. A newline starts a new
      block. The text takes the formatting of the text before it, and
      `marks` on top.
      """,
      annotations: []

    alias Kotoba.Issho.Text

    arg :document, :string, required: true
    arg :text, :string, required: true, max_length: 20_000
    arg :after, :string, description: "Type after this quoted text"
    arg :before, :string, description: "Type before this quoted text"
    arg :at, {:enum, ["start", "end"]}
    arg :block, :integer, min: 1, description: "The block of `at`, or where to look for the quote"
    arg :occurrence, :integer, min: 1

    arg :marks,
        {:object, Text.mark_args()},
        description: "Formatting for the typed text: bold, italic, underline..."

    arg :typing, :boolean, description: "Type it a few characters at a time (true), or at once"

    alias Kotoba.Issho.Tools.Doc

    @impl true
    def call(args, ctx) do
      typing? = Map.get(args, :typing) != false and String.length(args.text) <= 2_000
      marks = for {mark, value} <- args[:marks] || %{}, into: %{}, do: {to_string(mark), value}

      with {:ok, doc} <- Doc.open(ctx, args.document),
           {:ok, caret} <- Doc.caret(doc, args),
           :ok <- Doc.reach(doc, caret),
           {:ok, _doc, caret} <- Doc.type(doc, caret, args.text, marks, typing?) do
        {:ok, %{"typed" => String.length(args.text), "block" => caret.block.n}}
      else
        error -> Doc.error(error)
      end
    end
  end

  defmodule Kotoba.Issho.Tools.Replace do
    @moduledoc false
    use Issho.Tool,
      name: "replace_text",
      description: """
      Replaces text with other text: quoted text, or your selection. The new
      text takes the formatting of the text it replaces.
      """,
      annotations: [destructive: true]

    arg :document, :string, required: true
    arg :text, :string, description: "The text to replace, quoted; your selection unless given"
    arg :of, :string, description: "A person in the room, by name: the text they have selected"
    arg :with, :string, required: true
    arg :occurrence, :integer, min: 1
    arg :block, :integer, min: 1
    arg :typing, :boolean

    alias Kotoba.Issho.{Text, Tools.Doc}

    @impl true
    def call(args, ctx) do
      with {:ok, doc} <- Doc.open(ctx, args.document),
           {:ok, range} <- Doc.range(doc, args),
           marks = range |> Text.selected() |> List.first() |> marks_of(),
           :ok <- Doc.reach(doc, range),
           :ok <- Doc.hold(doc),
           {:ok, ops, _state} <- Text.delete(doc.state, range),
           {:ok, doc} <- Doc.commit(doc, ops),
           {:ok, caret} <- caret_at(doc, range) do
        typing? = Map.get(args, :typing) != false and String.length(args.with) <= 2_000

        with {:ok, _doc, _caret} <- Doc.type(doc, caret, args.with, marks, typing?),
             do: {:ok, %{"replaced" => true}}
      else
        error -> Doc.error(error)
      end
    end

    defp marks_of(%{attrs: attrs}) when is_map(attrs), do: Map.take(attrs, Text.marks())
    defp marks_of(_char), do: %{}

    # Where the replaced text was, in the document after the deletion.
    defp caret_at(doc, range) do
      place = Text.place(%{block: range.block, from: range.from, to: range.from})

      case Text.from_place(doc.state, place) do
        {:ok, range} -> {:ok, %{block: range.block, index: range.from}}
        error -> error
      end
    end
  end

  defmodule Kotoba.Issho.Tools.Delete do
    @moduledoc false
    use Issho.Tool,
      name: "delete_text",
      description: "Deletes text: quoted text, or your selection.",
      annotations: [destructive: true]

    arg :document, :string, required: true
    arg :text, :string, description: "The text to delete, quoted; your selection unless given"
    arg :of, :string, description: "A person in the room, by name: the text they have selected"
    arg :occurrence, :integer, min: 1
    arg :block, :integer, min: 1

    alias Kotoba.Issho.{Text, Tools.Doc}

    @impl true
    def call(args, ctx) do
      with {:ok, doc} <- Doc.open(ctx, args.document),
           {:ok, range} <- Doc.range(doc, args),
           :ok <- Doc.reach(doc, range),
           :ok <- Doc.hold(doc),
           {:ok, ops, _state} <- Text.delete(doc.state, range),
           {:ok, _doc} <- Doc.commit(doc, ops) do
        {:ok, %{"deleted" => range.to - range.from}}
      else
        error -> Doc.error(error)
      end
    end
  end

  defmodule Kotoba.Issho.Tools.Format do
    @moduledoc false
    use Issho.Tool,
      name: "format_text",
      description: """
      Formats text, as the toolbar does: bold, italic, underline,
      strikethrough, code, highlight, subscript, superscript (true to set,
      false to clear). Quoted text, or your selection.
      """,
      annotations: [idempotent: true]

    alias Kotoba.Issho.Text

    arg :document, :string, required: true
    arg :text, :string, description: "The text to format, quoted; your selection unless given"
    arg :of, :string, description: "A person in the room, by name: the text they have selected"
    arg :occurrence, :integer, min: 1
    arg :block, :integer, min: 1

    arg :marks,
        {:object, Text.mark_args()},
        required: true

    alias Kotoba.Issho.Tools.Doc

    @impl true
    def call(args, ctx) do
      marks =
        for {mark, value} <- args.marks,
            not is_nil(value),
            into: %{},
            do: {to_string(mark), value}

      with true <- marks != %{} || {:error, "Say which marks: bold, italic..."},
           {:ok, doc} <- Doc.open(ctx, args.document),
           {:ok, range} <- Doc.range(doc, args),
           :ok <- Doc.reach(doc, range),
           :ok <- Doc.hold(doc),
           {:ok, ops, _state} <- Text.format(doc.state, range, marks),
           {:ok, _doc} <- Doc.commit(doc, ops) do
        {:ok,
         %{"formatted" => Text.selected(range) |> Enum.map_join(& &1.text), "marks" => marks}}
      else
        error -> Doc.error(error)
      end
    end
  end

  defmodule Kotoba.Issho.Tools.Link do
    @moduledoc false
    use Issho.Tool,
      name: "link_text",
      description:
        "Makes text a link to a URL, as the link command does: quoted text, or your selection.",
      annotations: [idempotent: true]

    arg :document, :string, required: true
    arg :url, :string, required: true, max_length: 2_048
    arg :text, :string, description: "The text to link, quoted; your selection unless given"
    arg :of, :string, description: "A person in the room, by name: the text they have selected"
    arg :occurrence, :integer, min: 1
    arg :block, :integer, min: 1

    alias Kotoba.Issho.{Text, Tools.Doc}

    @impl true
    def call(args, ctx) do
      with {:ok, doc} <- Doc.open(ctx, args.document),
           {:ok, range} <- Doc.range(doc, args),
           :ok <- Doc.reach(doc, range),
           :ok <- Doc.hold(doc),
           {:ok, ops, _state} <- Text.link(doc.state, range, args.url),
           {:ok, _doc} <- Doc.commit(doc, ops) do
        {:ok, %{"linked" => Text.selected(range) |> Enum.map_join(& &1.text), "url" => args.url}}
      else
        error -> Doc.error(error)
      end
    end
  end

  defmodule Kotoba.Issho.Tools.AddBlock do
    @moduledoc false
    use Issho.Tool,
      name: "add_block",
      description: """
      Adds a block with text after block `after` (0 puts it first): a
      paragraph, a heading (h1 to h6) or a quote.
      """,
      annotations: []

    arg :document, :string, required: true
    arg :after, :integer, required: true, min: 0
    arg :type, {:enum, ~w(paragraph h1 h2 h3 h4 h5 h6 quote)}, required: true
    arg :text, :string, required: true, max_length: 20_000

    alias Kotoba.Issho.{Text, Tools.Doc}

    @impl true
    def call(args, ctx) do
      typing? = String.length(args.text) <= 2_000

      # To the end of the block it follows, a new block, and its text typed in it.
      with {:ok, doc} <- Doc.open(ctx, args.document),
           :ok <- go_after(doc, args.after),
           {:ok, ops, _state, caret} <- Text.insert_block(doc.state, args.after, args.type, ""),
           {:ok, doc} <- Doc.commit(doc, ops),
           caret = Text.caret_in(doc.state, caret),
           :ok <- Doc.point(doc, caret),
           {:ok, _doc, _caret} <- Doc.type(doc, caret, args.text, %{}, typing?) do
        {:ok, %{"added" => args.type}}
      else
        error -> Doc.error(error)
      end
    end

    defp go_after(_doc, 0), do: :ok

    defp go_after(doc, n) do
      with {:ok, caret} <- Text.caret(doc.state, {:end, n}), do: Doc.reach(doc, caret)
    end
  end

  defmodule Kotoba.Issho.Tools.Copy do
    @moduledoc false
    use Issho.Tool,
      name: "copy_text",
      description:
        "Copies text, with its formatting, for paste_text: quoted text, or your selection.",
      annotations: [read_only: true, idempotent: true]

    arg :document, :string, required: true
    arg :text, :string, description: "The text to copy, quoted; your selection unless given"
    arg :of, :string, description: "A person in the room, by name: the text they have selected"
    arg :occurrence, :integer, min: 1
    arg :block, :integer, min: 1

    alias Kotoba.Issho.{Text, Tools.Doc}

    @impl true
    def call(args, ctx) do
      with {:ok, doc} <- Doc.open(ctx, args.document),
           {:ok, range} <- Doc.range(doc, args),
           :ok <- Doc.reach(doc, range) do
        # Runs of the same formatting, to paste as they were.
        runs =
          range
          |> Text.selected()
          |> Enum.filter(& &1.atom)
          |> Enum.chunk_by(&Map.take(&1.attrs, Text.marks()))
          |> Enum.map(
            &{Enum.map_join(&1, fn char -> char.text end), Map.take(hd(&1).attrs, Text.marks())}
          )

        :ok = Doc.remember(doc, :clipboard, runs)
        {:ok, %{"copied" => Enum.map_join(runs, &elem(&1, 0))}}
      else
        error -> Doc.error(error)
      end
    end
  end

  defmodule Kotoba.Issho.Tools.Paste do
    @moduledoc false
    use Issho.Tool,
      name: "paste_text",
      description: """
      Pastes what you copied, with its formatting: `after` or `before`
      quoted text, `at` the "start" or "end" of a block or the document,
      else at the end of your selection. It may be in another document of
      the same room.
      """,
      annotations: []

    arg :document, :string, required: true
    arg :after, :string
    arg :before, :string
    arg :at, {:enum, ["start", "end"]}
    arg :block, :integer, min: 1
    arg :occurrence, :integer, min: 1

    alias Kotoba.Issho.Tools.Doc

    @impl true
    def call(args, ctx) do
      with {:ok, doc} <- Doc.open(ctx, args.document),
           runs when is_list(runs) <-
             Doc.recall(doc, :clipboard) || {:error, "Copy some text first."},
           {:ok, caret} <- Doc.caret(doc, args),
           :ok <- Doc.reach(doc, caret),
           {:ok, _doc, _caret} <- Doc.type_runs(doc, caret, runs) do
        {:ok, %{"pasted" => Enum.map_join(runs, &elem(&1, 0))}}
      else
        error -> Doc.error(error)
      end
    end
  end
end
