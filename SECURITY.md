# Security

## Reporting a vulnerability

Do not open a public issue for a security problem. Report it privately
through GitHub: [Report a vulnerability](https://github.com/hattoriai/kotoba/security/advisories/new).

Say what an attacker can do, and how: the document, the Markdown, the
upload or the event, and the steps or the payload. We answer within a
week, agree on a fix and a date, and credit you in the advisory unless
you ask us not to.

## Supported versions

Security fixes are made to the latest release. Kotoba is before 1.0, so
a fix is not backported to an earlier minor version.

## What is in scope

A document, a pasted text, an upload and every editor event come from
the browser, which any person can craft. A problem is in scope when such
input can:

- run a script, or put HTML or a URL that is not safe, in what Kotoba
  renders (`Kotoba.Renderer`, `<.kotoba_content>`, the cached HTML of
  `Kotoba.Content`), with the `:default` or the `:untrusted` policy;
- get past `Kotoba.Sanitizer`, the allowed link schemes, or
  `Kotoba.Content.validate_features/3`;
- make an upload served by `Kotoba.Storage.Local.Plug` run on the app's
  origin, or get a content type that its bytes do not prove;
- in collaboration, join a document, edit it or see it without the
  signed role and the app's authorization, or reach another document;
- crash the LiveView or the collaboration process, or make the server do
  unbounded work for a document of a size the app accepts.

What a person can edit, see or search is decided by the app: authorizing
the events, scoping the prompts, checking mentions and app nodes, and
limiting the size of a document are the app's job. The
[Security](guides/security.md) guide says what Kotoba checks and what
the app must do.
