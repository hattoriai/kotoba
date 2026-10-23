if Code.ensure_loaded?(Storehouse) do
  defmodule Kotoba.Storage do
    @moduledoc """
    The store of attachments, kept with [Storehouse](https://hexdocs.pm/storehouse).

    `Kotoba.Live.consume_uploads/4` and `Kotoba.Attachments.store/2` check
    each file and store it with `Storehouse.store/2`, through the store of
    `adapter/0`, and put the URL that it gives in the attachment node. Name
    the store in Storehouse's config:

        config :storehouse, adapter: Storehouse.S3

    The default is `Storehouse.Local`, the local disk, served by
    `Storehouse.Local.Plug`. Storehouse's [Stores](https://hexdocs.pm/storehouse/stores.html)
    guide has S3 (and R2, MinIO, LocalStack), and a store of your own.

    ## Keys

    A key is a relative path with segments of ASCII letters, digits, `.`, `-`
    and `_`, separated by `/`. `Storehouse.key/2` makes a new key in the form
    `yyyy/mm/<uuid>-<safe name><extension>`; the extension comes from the
    checked content type, never from the client's file name, so a key never
    ends in `.html` or `.svg`.

    ## The store of Kotoba 0.7 and before (deprecated)

    A store of the app's written for `Kotoba.Storage` (`put/3`, `url/1`,
    `delete/1`) is a `Storehouse.Adapter` as it is: the callbacks are the
    same, so it changes only its `@behaviour`. Until Kotoba 1.0,
    `config :kotoba, storage: MyApp.KotobaStorage` still names it, and
    `Kotoba.Storage.Local` (`config :kotoba, Kotoba.Storage.Local`) still
    works, each with a deprecation warning: move to
    `config :storehouse, adapter:` and `Storehouse.Local` (see the
    CHANGELOG).

    Storehouse is an optional dependency of Kotoba: an app with uploads has
    `{:storehouse, "~> 0.2"}` in its deps, and this module is there only
    with it.
    """

    require Logger

    @typedoc "A storage key, for example `\"2026/09/0b6…-cat.png\"`."
    @type key :: Storehouse.Adapter.key()

    @typedoc """
    What Kotoba knows about the file: `:name` (the client's file name, for
    display only, with control and format characters removed),
    `:content_type` (checked on the server, see `Kotoba.Attachments`) and
    `:bytes`.
    """
    @type meta :: %{
            optional(:name) => String.t(),
            optional(:content_type) => String.t(),
            optional(:bytes) => non_neg_integer()
          }

    @doc """
    Stores the file at `path` under `key`, and returns its URL.

    The file at `path` is a temporary file: the adapter copies it, and must
    not keep a reference to it.
    """
    @callback put(key(), path :: Path.t(), meta()) :: {:ok, url :: String.t()} | {:error, term()}

    @doc "Returns the URL of the file with `key`."
    @callback url(key()) :: String.t()

    @doc "Deletes the file with `key`. A key with no file gives `:ok`."
    @callback delete(key()) :: :ok | {:error, term()}

    @doc """
    Returns the store of attachments: `config :kotoba, storage:` when the
    app names one (deprecated), `Kotoba.Storage.Local` when the app
    configures it (deprecated), else Storehouse's (`Storehouse.adapter/0`).
    """
    @spec adapter() :: module()
    def adapter do
      cond do
        storage = Application.get_env(:kotoba, :storage) -> deprecated(storage)
        Application.get_env(:kotoba, Kotoba.Storage.Local) -> Kotoba.Storage.Local
        true -> Storehouse.adapter()
      end
    end

    # Once per node: the app names its store in Kotoba's config.
    defp deprecated(Kotoba.Storage.Local), do: Kotoba.Storage.Local

    defp deprecated(storage) do
      unless :persistent_term.get({__MODULE__, :warned}, false) do
        :persistent_term.put({__MODULE__, :warned}, true)

        Logger.warning("""
        config :kotoba, storage: #{inspect(storage)} is deprecated, and removed in \
        Kotoba 1.0: name the store in Storehouse's config, \
        config :storehouse, adapter: #{inspect(storage)}. See Kotoba's CHANGELOG.\
        """)
      end

      storage
    end

    @doc false
    @deprecated "Use Storehouse.key/2"
    defdelegate key(name, content_type), to: Storehouse

    @doc false
    @deprecated "Use Storehouse.safe_name/2"
    defdelegate safe_name(name, content_type), to: Storehouse

    @doc false
    @deprecated "Use Storehouse.valid_key?/1"
    defdelegate valid_key?(key), to: Storehouse
  end
end
