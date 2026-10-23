if Code.ensure_loaded?(Storehouse) do
  defmodule Kotoba.Storage.Local do
    @moduledoc deprecated: "Use Storehouse.Local"
    @moduledoc """
    Deprecated: the local store of Kotoba 0.7, kept so that an app
    configured for it goes on working. It is removed in Kotoba 1.0.

    Move to `Storehouse.Local`, which keeps the files the same way:

        # config/config.exs: remove `config :kotoba, storage: Kotoba.Storage.Local`

        # config/runtime.exs, dev.exs and test.exs: the same options
        config :storehouse, Storehouse.Local,
          root: System.get_env("KOTOBA_UPLOADS", "/var/lib/my_app/uploads"),
          url_prefix: "/uploads/kotoba"

        # the endpoint: plug Storehouse.Local.Plug, in place of Kotoba.Storage.Local.Plug

    Keep `url_prefix: "/uploads/kotoba"` (this store's default) and the same
    `root`, and the URLs in the documents you have stay valid.

    Until then, `config :kotoba, Kotoba.Storage.Local` takes `:root` (the
    directory, required) and `:url_prefix` (by default `"/uploads/kotoba"`).
    """

    @behaviour Storehouse.Adapter

    require Logger

    @default_prefix "/uploads/kotoba"

    @impl Storehouse.Adapter
    def put(key, path, _meta) do
      warn()

      with {:ok, destination} <- path(key),
           :ok <- File.mkdir_p(Path.dirname(destination)),
           :ok <- File.cp(path, destination) do
        {:ok, url(key)}
      end
    end

    @impl Storehouse.Adapter
    def url(key) when is_binary(key), do: String.trim_trailing(url_prefix(), "/") <> "/" <> key

    @impl Storehouse.Adapter
    def delete(key) do
      with {:ok, path} <- path(key) do
        case File.rm(path) do
          :ok -> :ok
          {:error, :enoent} -> :ok
          {:error, reason} -> {:error, reason}
        end
      end
    end

    @doc false
    def path(key) do
      root = root()

      with true <- Storehouse.valid_key?(key),
           path = Path.expand(key, root),
           true <- String.starts_with?(path, root <> "/") do
        {:ok, path}
      else
        false -> {:error, :invalid_key}
      end
    end

    @doc false
    def root do
      case Keyword.get(config(), :root) do
        root when is_binary(root) and root != "" ->
          Path.expand(root)

        _missing ->
          raise ArgumentError, """
          Kotoba.Storage.Local needs a root directory. It is deprecated: move to
          Storehouse.Local, with the same root:

              config :storehouse, Storehouse.Local, root: "tmp/uploads", url_prefix: "/uploads/kotoba"
          """
      end
    end

    @doc false
    def url_prefix, do: Keyword.get(config(), :url_prefix, @default_prefix)

    @doc false
    # Once per node: the app still uses the store of Kotoba 0.7.
    def warn do
      unless :persistent_term.get({__MODULE__, :warned}, false) do
        :persistent_term.put({__MODULE__, :warned}, true)

        Logger.warning("""
        Kotoba.Storage.Local is deprecated, and removed in Kotoba 1.0. Keep the \
        files with Storehouse.Local: config :storehouse, Storehouse.Local, with the \
        same root and url_prefix: "/uploads/kotoba", and remove config :kotoba, \
        storage: Kotoba.Storage.Local. See Kotoba's CHANGELOG.\
        """)
      end

      :ok
    end

    defp config, do: Application.get_env(:kotoba, __MODULE__, [])
  end
end
