defmodule Kotoba.Issho.Text do
  @moduledoc false
  # A shared document as an agent works on it: blocks of text it reads and
  # quotes, and the operations a person's editor would send for the same
  # edit (Kotoba.Collab.Document's), so that an agent's change merges with
  # everyone's as theirs do.
  #
  # A block is a paragraph, a heading, a quote, a list item or a code block,
  # and its characters, each with the buffer and the atom (the character's
  # identity) it is in, its attributes and its link. A caret is a block and
  # the index of the character it is before; a range is a block and two
  # indexes. The operations are built against a working state, each applied
  # as it is made, as the browser's binding does.

  alias Kotoba.Collab.Document

  @blocks ~w(paragraph heading quote listitem code)
  @inline ~w(link autolink)
  @marks ~w(bold italic underline strikethrough code highlight subscript superscript)
  @text_attrs %{
    "type" => "text",
    "version" => 1,
    "detail" => 0,
    "mode" => "normal",
    "style" => "",
    "bold" => false,
    "italic" => false,
    "underline" => false,
    "strikethrough" => false,
    "code" => false,
    "highlight" => false,
    "subscript" => false,
    "superscript" => false,
    "lowercase" => false,
    "uppercase" => false,
    "capitalize" => false
  }

  @doc false
  def marks, do: @marks

  @doc false
  # The marks as the arguments of a tool: a boolean each.
  def mark_args, do: for(mark <- @marks, do: {String.to_atom(mark), :boolean, []})

  # Reading

  @doc false
  # The blocks of the document, in order, each with its characters.
  def blocks(state) do
    state
    |> walk(state["root"], [])
    |> Enum.reverse()
    |> Enum.with_index(1)
    |> Enum.map(fn {block, n} -> Map.put(block, :n, n) end)
  end

  @doc false
  # The blocks of the document, in order and numbered, without their
  # characters: what a block is and where.
  def outline(state) do
    state
    |> walk(state["root"], [], &outline_block/2)
    |> Enum.reverse()
    |> Enum.with_index(1)
    |> Enum.map(fn {block, n} -> Map.put(block, :n, n) end)
  end

  @doc false
  # The block that node `id` is in (or is), or nil.
  def block_of(_state, nil), do: nil

  def block_of(state, id) do
    case state["nodes"][id] do
      nil -> nil
      node -> if node["data"]["type"] in @blocks, do: id, else: block_of(state, node["parent"])
    end
  end

  @doc false
  # The text of block `id`, as `read/1` gives it.
  def block_text(state, id), do: state |> block(id) |> text()

  defp walk(state, id, acc, build \\ &block/2) do
    acc = if block?(state, id), do: [build.(state, id) | acc], else: acc

    state
    |> children(id)
    |> Enum.filter(&(element?(state, &1) and not inline?(state, &1)))
    |> Enum.reduce(acc, &walk(state, &1, &2, build))
  end

  defp block?(state, id), do: type(state, id) in @blocks

  defp block(state, id), do: Map.put(outline_block(state, id), :chars, chars(state, id, nil))

  defp outline_block(state, id) do
    data = state["nodes"][id]["data"]

    %{
      id: id,
      type: data["type"],
      tag: data["tag"],
      list: if(data["type"] == "listitem", do: list_type(state, id)),
      checked: data["checked"]
    }
  end

  defp list_type(state, id), do: state["nodes"][state["nodes"][id]["parent"]]["data"]["listType"]

  # The characters of a block, through its inline elements (links), and a
  # placeholder for what is not text (a line break, an image, a tag).
  defp chars(state, id, link),
    do: Enum.flat_map(children(state, id), &child_chars(state, &1, link))

  defp child_chars(state, child, link) do
    cond do
      Map.has_key?(state["texts"], child) ->
        for atom <- visible(state, child),
            do: %{
              buffer: child,
              atom: atom["id"],
              text: atom["text"],
              attrs: atom["attrs"],
              link: link
            }

      inline?(state, child) ->
        chars(state, child, %{id: child, url: state["nodes"][child]["data"]["url"]})

      element?(state, child) ->
        []

      true ->
        text = if type(state, child) == "linebreak", do: "\n", else: "\uFFFC"
        [%{buffer: nil, atom: nil, node: child, text: text, attrs: nil, link: link}]
    end
  end

  @doc false
  def text(%{chars: chars}), do: Enum.map_join(chars, & &1.text)

  @doc false
  # The document as an agent reads it: its blocks, numbered, with their links.
  def read(state) do
    for block <- blocks(state) do
      %{"n" => block.n, "type" => kind(block), "text" => text(block)}
      |> put_unless("links", links(block), [])
      |> put_unless("checked", block.checked, nil)
    end
  end

  defp links(block) do
    block.chars
    |> Enum.chunk_by(& &1.link)
    |> Enum.filter(&hd(&1).link)
    |> Enum.map(
      &%{"text" => Enum.map_join(&1, fn char -> char.text end), "url" => hd(&1).link.url}
    )
  end

  defp put_unless(map, _key, value, value), do: map
  defp put_unless(map, key, value, _none), do: Map.put(map, key, value)

  @doc false
  # What a block is, as an agent reads it: "paragraph", "h2", "bullet item".
  def kind(%{type: "heading", tag: tag}), do: tag
  def kind(%{type: "listitem", list: list}), do: "#{list || "bullet"} item"
  def kind(%{type: type}), do: type

  # Finding

  @doc false
  # The range of a quoted passage: its `occurrence` (1, the first) in the
  # document, or in block `n`.
  def find(state, quote, opts \\ []) when is_binary(quote) do
    occurrence = Keyword.get(opts, :occurrence) || 1
    needle = String.codepoints(quote)

    matches =
      for block <- blocks(state),
          is_nil(opts[:block]) or block.n == opts[:block],
          index <- positions(Enum.map(block.chars, & &1.text), needle),
          do: %{block: block, from: index, to: index + length(needle)}

    cond do
      quote == "" ->
        {:error, "Quote the text: it cannot be empty."}

      matches == [] ->
        {:error, "The text #{inspect(quote)} is not in the document."}

      occurrence > length(matches) ->
        {:error, "#{inspect(quote)} occurs #{length(matches)} time(s)."}

      true ->
        {:ok, Enum.at(matches, occurrence - 1)}
    end
  end

  defp positions(haystack, needle) do
    size = length(needle)

    haystack
    |> Enum.chunk_every(size, 1, :discard)
    |> Enum.with_index()
    |> Enum.filter(fn {window, _index} -> window == needle end)
    |> Enum.map(&elem(&1, 1))
  end

  @doc false
  # A caret at the start or the end of block `n`, or of the document.
  def caret(state, where) do
    blocks = blocks(state)

    case where do
      {:start, n} ->
        with {:ok, block} <- nth(blocks, n), do: {:ok, %{block: block, index: 0}}

      {:end, n} ->
        with {:ok, block} <- nth(blocks, n),
             do: {:ok, %{block: block, index: length(block.chars)}}

      :end ->
        with {:ok, block} <- nth(blocks, length(blocks)),
             do: {:ok, %{block: block, index: length(block.chars)}}
    end
  end

  defp nth(blocks, n) do
    case Enum.find(blocks, &(&1.n == n)) do
      nil -> {:error, "The document has no block #{n}: it has #{length(blocks)}."}
      block -> {:ok, block}
    end
  end

  @doc false
  def selected(%{block: block, from: from, to: to}), do: Enum.slice(block.chars, from, to - from)

  # Places: what editors draw as someone's selection

  @doc false
  # A range as a selection in the editors' terms: points at a buffer, after an atom.
  def place(%{block: block, from: from, to: to}) do
    %{"anchor" => point(block, from), "focus" => point(block, to)}
  end

  def place(%{block: block, index: index}), do: place(%{block: block, from: index, to: index})

  defp point(%{chars: chars, id: id}, index) do
    case {Enum.at(chars, index - 1), Enum.at(chars, index)} do
      {%{atom: atom, buffer: buffer}, _} when index > 0 and not is_nil(atom) ->
        %{"node" => buffer, "before" => atom}

      {_, %{buffer: buffer}} when not is_nil(buffer) ->
        %{"node" => buffer, "before" => nil}

      _ ->
        %{"node" => id, "before" => nil, "offset" => 0}
    end
  end

  @doc false
  # A selection the agent made before (its place), as a range, if its text is still there.
  def from_place(state, %{"anchor" => anchor, "focus" => focus}) do
    blocks = blocks(state)

    with {:ok, block, from} <- locate(blocks, anchor),
         {:ok, ^block, to} <- locate(blocks, focus) do
      {:ok, %{block: block, from: min(from, to), to: max(from, to)}}
    else
      _ -> {:error, "Select the text first: your selection is gone."}
    end
  end

  def from_place(_state, _place), do: {:error, "Select the text first."}

  defp locate(blocks, %{"node" => node, "before" => before}),
    do: Enum.find_value(blocks, {:error, :gone}, &locate_in(&1, node, before))

  defp locate_in(block, node, nil) do
    if block.id == node do
      {:ok, block, 0}
    else
      index = Enum.find_index(block.chars, &(&1.buffer == node))
      if index, do: {:ok, block, index}
    end
  end

  defp locate_in(block, _node, before) do
    index = Enum.find_index(block.chars, &(&1.atom == before))
    if index, do: {:ok, block, index + 1}
  end

  # Operations

  @doc false
  # Types text at a caret, with the formatting of the text before it (and
  # `marks`); a newline starts a new block. Gives the operations, the state
  # after them, and the caret after the text.
  def insert(state, %{block: block, index: index}, text, marks \\ %{}) do
    [first | lines] = String.split(text, "\n")
    acc = %{state: state, ops: []}

    with {:ok, acc, caret} <- insert_line(acc, block.id, index, first, marks) do
      # The lines after the first go on with the formatting of the text typed, as in an editor.
      acc |> insert_lines(caret, lines, marks, typed_attrs(acc.state, caret)) |> finish()
    end
  end

  defp insert_lines(acc, caret, [], _marks, _typed), do: {:ok, acc, caret}

  defp insert_lines(acc, caret, [line | lines], marks, typed) do
    with {:ok, acc, new_block} <- split(acc, caret),
         {:ok, acc, caret} <- insert_line(acc, new_block, 0, line, marks, typed),
         do: insert_lines(acc, caret, lines, marks, typed)
  end

  defp finish({:ok, acc, caret}), do: {:ok, Enum.reverse(acc.ops), acc.state, caret}
  defp finish(error), do: error

  defp typed_attrs(state, {block_id, index}) do
    if index > 0, do: attrs_from(Enum.at(block(state, block_id).chars, index - 1))
  end

  # One line of text into a block, at a character index; gives the caret after it.
  defp insert_line(acc, block_id, index, line, marks, base \\ nil)
  defp insert_line(acc, block_id, index, "", _marks, _base), do: {:ok, acc, {block_id, index}}

  defp insert_line(acc, block_id, index, line, marks, base) do
    block = block(acc.state, block_id)
    before = if index > 0, do: Enum.at(block.chars, index - 1)
    next = Enum.at(block.chars, index)
    base = base || attrs_from(if(index > 0, do: before, else: next))

    with {:ok, acc, buffer, after_atom} <- slot(acc, block, index, before, next) do
      atoms =
        for character <- String.codepoints(line),
            do: %{"id" => id(), "text" => character, "attrs" => Map.merge(base, marks)}

      anchor = after_atom || first_atom(acc.state, buffer)

      op =
        %{
          "op" => "insert_text",
          "id" => buffer,
          "after" => after_atom && after_atom["id"],
          "atoms" => atoms
        }
        |> then(
          &if(anchor,
            do: Map.merge(&1, %{"inherit" => anchor["id"], "base_attrs" => anchor["attrs"]}),
            else: &1
          )
        )

      with {:ok, acc} <- emit(acc, op), do: {:ok, acc, {block_id, index + length(atoms)}}
    end
  end

  defp attrs_from(%{attrs: attrs}) when is_map(attrs), do: Map.merge(@text_attrs, attrs)
  defp attrs_from(_char), do: @text_attrs

  defp first_atom(state, buffer), do: List.first(visible(state, buffer))

  # Where text goes at an index: the buffer of the character before it, unless
  # that one is in a link the next is not in (text after a link goes after it).
  defp slot(acc, block, _index, before, next) do
    cond do
      goes_after?(before, next) ->
        {:ok, acc, before.buffer, find_atom(acc.state, before.atom)}

      goes_before?(next) ->
        {:ok, acc, next.buffer, previous_atom(acc.state, next.buffer, next.atom)}

      true ->
        # A buffer of its own, after the element before (a link) or first.
        new_buffer(acc, block.id, holder(before))
    end
  end

  defp goes_after?(nil, _next), do: false
  defp goes_after?(%{buffer: nil}, _next), do: false
  defp goes_after?(%{link: nil}, _next), do: true
  defp goes_after?(%{link: link}, next), do: next != nil and next.link == link

  defp goes_before?(next), do: next != nil and next.buffer != nil and next.link == nil

  # The node a character is in, among its block's children: its link, its buffer, or itself.
  defp holder(nil), do: nil
  defp holder(char), do: (char.link && char.link.id) || char.buffer || char[:node]

  defp new_buffer(acc, parent, after_node) do
    buffer = id()

    op = %{
      "op" => "insert_node",
      "id" => buffer,
      "parent" => parent,
      "after" => after_node,
      "data" => %{"type" => "text", "version" => 1},
      "element" => false
    }

    with {:ok, acc} <- emit(acc, op), do: {:ok, acc, buffer, nil}
  end

  defp find_atom(state, id),
    do:
      Enum.find_value(state["texts"], fn {_buffer, atoms} ->
        Enum.find(atoms, &(&1["id"] == id and is_nil(&1["moved_to"])))
      end)

  defp previous_atom(state, buffer, atom_id) do
    atoms = state["texts"][buffer]
    index = Enum.find_index(atoms, &(&1["id"] == atom_id))
    if index && index > 0, do: Enum.at(atoms, index - 1)
  end

  # Splits a block at a caret, as Enter does: a block of the same kind after
  # it takes what follows the caret. Gives the new block.
  defp split(acc, {block_id, index}) do
    data = Map.drop(acc.state["nodes"][block_id]["data"], ["checked"])
    new_block = id()
    parent = acc.state["nodes"][block_id]["parent"]

    op = %{
      "op" => "insert_node",
      "id" => new_block,
      "parent" => parent,
      "after" => block_id,
      "data" => data,
      "element" => true
    }

    with {:ok, acc} <- emit(acc, op),
         {:ok, acc} <- move_rest(acc, block_id, index, new_block) do
      {:ok, acc, new_block}
    end
  end

  # What follows a character index of a block goes to another block: the rest
  # of the buffer the index is in, then the children after it.
  defp move_rest(acc, block_id, index, target) do
    case Enum.drop(block(acc.state, block_id).chars, index) do
      [] ->
        {:ok, acc}

      [first | _] = rest ->
        children = children(acc.state, block_id)
        holder = holder(first)
        follow = Enum.drop(children, Enum.find_index(children, &(&1 == holder)) + 1)
        {acc, after_node} = move_head(acc, first, rest, holder, target)

        ops =
          Enum.zip_with(follow, [after_node | follow], fn child, after_child ->
            %{
              "op" => "move_node",
              "id" => child,
              "parent" => target,
              "after" => after_child,
              "stamp" => id()
            }
          end)

        emits(acc, ops)
    end
  end

  # The first holder of what follows: a buffer whose rest moves into a new
  # buffer of the target, or a whole node (a link) that moves.
  defp move_head(acc, %{buffer: buffer, link: nil}, rest, _holder, target)
       when not is_nil(buffer) do
    moving = rest |> Enum.take_while(&(&1.buffer == buffer)) |> Enum.map(& &1.atom)

    if moving == visible(acc.state, buffer) |> Enum.map(& &1["id"]) do
      {:ok, acc} =
        emit(acc, %{
          "op" => "move_node",
          "id" => buffer,
          "parent" => target,
          "after" => nil,
          "stamp" => id()
        })

      {acc, buffer}
    else
      {:ok, acc, new, nil} = new_buffer(acc, target, nil)

      {:ok, acc} =
        emit(acc, %{
          "op" => "move_text",
          "id" => new,
          "after" => nil,
          "atoms" => moving,
          "stamp" => id()
        })

      {acc, new}
    end
  end

  defp move_head(acc, _first, _rest, holder, target) do
    {:ok, acc} =
      emit(acc, %{
        "op" => "move_node",
        "id" => holder,
        "parent" => target,
        "after" => nil,
        "stamp" => id()
      })

    {acc, holder}
  end

  @doc false
  # Deletes the characters of a range.
  def delete(state, range) do
    tag = id()

    ops =
      for chars <- runs(range),
          do: %{
            "op" => "text_visibility",
            "id" => hd(chars).buffer,
            "atoms" => Enum.map(chars, & &1.atom),
            "deleted" => true,
            "tag" => tag
          }

    with {:ok, acc} <- emits(%{state: state, ops: []}, ops),
         do: {:ok, Enum.reverse(acc.ops), acc.state}
  end

  @doc false
  # Sets marks (bold, italic...) on the characters of a range.
  def format(state, range, marks) do
    stamp = id()

    ops =
      for chars <- runs(range),
          do: %{
            "op" => "set_text_attrs",
            "id" => hd(chars).buffer,
            "atoms" => Enum.map(chars, & &1.atom),
            "values" => marks,
            "stamp" => stamp
          }

    with {:ok, acc} <- emits(%{state: state, ops: []}, ops),
         do: {:ok, Enum.reverse(acc.ops), acc.state}
  end

  # The characters of a range, by the buffer they are in.
  defp runs(range),
    do: range |> selected() |> Enum.filter(& &1.atom) |> Enum.chunk_by(& &1.buffer)

  @doc false
  # Makes the characters of a range a link, as the editor's link command
  # does: a link element after the text before them, with a buffer of its
  # own that they move into, and the text after them in another buffer.
  def link(state, range, url) do
    chars = selected(range)
    buffers = chars |> Enum.map(& &1.buffer) |> Enum.uniq()

    cond do
      chars == [] ->
        {:error, "Select some text to make a link."}

      Enum.any?(chars, & &1.link) ->
        {:error, "Part of that text is a link already."}

      length(buffers) != 1 or hd(buffers) == nil ->
        {:error, "A link takes text of one run, with no image or line break in it."}

      true ->
        wrap(state, hd(buffers), Enum.map(chars, & &1.atom), url)
    end
  end

  defp wrap(state, buffer, atoms, url) do
    parent = state["nodes"][buffer]["parent"]
    visible = state |> visible(buffer) |> Enum.map(& &1["id"])
    last = List.last(atoms)
    after_link = visible |> Enum.drop_while(&(&1 != last)) |> Enum.drop(1)
    {link, inner} = {id(), id()}

    link_data = %{
      "type" => "link",
      "version" => 1,
      "url" => url,
      "rel" => nil,
      "target" => nil,
      "title" => nil,
      "direction" => nil,
      "format" => "",
      "indent" => 0
    }

    ops =
      [
        %{
          "op" => "insert_node",
          "id" => link,
          "parent" => parent,
          "after" => buffer,
          "data" => link_data,
          "element" => true
        },
        %{
          "op" => "insert_node",
          "id" => inner,
          "parent" => link,
          "after" => nil,
          "data" => %{"type" => "text", "version" => 1},
          "element" => false
        },
        %{"op" => "move_text", "id" => inner, "after" => nil, "atoms" => atoms, "stamp" => id()}
      ] ++ rest_after(after_link, parent, link)

    with {:ok, next} <- Document.apply_ops(state, ops), do: {:ok, ops, next}
  end

  defp rest_after([], _parent, _link), do: []

  defp rest_after(atoms, parent, link) do
    rest = id()

    [
      %{
        "op" => "insert_node",
        "id" => rest,
        "parent" => parent,
        "after" => link,
        "data" => %{"type" => "text", "version" => 1},
        "element" => false
      },
      %{"op" => "move_text", "id" => rest, "after" => nil, "atoms" => atoms, "stamp" => id()}
    ]
  end

  @doc false
  # A new block of `type` ("paragraph", "h1" to "h6", "quote") after block
  # `n` (0: first), with text.
  def insert_block(state, after_n, type, text) do
    blocks = blocks(state)

    with {:ok, parent, after_node} <- block_slot(state, blocks, after_n),
         {:ok, data} <- block_data(type) do
      block = id()

      op = %{
        "op" => "insert_node",
        "id" => block,
        "parent" => parent,
        "after" => after_node,
        "data" => data,
        "element" => true
      }

      with {:ok, acc} <- emit(%{state: state, ops: []}, op),
           {:ok, ops, next, caret} <-
             insert(acc.state, %{block: block(acc.state, block), index: 0}, text) do
        {:ok, Enum.reverse(acc.ops) ++ ops, next, caret}
      end
    end
  end

  defp block_slot(state, _blocks, 0), do: {:ok, state["root"], nil}

  defp block_slot(state, blocks, n) do
    case Enum.find(blocks, &(&1.n == n)) do
      nil -> {:error, "The document has no block #{n}: it has #{length(blocks)}."}
      block -> {:ok, state["nodes"][block.id]["parent"], block.id}
    end
  end

  @doc false
  # Moves the top-level block that holds block `n` (a list with all its
  # items, a table, a quote) after the top-level block that holds block
  # `after_n` (0: first), as a block handle does. One `move_node`, so that
  # the people's carets in it go with it.
  def move_block(state, n, after_n) do
    blocks = blocks(state)
    root = state["root"]

    with {:ok, moving} <- top_of(state, blocks, n),
         {:ok, target} <- if(after_n == 0, do: {:ok, nil}, else: top_of(state, blocks, after_n)),
         :ok <- movable(state, root, moving, target, n, after_n) do
      emits(%{state: state, ops: []}, [
        %{
          "op" => "move_node",
          "id" => moving,
          "parent" => root,
          "after" => target,
          "stamp" => id()
        }
      ])
      |> case do
        {:ok, acc} -> {:ok, Enum.reverse(acc.ops), acc.state, moving}
        error -> error
      end
    end
  end

  # The top-level node of block `n`.
  defp top_of(state, blocks, n) do
    case Enum.find(blocks, &(&1.n == n)) do
      nil -> {:error, "The document has no block #{n}: it has #{length(blocks)}."}
      block -> {:ok, top(state, block.id)}
    end
  end

  @doc false
  # Whether node `id` is `top` or in it.
  def within?(_state, top, top), do: true
  def within?(_state, nil, _top), do: false
  def within?(state, id, top), do: within?(state, state["nodes"][id]["parent"], top)

  defp top(state, id) do
    parent = state["nodes"][id]["parent"]
    if parent == state["root"], do: id, else: top(state, parent)
  end

  defp movable(_state, _root, same, same, n, after_n),
    do: {:error, "Blocks #{n} and #{after_n} are in the same block: it cannot go after itself."}

  defp movable(state, root, moving, target, n, _after_n) do
    tops = children(state, root)
    index = Enum.find_index(tops, &(&1 == moving))
    previous = if index > 0, do: Enum.at(tops, index - 1)

    if previous == target, do: {:error, "Block #{n} is already there."}, else: :ok
  end

  @element %{"direction" => nil, "format" => "", "indent" => 0, "version" => 1}

  defp block_data("paragraph"),
    do: {:ok, Map.merge(@element, %{"type" => "paragraph", "textFormat" => 0, "textStyle" => ""})}

  defp block_data("h" <> level = tag) when level in ~w(1 2 3 4 5 6),
    do: {:ok, Map.merge(@element, %{"type" => "heading", "tag" => tag})}

  defp block_data("quote"), do: {:ok, Map.put(@element, "type", "quote")}

  defp block_data(type),
    do:
      {:error,
       "A new block is a paragraph, a heading (h1 to h6) or a quote, not #{inspect(type)}."}

  # Building against a working state

  defp emits(acc, ops), do: Enum.reduce_while(ops, {:ok, acc}, &emit_step/2)

  defp emit_step(op, {:ok, acc}) do
    case emit(acc, op) do
      {:ok, acc} -> {:cont, {:ok, acc}}
      error -> {:halt, error}
    end
  end

  defp emit(acc, op) do
    case Document.apply_ops(acc.state, [op]) do
      {:ok, state} -> {:ok, %{acc | state: state, ops: [op | acc.ops]}}
      {:error, reason} -> {:error, "The document refused the change (#{inspect(reason)})."}
    end
  end

  @doc false
  # A caret as `insert` gives it ({block id, index}), in a state.
  def caret_in(state, {block_id, index}),
    do: %{block: Enum.find(blocks(state), &(&1.id == block_id)), index: index}

  defp id, do: "ai:" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

  defp children(state, id) do
    nodes = state["nodes"]

    Enum.filter(
      state["orders"][id] || [],
      &(nodes[&1]["parent"] == id and not nodes[&1]["deleted"])
    )
  end

  defp visible(state, buffer),
    do: Enum.filter(state["texts"][buffer] || [], &(not &1["deleted"] and is_nil(&1["moved_to"])))

  defp type(state, id), do: state["nodes"][id]["data"]["type"]
  defp element?(state, id), do: state["nodes"][id]["element"] == true
  defp inline?(state, id), do: type(state, id) in @inline
end
