defmodule Kotoba.Collab.Document do
  @moduledoc """
  The versioned collaboration document and its semantic operations.

  Nodes and Unicode scalar values have persistent identities. Deleted
  values remain as anchors, so an offline insertion does not depend on a
  current array index. Phoenix orders accepted transactions.

  The wire format uses string keys. Transactions contain `v`, `schema`,
  `epoch`, `id`, `base_revision` and `ops`. A transaction is atomic: its
  resulting tree must pass the node, nesting, URL and feature checks.
  """

  import Bitwise

  alias Kotoba.{Content, Features, Nodes, Renderer, Sanitizer}

  @text_types ~w(text code-highlight tab)
  @marks Enum.with_index(
           ~w(bold italic strikethrough underline code subscript superscript highlight lowercase uppercase capitalize)
         )
  @reserved ~w(type version children text)
  @max_ops 1_000
  @id_pattern ~r/\A[A-Za-z0-9_:.-]{1,160}\z/
  @reserved_ids ~w(__proto__ constructor prototype toString toLocaleString valueOf hasOwnProperty isPrototypeOf propertyIsEnumerable __defineGetter__ __defineSetter__ __lookupGetter__ __lookupSetter__)

  @doc "Creates a collaboration state from server-owned content."
  def new(content \\ nil, opts \\ []) do
    case Content.to_doc(content) do
      {:ok, envelope} ->
        root = envelope["root"]

        root =
          if Map.get(root, "children", []) == [],
            do:
              Map.put(root, "children", [
                %{"type" => "paragraph", "version" => 1, "children" => []}
              ]),
            else: root

        state = %{
          "v" => 1,
          "schema" => 1,
          "epoch" => random_id(),
          "revision" => 0,
          "root" => "root",
          "nodes" => %{},
          "orders" => %{},
          "texts" => %{},
          "receipts" => %{},
          "transactions" => []
        }

        {state, _next} = import_node(state, root, "root", nil, 1)
        state = Map.put(state, "initial", snapshot(state))
        with {:ok, _content} <- validate(state, opts), do: {:ok, state}

      _ ->
        {:error, :invalid_content}
    end
  end

  @doc "The editing snapshot; receipts and the transaction journal stay on the server."
  def snapshot(state), do: Map.drop(state, ["receipts", "transactions", "initial"])

  @doc "Exports the editing state as the existing Kotoba document envelope."
  def to_envelope(state) do
    %{"kotoba" => 1, "lexical" => "0.51", "root" => export_node(state, state["root"])}
  end

  @doc "Checks and applies one transaction, returning its content and accepted event."
  def commit(state, transaction, author, opts \\ []) do
    with :ok <- check_transaction(state, transaction),
         digest = fingerprint(transaction, author),
         :new <- receipt(state, transaction["id"], digest),
         :ok <- check_operations(transaction["ops"]),
         {:ok, candidate} <- apply_ops(state, transaction["ops"]),
         {:ok, content} <- validate(candidate, opts) do
      revision = state["revision"] + 1
      event = Map.merge(transaction, %{"revision" => revision, "author" => author})
      receipt = %{"digest" => digest, "revision" => revision, "author" => author}

      candidate =
        candidate
        |> Map.put("revision", revision)
        |> put_in(["receipts", transaction["id"]], receipt)
        |> Map.update!("transactions", &(&1 ++ [event]))

      {:ok, candidate, content, event}
    else
      {:duplicate, revision} -> {:duplicate, revision}
      {:error, _reason} = error -> error
      _ -> {:error, :invalid_transaction}
    end
  rescue
    _error -> {:error, :invalid_transaction}
  end

  @doc "Applies operations without advancing a revision; used for transaction previews."
  def apply_ops(state, ops) when is_list(ops) do
    Enum.reduce_while(ops, {:ok, state}, fn op, {:ok, current} ->
      case apply_op(current, op) do
        {:ok, next} -> {:cont, {:ok, next}}
        error -> {:halt, error}
      end
    end)
  end

  def apply_ops(_state, _ops), do: {:error, :invalid_operations}

  @doc "Reads an immutable accepted revision, including its epoch."
  def at_revision(state, epoch, revision, opts \\ []) do
    if epoch == state["epoch"] and is_integer(revision) and revision >= 0 and
         revision <= state["revision"] do
      ops = state["transactions"] |> Enum.take(revision) |> Enum.flat_map(& &1["ops"])
      with {:ok, document} <- apply_ops(state["initial"], ops), do: validate(document, opts)
    else
      {:error, :unknown_revision}
    end
  end

  @doc "Validates and renders a snapshot on the server."
  def validate(state, opts \\ []) do
    envelope = to_envelope(state)

    with {:ok, parsed} <- Kotoba.Document.parse(envelope, nodes: Keyword.get(opts, :nodes, [])),
         :ok <- check_tree(parsed.root, nil, opts),
         :ok <- Features.check(parsed, Keyword.get(opts, :features, Features.all())) do
      content = %Content{
        doc: Kotoba.Document.to_json(parsed),
        html: parsed |> Renderer.to_html(opts) |> Phoenix.HTML.safe_to_string(),
        text: Renderer.to_text(parsed, opts)
      }

      validate_callback(content, Keyword.get(opts, :validate))
    else
      {:error, reason} -> {:error, {:invalid_content, reason}}
    end
  end

  @doc "Returns a cryptographically random identifier suitable for epochs and operations."
  def random_id, do: :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)

  defp validate_callback(content, nil), do: {:ok, content}

  defp validate_callback(content, callback) do
    case callback.(content) do
      :ok -> {:ok, content}
      {:error, reason} -> {:error, reason}
    end
  end

  defp check_operations(ops) do
    if Enum.all?(ops, &valid_operation?/1), do: :ok, else: {:error, :invalid_operation}
  end

  defp valid_operation?(op) when is_map(op) do
    valid_id?(op["id"]) and operation_fields?(op) and valid_atom_list?(op) and json_value?(op, 0)
  end

  defp valid_operation?(_op), do: false

  defp operation_fields?(op) do
    Enum.all?(~w(stamp tag expected_move parent after inherit), &optional_id?(op, &1)) and
      Enum.all?(
        ~w(data values attrs base_attrs expected expected_versions expected_moves),
        &optional_map?(op, &1)
      )
  end

  defp optional_id?(op, key),
    do: not Map.has_key?(op, key) or is_nil(op[key]) or valid_id?(op[key])

  defp optional_map?(op, key), do: not Map.has_key?(op, key) or is_map(op[key])

  defp valid_atom_list?(op),
    do: not Map.has_key?(op, "atoms") or (is_list(op["atoms"]) and length(op["atoms"]) <= 50_000)

  defp json_value?(_value, depth) when depth > 32, do: false

  defp json_value?(value, depth) when is_map(value),
    do:
      Enum.all?(value, fn {key, child} ->
        is_binary(key) and key not in ~w(__proto__ constructor prototype) and
          json_value?(child, depth + 1)
      end)

  defp json_value?(value, depth) when is_list(value),
    do: Enum.all?(value, &json_value?(&1, depth + 1))

  defp json_value?(value, _depth),
    do: is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value)

  defp check_transaction(state, tx) when is_map(tx) do
    cond do
      tx["v"] != 1 or tx["schema"] != state["schema"] ->
        {:error, :unsupported_version}

      tx["epoch"] != state["epoch"] ->
        {:error, :epoch_mismatch}

      not valid_id?(tx["id"]) ->
        {:error, :invalid_id}

      not valid_revision?(tx["base_revision"], state["revision"]) ->
        {:error, :invalid_revision}

      not valid_operations_count?(tx["ops"]) ->
        {:error, :invalid_operations}

      true ->
        :ok
    end
  end

  defp check_transaction(_state, _tx), do: {:error, :invalid_transaction}

  defp valid_revision?(revision, current),
    do: is_integer(revision) and revision >= 0 and revision <= current

  defp valid_operations_count?(ops), do: is_list(ops) and ops != [] and length(ops) <= @max_ops

  defp fingerprint(tx, author),
    do:
      :crypto.hash(
        :sha256,
        :erlang.term_to_binary({Map.take(tx, ~w(v schema epoch id base_revision ops)), author}, [
          :deterministic
        ])
      )
      |> Base.encode16(case: :lower)

  defp receipt(state, id, digest) do
    case state["receipts"][id] do
      nil -> :new
      %{"digest" => ^digest, "revision" => revision} -> {:duplicate, revision}
      _ -> {:error, :id_reused}
    end
  end

  defp apply_op(state, %{
         "op" => "insert_node",
         "id" => id,
         "parent" => parent,
         "after" => after_id,
         "data" => data
       }) do
    with true <- valid_id?(id) and not Map.has_key?(state["nodes"], id),
         :ok <- live_node(state, parent),
         :ok <- container(state, parent),
         :ok <- valid_data(data),
         {:ok, order} <- insert_after(Map.get(state["orders"], parent, []), after_id, id) do
      node = %{
        "data" => data,
        "parent" => parent,
        "element" => element?(data["type"]),
        "deleted" => false,
        "deletions" => [],
        "versions" => %{}
      }

      state =
        state
        |> put_in(["nodes", id], node)
        |> put_in(["orders", parent], order)
        |> put_in(["orders", id], [])

      state = if data["type"] == "text", do: put_in(state, ["texts", id], []), else: state
      {:ok, state}
    else
      false -> {:error, :invalid_id}
      error -> error
    end
  end

  defp apply_op(
         state,
         %{"op" => "move_node", "id" => id, "parent" => parent, "after" => after_id} = op
       ) do
    with :ok <- live_node(state, id),
         :ok <- live_node(state, parent),
         :ok <- container(state, parent),
         true <- id != state["root"] and id != after_id and not ancestor?(state, id, parent),
         {:ok, order} <- insert_after(Map.get(state["orders"], parent, []) -- [id], after_id, id) do
      if expected?(state["nodes"][id], op["expected"]) and
           (not Map.has_key?(op, "expected_move") or
              state["nodes"][id]["move_version"] == op["expected_move"]) do
        {:ok,
         state
         |> put_in(["nodes", id, "parent"], parent)
         |> put_in(["nodes", id, "move_version"], op["stamp"])
         |> put_in(["orders", parent], order)}
      else
        {:ok, state}
      end
    else
      false -> {:error, :invalid_move}
      error -> error
    end
  end

  defp apply_op(
         state,
         %{"op" => "node_visibility", "id" => id, "deleted" => deleted, "tag" => tag} = op
       )
       when is_boolean(deleted) and is_binary(tag) do
    cond do
      id == state["root"] -> {:error, :root_is_fixed}
      not Map.has_key?(state["nodes"], id) -> {:error, :unknown_node}
      deleted and op["if_empty"] == true and not empty_node?(state, id) -> {:ok, state}
      true -> {:ok, update_in(state, ["nodes", id], &visibility(&1, tag, deleted))}
    end
  end

  defp apply_op(state, %{"op" => "set_attrs", "id" => id, "values" => values} = op)
       when is_map(values) do
    with :ok <- live_node(state, id),
         true <- Enum.all?(Map.keys(values), &(is_binary(&1) and &1 not in @reserved)) do
      node = patch_record(state["nodes"][id], "data", values, op)
      {:ok, put_in(state, ["nodes", id], node)}
    else
      false -> {:error, :reserved_attribute}
      error -> error
    end
  end

  defp apply_op(
         state,
         %{"op" => "insert_text", "id" => id, "after" => after_id, "atoms" => atoms} = op
       )
       when is_list(atoms) do
    target = atom_location(state, after_id) || atom_location(state, op["inherit"]) || id
    atoms = Enum.map(atoms, &expand_atom(&1, op["attrs"]))

    with :ok <- live_node(state, target),
         true <- Map.has_key?(state["texts"], target),
         :ok <- check_atoms(state, atoms),
         {:ok, index} <- insertion_index(state, target, id, after_id, op["inherit"]) do
      inherited = find_atom(state, op["inherit"])

      atoms = Enum.map(atoms, &inserted_atom(&1, inherited, op["base_attrs"]))

      {before, rest} = Enum.split(state["texts"][target], index)
      {:ok, put_in(state, ["texts", target], before ++ atoms ++ rest)}
    else
      false -> {:error, :not_text}
      error -> error
    end
  end

  defp apply_op(
         state,
         %{"op" => "move_text", "id" => target, "after" => after_id, "atoms" => ids} = op
       )
       when is_list(ids) do
    with :ok <- live_node(state, target),
         true <- Map.has_key?(state["texts"], target),
         true <- ids != [] and length(ids) == MapSet.size(MapSet.new(ids)),
         true <- Enum.all?(ids, &(atom_location(state, &1) != nil)) do
      eligible =
        Enum.filter(ids, fn id ->
          not is_map(op["expected_moves"]) or not Map.has_key?(op["expected_moves"], id) or
            find_atom(state, id)["move_version"] == op["expected_moves"][id]
        end)

      moving =
        Enum.map(eligible, fn id ->
          find_atom(state, id) |> Map.delete("moved_to") |> Map.put("move_version", op["stamp"])
        end)

      texts =
        Map.new(state["texts"], fn {buffer, atoms} ->
          {buffer, move_source(atoms, buffer, target, eligible)}
        end)

      with {:ok, index} <- anchor_index(texts[target], after_id, & &1["id"]) do
        {before, rest} = Enum.split(texts[target], index)
        {:ok, Map.put(state, "texts", Map.put(texts, target, before ++ moving ++ rest))}
      end
    else
      false -> {:error, :unknown_atom}
      error -> error
    end
  end

  defp apply_op(state, %{
         "op" => "text_visibility",
         "id" => id,
         "atoms" => ids,
         "deleted" => deleted,
         "tag" => tag
       })
       when is_list(ids) and is_boolean(deleted) and is_binary(tag) do
    update_atoms(state, id, ids, &visibility(&1, tag, deleted))
  end

  defp apply_op(
         state,
         %{"op" => "set_text_attrs", "id" => id, "atoms" => ids, "values" => values} = op
       )
       when is_list(ids) and is_map(values) do
    if Enum.any?(
         Map.keys(values),
         &(&1 in ~w(children text format id deleted deletions versions moved_to move_version))
       ) or not valid_text_attrs?(values),
       do: {:error, :reserved_attribute},
       else: update_atoms(state, id, ids, &patch_record(&1, "attrs", values, op))
  end

  defp apply_op(_state, _op), do: {:error, :invalid_operation}

  defp expand_atom(atom, attrs) when is_map(atom), do: Map.put_new(atom, "attrs", attrs)
  defp expand_atom(atom, _attrs), do: atom

  defp inserted_atom(atom, inherited, base) do
    attrs =
      if inherited && is_map(base),
        do: inherit_attrs(inherited["attrs"], base, atom["attrs"]),
        else: atom["attrs"]

    atom
    |> Map.take(["id", "text"])
    |> Map.merge(%{"attrs" => attrs, "deleted" => false, "deletions" => [], "versions" => %{}})
  end

  defp move_source(atoms, buffer, target, eligible) when buffer == target,
    do: Enum.reject(atoms, &(&1["id"] in eligible))

  defp move_source(atoms, _buffer, target, eligible),
    do: Enum.map(atoms, &move_source_atom(&1, target, eligible))

  defp move_source_atom(atom, target, eligible) do
    if atom["id"] in eligible and is_nil(atom["moved_to"]),
      do: Map.put(atom, "moved_to", target),
      else: atom
  end

  defp atom_location(_state, nil), do: nil

  defp atom_location(state, id) do
    Enum.find_value(state["texts"], fn {buffer, atoms} ->
      if Enum.any?(atoms, &(&1["id"] == id and is_nil(&1["moved_to"]))), do: buffer
    end)
  end

  defp find_atom(state, id) do
    case atom_location(state, id) do
      nil -> nil
      buffer -> Enum.find(state["texts"][buffer], &(&1["id"] == id and is_nil(&1["moved_to"])))
    end
  end

  defp insertion_index(state, target, original, nil, inherited)
       when target != original and not is_nil(inherited) do
    with {:ok, index} <- anchor_index(state["texts"][target], inherited, & &1["id"]),
         do: {:ok, index - 1}
  end

  defp insertion_index(state, target, _original, after_id, _inherited),
    do: anchor_index(state["texts"][target], after_id, & &1["id"])

  defp update_atoms(state, id, ids, fun) do
    locations = Enum.map(ids, &atom_location(state, &1))

    with true <- ids != [] and Enum.all?(locations, &(not is_nil(&1))),
         :ok <- live_locations(state, locations) do
      targets = MapSet.new(ids)

      texts =
        Map.new(state["texts"], fn {buffer, atoms} ->
          {buffer, update_targets(atoms, targets, fun)}
        end)

      {:ok, Map.put(state, "texts", texts)}
    else
      false ->
        if(Map.has_key?(state["texts"], id),
          do: {:error, :unknown_atom},
          else: {:error, :not_text}
        )

      error ->
        error
    end
  end

  defp live_locations(state, locations) do
    Enum.reduce_while(Enum.uniq(locations), :ok, fn buffer, :ok ->
      case live_node(state, buffer) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp update_targets(atoms, targets, fun), do: Enum.map(atoms, &update_target(&1, targets, fun))

  defp update_target(atom, targets, fun) do
    if atom["id"] in targets and is_nil(atom["moved_to"]), do: fun.(atom), else: atom
  end

  defp conditional_patch(data, values, expected) do
    Enum.reduce(values, data, fn {key, value}, current ->
      if not is_map(expected) or not Map.has_key?(expected, key) or
           Map.get(current, key) == expected[key], do: Map.put(current, key, value), else: current
    end)
  end

  defp patch_record(record, field, values, op) do
    versions = Map.get(record, "versions", %{})

    values =
      Map.new(
        Enum.filter(values, fn {key, _value} ->
          not is_map(op["expected_versions"]) or not Map.has_key?(op["expected_versions"], key) or
            versions[key] == op["expected_versions"][key]
        end)
      )

    values =
      Map.new(
        Enum.filter(values, fn {key, _value} ->
          not is_map(op["expected"]) or not Map.has_key?(op["expected"], key) or
            record[field][key] == op["expected"][key]
        end)
      )

    data = conditional_patch(record[field], values, op["expected"])

    versions =
      Enum.reduce(values, versions, fn {key, _value}, acc -> Map.put(acc, key, op["stamp"]) end)

    record |> Map.put(field, data) |> Map.put("versions", versions)
  end

  defp visibility(record, tag, deleted) do
    deletions = Map.get(record, "deletions", [])
    deletions = if deleted, do: Enum.uniq([tag | deletions]), else: deletions -- [tag]
    record |> Map.put("deletions", deletions) |> Map.put("deleted", deletions != [])
  end

  defp expected?(_data, nil), do: true

  defp expected?(data, expected) when is_map(expected),
    do: Enum.all?(expected, fn {key, value} -> data[key] == value end)

  defp expected?(_data, _other), do: false

  defp inherit_attrs(current, base, desired),
    do:
      Map.merge(
        current,
        Map.new(Enum.reject(desired, fn {key, value} -> Map.get(base, key) == value end))
      )

  defp check_atoms(state, atoms) do
    ids = Enum.map(atoms, fn atom -> if is_map(atom), do: atom["id"] end)
    existing = state["texts"] |> Map.values() |> List.flatten() |> MapSet.new(& &1["id"])

    if atoms != [] and length(ids) == MapSet.size(MapSet.new(ids)) and
         Enum.all?(atoms, &valid_atom?(&1, existing)), do: :ok, else: {:error, :invalid_atoms}
  end

  defp valid_atom?(atom, existing) when is_map(atom) do
    valid_id?(atom["id"]) and atom["id"] not in existing and scalar?(atom["text"]) and
      valid_text_attrs?(atom["attrs"])
  end

  defp valid_atom?(_atom, _existing), do: false

  defp scalar?(text),
    do: is_binary(text) and String.valid?(text) and length(String.codepoints(text)) == 1

  defp valid_text_attrs?(attrs) when is_map(attrs) do
    (not Map.has_key?(attrs, "type") or attrs["type"] in @text_types) and
      Enum.all?(@marks, fn {mark, _} ->
        not Map.has_key?(attrs, mark) or is_boolean(attrs[mark])
      end)
  end

  defp valid_text_attrs?(_), do: false

  defp valid_data(data) when is_map(data) do
    if is_binary(data["type"]) and data["type"] not in ["root", "kotoba-upload", "kotoba-unknown"] and
         not Map.has_key?(data, "children") and not Map.has_key?(data, "text"),
       do: :ok,
       else: {:error, :invalid_node}
  end

  defp valid_data(_data), do: {:error, :invalid_node}

  defp valid_id?(id),
    do: is_binary(id) and id not in @reserved_ids and Regex.match?(@id_pattern, id)

  defp empty_node?(state, id) do
    cond do
      Map.has_key?(state["texts"], id) ->
        Enum.all?(state["texts"][id], &(&1["deleted"] or not is_nil(&1["moved_to"])))

      state["nodes"][id]["element"] ->
        Enum.all?(state["orders"][id], fn child ->
          state["nodes"][child]["parent"] != id or state["nodes"][child]["deleted"] or
            empty_node?(state, child)
        end)

      true ->
        false
    end
  end

  defp live_node(state, id) do
    case state["nodes"][id] do
      nil -> {:error, :unknown_node}
      %{"deleted" => true} -> {:error, :deleted_target}
      %{"parent" => nil} -> :ok
      %{"parent" => parent} -> live_node(state, parent)
    end
  end

  defp container(state, id) do
    type = state["nodes"][id]["data"]["type"]

    case Nodes.registry()[type] do
      nil -> {:error, :unknown_node_type}
      module -> if module.element?(), do: :ok, else: {:error, :not_container}
    end
  end

  defp ancestor?(_state, _id, nil), do: false
  defp ancestor?(_state, id, id), do: true
  defp ancestor?(state, id, other), do: ancestor?(state, id, state["nodes"][other]["parent"])

  defp insert_after(order, anchor, id) do
    with {:ok, index} <- anchor_index(order, anchor, & &1),
         do: {:ok, List.insert_at(order, index, id)}
  end

  defp anchor_index(_items, nil, _get_id), do: {:ok, 0}

  defp anchor_index(items, anchor, get_id) do
    case Enum.find_index(items, &(get_id.(&1) == anchor)) do
      nil -> {:error, :unknown_anchor}
      index -> {:ok, index + 1}
    end
  end

  defp import_node(state, json, id, parent, next) do
    data = Map.drop(json, ["children", "text"])

    node = %{
      "data" => data,
      "parent" => parent,
      "element" => element?(data["type"]),
      "deleted" => false,
      "deletions" => [],
      "versions" => %{}
    }

    state = state |> put_in(["nodes", id], node) |> put_in(["orders", id], [])
    children = Map.get(json, "children", [])

    children
    |> Enum.chunk_by(&(&1["type"] in @text_types))
    |> Enum.reduce({state, next}, &import_group(&1, &2, id))
  end

  defp import_group(group, {state, counter}, parent) do
    if hd(group)["type"] in @text_types do
      id = "seed:#{counter}"

      node = %{
        "data" => %{"type" => "text", "version" => 1},
        "parent" => parent,
        "element" => false,
        "deleted" => false,
        "deletions" => [],
        "versions" => %{}
      }

      {atoms, _} = Enum.reduce(group, {[], 0}, &import_text(&1, &2, id))

      state =
        state
        |> put_in(["nodes", id], node)
        |> put_in(["orders", id], [])
        |> put_in(["texts", id], atoms)
        |> update_in(["orders", parent], &(&1 ++ [id]))

      {state, counter + 1}
    else
      Enum.reduce(group, {state, counter}, &import_child(&1, &2, parent))
    end
  end

  defp import_text(text, {atoms, offset}, id) do
    parts = String.codepoints(text["text"] || "")
    attrs = text_attrs(text)

    added =
      parts
      |> Enum.with_index(offset)
      |> Enum.map(fn {char, index} ->
        %{
          "id" => "#{id}:#{index}",
          "text" => char,
          "attrs" => attrs,
          "deleted" => false,
          "deletions" => [],
          "versions" => %{}
        }
      end)

    {atoms ++ added, offset + length(parts)}
  end

  defp import_child(child, {state, counter}, parent) do
    id = "seed:#{counter}"
    {state, counter} = import_node(state, child, id, parent, counter + 1)
    {update_in(state, ["orders", parent], &(&1 ++ [id])), counter}
  end

  defp text_attrs(json) do
    attrs = Map.drop(json, ["text", "children", "format"])

    Enum.reduce(@marks, attrs, fn {name, index}, attrs ->
      Map.put(attrs, name, (Map.get(json, "format", 0) &&& 1 <<< index) != 0)
    end)
  end

  defp export_node(state, id) do
    node = state["nodes"][id]
    data = node["data"]
    children = state["orders"][id] || []

    children =
      Enum.filter(children, fn child ->
        state["nodes"][child]["parent"] == id and not state["nodes"][child]["deleted"]
      end)

    children =
      Enum.flat_map(children, fn child ->
        if Map.has_key?(state["texts"], child),
          do: export_text(state["texts"][child]),
          else: [export_node(state, child)]
      end)

    if node["element"], do: Map.put(data, "children", children), else: data
  end

  defp element?(type) do
    case Nodes.registry()[type] do
      nil -> false
      module -> module.element?()
    end
  end

  defp export_text(atoms) do
    atoms
    |> Enum.reject(&(&1["deleted"] or &1["moved_to"]))
    |> Enum.chunk_by(& &1["attrs"])
    |> Enum.map(&export_span/1)
  end

  defp export_span(group) do
    attrs = hd(group)["attrs"]
    format = Enum.reduce(@marks, 0, &export_mark(&1, &2, attrs))

    attrs
    |> Map.drop(Enum.map(@marks, &elem(&1, 0)))
    |> Map.put("format", format)
    |> Map.put("text", Enum.map_join(group, & &1["text"]))
  end

  defp export_mark({name, index}, value, attrs),
    do: if(attrs[name], do: value ||| 1 <<< index, else: value)

  defp check_tree(%Nodes.Unknown{}, _parent, _opts), do: {:error, :unknown_node_type}

  defp check_tree(node, parent, opts) do
    with :ok <- Sanitizer.check(node, parent, opts),
         :ok <- check_link(node, opts) do
      check_children(node, opts)
    end
  end

  defp check_children(node, opts) do
    Map.get(node, :children, [])
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, &check_child(&1, &2, node, opts))
  end

  defp check_child({child, index}, :ok, parent, opts) do
    case check_tree(child, parent, Keyword.put(opts, :index, index)) do
      :ok -> {:cont, :ok}
      error -> {:halt, error}
    end
  end

  defp check_link(%module{url: url}, opts) when module in [Nodes.Link, Nodes.AutoLink],
    do: if(Sanitizer.link_url(url, opts), do: :ok, else: {:error, :unsafe_url})

  defp check_link(_node, _opts), do: :ok
end
