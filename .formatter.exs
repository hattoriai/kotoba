# `field` of `Kotoba.Node`; an app gets it with `import_deps: [:kotoba]`.
locals_without_parens = [field: 2, field: 3]

[
  import_deps: [:ecto, :phoenix_html, :phoenix_live_view],
  locals_without_parens: [attr: 2, attr: 3, slot: 1, slot: 2, slot: 3] ++ locals_without_parens,
  inputs: ["{mix,.formatter,dev}.exs", "{config,lib,test,dev}/**/*.{ex,exs}"],
  export: [locals_without_parens: locals_without_parens]
]
