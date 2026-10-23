if Code.ensure_loaded?(Storehouse) do
  defmodule Kotoba.Storage.Local.Plug do
    @moduledoc deprecated: "Use Storehouse.Local.Plug"
    @moduledoc """
    Deprecated: serves the files of `Kotoba.Storage.Local` with
    `Storehouse.Local.Plug`, under its `:url_prefix` and from its `:root`.
    It is removed in Kotoba 1.0: move to `Storehouse.Local` and its plug
    (see `Kotoba.Storage.Local`).

    It takes the options of `Storehouse.Local.Plug`.
    """

    @behaviour Plug

    alias Kotoba.Storage.Local
    alias Storehouse.Local.Plug, as: FilePlug

    @impl Plug
    def init(opts) do
      IO.warn(
        "Kotoba.Storage.Local.Plug is deprecated, and removed in Kotoba 1.0: " <>
          "use Storehouse.Local.Plug (see Kotoba.Storage.Local)",
        []
      )

      FilePlug.init(opts)
    end

    @impl Plug
    def call(conn, opts) do
      opts =
        opts
        |> Keyword.put_new_lazy(:at, &Local.url_prefix/0)
        |> Keyword.put_new_lazy(:root, &Local.root/0)

      FilePlug.call(conn, opts)
    end
  end
end
