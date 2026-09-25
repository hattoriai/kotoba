import Config

if config_env() == :dev do
  # The editor bundles. Lexical comes from assets/node_modules, so NODE_PATH
  # is unset: the bundles never pick up a package from deps/.
  esbuild_args = ~w(
    src/index.ts
    --bundle
    --minify
    --sourcemap
    --target=es2020
    --conditions=production
    --define:process.env.NODE_ENV="production"
    --external:phoenix
    --external:phoenix_live_view
  )

  config :esbuild,
    version: "0.28.2",
    kotoba_esm: [
      args: esbuild_args ++ ~w(--format=esm --outfile=../priv/static/kotoba.esm.js),
      cd: Path.expand("../assets", __DIR__),
      env: %{"NODE_PATH" => nil}
    ],
    kotoba_cjs: [
      args: esbuild_args ++ ~w(--format=cjs --outfile=../priv/static/kotoba.cjs.js),
      cd: Path.expand("../assets", __DIR__),
      env: %{"NODE_PATH" => nil}
    ],
    # The JavaScript halves of the development server's nodes (dev.exs).
    kotoba_dev_nodes: [
      args:
        ~w(js/kotoba/nodes/*.js --bundle --format=esm --target=es2022 --outdir=../../priv/static/nodes),
      cd: Path.expand("../dev/assets", __DIR__),
      env: %{"NODE_PATH" => nil}
    ]
end

if config_env() == :test do
  config :logger, level: :warning
  config :phoenix, :json_library, JSON

  config :kotoba, KotobaTest.Endpoint,
    secret_key_base: String.duplicate("kotoba-test-secret-key-base-", 4),
    live_view: [signing_salt: "kotoba-test-salt"],
    pubsub_server: KotobaTest.PubSub,
    render_errors: [formats: [html: KotobaTest.ErrorHTML], layout: false],
    server: false
end
