defmodule Kotoba.Storage.Local do
  @moduledoc """
  A `Kotoba.Storage` adapter that keeps files in a directory on the local
  disk.

      # config/config.exs
      config :kotoba, storage: Kotoba.Storage.Local

      # config/runtime.exs, in the :prod block
      if config_env() == :prod do
        config :kotoba, Kotoba.Storage.Local,
          root: System.get_env("KOTOBA_UPLOADS", "/var/lib/my_app/uploads"),
          url_prefix: "/uploads/kotoba"
      end

      # config/dev.exs
      config :kotoba, Kotoba.Storage.Local, root: Path.expand("../tmp/uploads", __DIR__)

    * `:root` - the directory for the files (required). In production,
      give an absolute path outside the release, from the `:prod` block of
      `config/runtime.exs` (`runtime.exs` runs in every environment, so
      outside that block it replaces the development root). A relative path
      is relative to the current working directory, and in a release the
      files would go into the release directory and be lost on the next
      deploy.
    * `:url_prefix` - the path at which the files are served. The default
      is `"/uploads/kotoba"`. When `Kotoba.Storage.Local.Plug` serves the
      files, this is a path, not a full URL: the plug matches requests
      under it.

  Serve the files with `Kotoba.Storage.Local.Plug`. Any other way to serve
  them must send `X-Content-Type-Options: nosniff`, a content type from the
  allow-list of `Kotoba.Attachments`, and `Content-Disposition: attachment`
  for every type that is not an image or a PDF, as the plug does. A key is
  always a relative path under the root: a key that
  `Kotoba.Storage.valid_key?/1` refuses gives `{:error, :invalid_key}`, so
  a key cannot reach a file outside the root.
  """

  @behaviour Kotoba.Storage

  @default_prefix "/uploads/kotoba"

  @impl Kotoba.Storage
  def put(key, path, _meta) do
    with {:ok, destination} <- path(key),
         :ok <- File.mkdir_p(Path.dirname(destination)),
         :ok <- File.cp(path, destination) do
      {:ok, url(key)}
    end
  end

  @impl Kotoba.Storage
  def url(key) when is_binary(key), do: String.trim_trailing(url_prefix(), "/") <> "/" <> key

  @impl Kotoba.Storage
  def delete(key) do
    with {:ok, path} <- path(key) do
      case File.rm(path) do
        :ok -> :ok
        {:error, :enoent} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Returns the path on disk of the file with `key`, or
  `{:error, :invalid_key}`.
  """
  @spec path(Kotoba.Storage.key()) :: {:ok, Path.t()} | {:error, :invalid_key}
  def path(key) do
    root = root()

    with true <- Kotoba.Storage.valid_key?(key),
         path = Path.expand(key, root),
         true <- String.starts_with?(path, root <> "/") do
      {:ok, path}
    else
      false -> {:error, :invalid_key}
    end
  end

  @doc """
  Returns the configured root directory, as an absolute path.

  Raises `ArgumentError` when no root is configured.
  """
  @spec root() :: Path.t()
  def root do
    case Keyword.get(config(), :root) do
      root when is_binary(root) and root != "" ->
        Path.expand(root)

      _missing ->
        raise ArgumentError, """
        Kotoba.Storage.Local needs a root directory:

            config :kotoba, Kotoba.Storage.Local, root: "tmp/uploads"
        """
    end
  end

  @doc "Returns the configured URL prefix, by default `\"#{@default_prefix}\"`."
  @spec url_prefix() :: String.t()
  def url_prefix, do: Keyword.get(config(), :url_prefix, @default_prefix)

  defp config, do: Application.get_env(:kotoba, __MODULE__, [])
end
