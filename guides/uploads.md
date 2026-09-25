# Uploads

The editor takes files from its "Attach a file" button, from a drop and
from a paste. It gives them to a normal LiveView upload. The LiveView
stores each finished file through a `Kotoba.Storage` adapter, and the
editor puts an attachment node (an image or a file link) in the place of
the file's marker.

## The LiveView

```elixir
def mount(_params, _session, socket) do
  {:ok,
   socket
   |> assign(form: to_form(Blog.change_post(%Post{})))
   |> allow_upload(:attachments,
     accept: ~w(.png .jpg .jpeg .gif .webp .pdf),
     max_file_size: 10_000_000,
     max_entries: 5,
     auto_upload: true,
     progress: &handle_progress/3
   )}
end

defp handle_progress(:attachments, entry, socket) do
  if entry.done? do
    {:noreply, Kotoba.Live.consume_uploads(socket, :attachments, "post-body")}
  else
    {:noreply, socket}
  end
end

# The form's phx-change handler: a file that fails validation (too large,
# a type that is not accepted) loses its marker here.
def handle_event("validate", %{"post" => params}, socket) do
  socket = Kotoba.Live.consume_uploads(socket, :attachments, "post-body")
  {:noreply, assign(socket, form: to_form(Blog.change_post(%Post{}, params), action: :validate))}
end
```

```heex
<.kotoba field={@form[:body]} id="post-body" uploads={@uploads.attachments} />
```

Use `auto_upload: true`. The file then goes to the server when the person
adds it, and the attachment is in the document before the form is
submitted. Without it, LiveView sends the files only with the submit, after
the document was posted.

`Kotoba.Live.consume_uploads/4` does this for each entry:

* An entry that is done: it checks the file (`Kotoba.Attachments`),
  stores it under a new key, and pushes an attachment node with the URL
  that the adapter gives. The node takes the place of that entry's marker,
  also when the uploads finish in another order.
* An entry with an error: it cancels the entry and removes its marker.
  Read `upload_errors/2` before the call to show the error.
* An entry that is not done: it does nothing.

When the check or the adapter fails, it logs a warning and removes the
marker.

## What Kotoba checks

The size limit and the accepted extensions are the ones of
`Phoenix.LiveView.allow_upload/3`. Then Kotoba reads the first bytes of
each file on the server. It keeps a content type only when the bytes prove
it: PNG, JPEG, GIF and WebP images, PDF, UTF-8 plain text, ZIP and Office
files. Every other file is stored as `application/octet-stream`. The type
that the browser sends is not trusted.

The storage key takes its extension from the checked type, never from the
client's file name. So a key never ends in `.html` or `.svg`. The file
name stays in the node for display, without control characters and
without bidirectional format characters.

## The local adapter

`Kotoba.Storage.Local` keeps the files in a directory:

```elixir
# config/config.exs
config :kotoba, storage: Kotoba.Storage.Local

# config/runtime.exs
if config_env() == :prod do
  config :kotoba, Kotoba.Storage.Local,
    root: System.get_env("KOTOBA_UPLOADS", "/var/lib/my_app/uploads"),
    url_prefix: "/uploads/kotoba"
end

# config/dev.exs
config :kotoba, Kotoba.Storage.Local, root: Path.expand("../tmp/uploads", __DIR__)
```

In a release, give an absolute `root` outside the release directory, in
the `:prod` block of `config/runtime.exs`. A relative path is relative to
the working directory, and files in the release directory are lost at the
next deploy. Keep the production root inside the `:prod` block:
`config/runtime.exs` runs in every environment, after `config/dev.exs`,
so outside the block it would replace the development root.

Serve the files with `Kotoba.Storage.Local.Plug`, in the endpoint before
the router:

```elixir
plug Kotoba.Storage.Local.Plug
```

or in the router:

```elixir
forward "/uploads/kotoba", Kotoba.Storage.Local.Plug, at: "/"
```

### Files behind a login, per tenant

The endpoint plug and a `forward` serve every file to every visitor. When
only the people of an account may see its files, and the account is a
dynamic segment of the path (`/:org_slug/...`), serve the files from a
route in the scope that checks the login, and start each key with the
path of that route:

```elixir
# config/config.exs
config :kotoba, Kotoba.Storage.Local, url_prefix: "/"

# The LiveView: keys like "acme/uploads/2026/09/<uuid>-name.png"
Kotoba.Live.consume_uploads(socket, :attachments, "post-body",
  key: &("#{slug}/uploads/" <> Kotoba.Storage.key(&1.client_name, &2))
)

# The router, in the scope that requires a member of :org_slug
get "/uploads/*key", Kotoba.Storage.Local.Plug, [at: "/"], alias: false
```

The URL of a file is then its key, the router lets only the account's
people reach it, and the plug serves the file at that path under the
root. `forward` cannot take a path with a dynamic segment, so use a
`get` route (`alias: false` keeps the scope's alias off the module).

The plug serves only `GET` and `HEAD`, with safe headers. See the
[Security](security.md) guide. Do not serve the directory with
`Plug.Static`: it sends none of these headers.

## Another store

Write a module with the three callbacks of `Kotoba.Storage` (`put/3`,
`url/1` and `delete/1`) and name it in the config:

```elixir
config :kotoba, storage: MyApp.KotobaStorage
```

or give it per call: `consume_uploads(socket, :attachments, "post-body",
storage: MyApp.KotobaStorage)`. The `Kotoba.Storage` docs have a full
example for S3.

Two rules for an adapter:

* Store each file with its checked content type (`meta.content_type`), and
  with `Content-Disposition: attachment` for every type that
  `Kotoba.Attachments.inline?/1` refuses. Without this, a store such as S3
  serves an uploaded HTML file inline, and it can run a script on the
  store's origin.
* The URL goes into the stored document, so it must stay valid. Give a
  public or CDN URL, or a path in your app (for example `"/files/" <>
  key`) whose controller checks access and redirects to a short-lived
  signed URL.

The `:key` option of `Kotoba.Live.consume_uploads/4` changes how the keys
are made.

## Direct uploads are not supported

LiveView's `external:` uploads (the browser sends the file straight to a
cloud store) are not supported. The file always comes to the LiveView
first, and the adapter then sends it on. Kotoba must read the bytes to
check the content type.

## Deleted attachments

Kotoba does not delete a stored file when a person removes its attachment
from a document. `Kotoba.Document.attachments/1` gives the attachments of a
document, so a job can compare them with the files in the store and call
the adapter's `delete/1`.
