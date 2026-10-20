# Contributing to Kotoba

Thank you for helping. This page says what to open (an issue, a pull
request, or a security report), what a pull request needs, and what the
maintainers keep for themselves. How to build the editor, run the
development server and run the tests is in the README, under
[Development](README.md#development).

## Questions, bugs and ideas

- **A bug.** Open an issue with the bug report form. The smallest
  document or editor that shows it (the `<.kotoba>` or `<.kotoba_content>`
  call, its features, and the document JSON or the Markdown) is the most
  useful thing you can give.
- **An idea or a change of behaviour.** Open an issue with the feature
  request form, and say the problem before the solution.
- **A security problem.** Do not open an issue. See
  [SECURITY.md](SECURITY.md).

Search the open and closed issues first: the idea may already be planned,
or turned down for a reason given there. `BACKLOG.md` lists known gaps.

## When a pull request needs an issue first

Open an issue, and agree on the change there, before a pull request that:

- adds a feature, a node, an attribute, an option, a callback or a
  toolbar command;
- changes what the editor, the renderer, the sanitizer, `Kotoba.Content`
  or collaboration does, or its public API;
- changes the document format, the stored content, or the events between
  the browser and the LiveView;
- adds a dependency, an Elixir one or an npm one in `assets/`;
- touches many files, or needs a design decision.

A pull request does not need an issue when it is small and its reason is
plain from the diff: a typo, a broken link, a wrong sentence in a guide,
or a bug fix with a test that fails without it. When in doubt, open the
issue: a short discussion costs less than a pull request that is not
merged.

A pull request with an issue says so: `Fixes #123` or `Closes #123`.

## A pull request

- **One change.** A fix, the guides for an unrelated case and a README
  edit are three pull requests. Each is reviewed, reverted and released
  on its own.
- **Why, not only what.** The description says the problem the change
  solves, for whom, and what happened before it: an error, a crash, a
  document that rendered wrong. Say why a number was chosen when the
  change adds one.
- **Tests.** A bug fix has a test that fails on `main` and passes with
  the fix. A feature has tests of what it does, and of its errors. A
  change the browser sees has a Playwright spec in `e2e/`.
- **Docs.** A change a user can see updates the guide it belongs to and
  the `[Unreleased]` section of [CHANGELOG.md](CHANGELOG.md).
- **The checks pass.** CI runs them; run them first:

  ```sh
  mix format --check-formatted
  MIX_ENV=test mix compile --warnings-as-errors
  MIX_ENV=test mix credo --strict
  mix docs
  mix test
  mix dialyzer
  ```

  `mix precommit` runs most of them at once. A change to `assets/` or to
  what the browser sees also runs `mix test.e2e` (CI runs it in Chromium,
  Firefox and WebKit). CI also runs the tests on the oldest versions that
  Kotoba supports, Elixir 1.18 (OTP 27), Phoenix 1.7 and LiveView 1.1:
  with `KOTOBA_OLDEST=1` set, `mix deps.update phoenix phoenix_live_view`,
  then `mix test`. The checks need the files in `priv/static`: run
  `mix kotoba.build` once, as the README says.

The pull request template has these as a checklist.

## What the maintainers keep

- **Releases.** The version in `mix.exs` and `package.json`, the release
  headings of the changelog and the tags are changed by the maintainers,
  at a release (`mix release`).
- **The built bundle.** The files in `priv/static` are built at a
  release and are not in the repository. A pull request changes the
  source in `assets/`, not the bundle.

## Style

Match the code around your change: its naming, its comments and the way
its guides are written. `mix format` and `mix credo --strict` settle the
rest of the Elixir.

## License

By contributing, you agree that your contribution is released under the
MIT License of the project (see [LICENSE](LICENSE)).
