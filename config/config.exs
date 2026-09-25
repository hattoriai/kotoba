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
    ]
end
