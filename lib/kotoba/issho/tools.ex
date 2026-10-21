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

    # The agent's selection in this document, as a range.
    def selection(%__MODULE__{} = doc) do
      case Participant.awareness(doc.participant) do
        %{"place" => %{"doc" => document, "at" => at}} when document == doc.document ->
          Text.from_place(doc.state, at)

        _ ->
          {:error, "Select the text first, or quote it."}
      end
    end

    # The range a call names: quoted text, or the agent's selection.
    def range(%__MODULE__{} = doc, args) do
      case args[:text] do
        nil -> selection(doc)
        quote -> Text.find(doc.state, quote, occurrence: args[:occurrence], block: args[:block])
      end
    end

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

    # Types text at a caret, a few characters at a time when `typing`, so
    # that the people see it written, the agent's caret moving with it.
    def type(%__MODULE__{} = doc, caret, text, marks, typing?) do
      chunks = if typing?, do: chunks(text), else: [text]
      type_chunks(doc, caret, chunks, marks, typing?)
    end

    defp type_chunks(doc, caret, [], _marks, _typing?), do: {:ok, doc, caret}

    defp type_chunks(doc, caret, [chunk | chunks], marks, typing?) do
      with {:ok, ops, _state, after_caret} <- Text.insert(doc.state, caret, chunk, marks),
           {:ok, doc} <- commit(doc, ops),
           caret = Text.caret_in(doc.state, after_caret),
           :ok <- point(doc, caret) do
        # A person's pace, so that the others see it written.
        if typing? and chunks != [], do: Process.sleep(35)
        type_chunks(doc, caret, chunks, marks, typing?)
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
      links. Quote this text to select or change it.
      """,
      annotations: [read_only: true, idempotent: true]

    arg :document, :string, required: true, description: "The document's id: \"notebook:7/intro\""

    alias Kotoba.Issho.{Text, Tools.Doc}

    @impl true
    def call(%{document: document}, ctx) do
      case Doc.open(ctx, document) do
        {:ok, doc} ->
          {:ok, %{"document" => document, "blocks" => Text.read(doc.state)}}

        error ->
          Doc.error(error)
      end
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
           :ok <- Doc.point(doc, range) do
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
           :ok <- Doc.point(doc, range),
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
    arg :occurrence, :integer, min: 1
    arg :block, :integer, min: 1

    alias Kotoba.Issho.{Text, Tools.Doc}

    @impl true
    def call(args, ctx) do
      with {:ok, doc} <- Doc.open(ctx, args.document),
           {:ok, range} <- Doc.range(doc, args),
           :ok <- Doc.point(doc, range),
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
           :ok <- Doc.point(doc, range),
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
    arg :occurrence, :integer, min: 1
    arg :block, :integer, min: 1

    alias Kotoba.Issho.{Text, Tools.Doc}

    @impl true
    def call(args, ctx) do
      with {:ok, doc} <- Doc.open(ctx, args.document),
           {:ok, range} <- Doc.range(doc, args),
           :ok <- Doc.point(doc, range),
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
      with {:ok, doc} <- Doc.open(ctx, args.document),
           {:ok, ops, _state, caret} <-
             Text.insert_block(doc.state, args.after, args.type, args.text),
           {:ok, doc} <- Doc.commit(doc, ops),
           :ok <- Doc.point(doc, Text.caret_in(doc.state, caret)) do
        {:ok, %{"added" => args.type}}
      else
        error -> Doc.error(error)
      end
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
    arg :occurrence, :integer, min: 1
    arg :block, :integer, min: 1

    alias Kotoba.Issho.{Text, Tools.Doc}

    @impl true
    def call(args, ctx) do
      with {:ok, doc} <- Doc.open(ctx, args.document),
           {:ok, range} <- Doc.range(doc, args),
           :ok <- Doc.point(doc, range) do
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
           {:ok, _doc, _caret} <- Doc.type_runs(doc, caret, runs) do
        {:ok, %{"pasted" => Enum.map_join(runs, &elem(&1, 0))}}
      else
        error -> Doc.error(error)
      end
    end
  end
end
