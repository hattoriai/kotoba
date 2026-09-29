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
it: PNG, JPEG, GIF and WebP images, PDF, MP4 and WebM video, UTF-8 plain
text, ZIP and Office files. Every other file is stored as
`application/octet-stream`. The type
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

## Galleries

Images uploaded together (picked, dropped or pasted at once) go in a
gallery: a `gallery` node that holds their attachments, shown in a grid.
Each image takes the place of its own marker in the gallery, so the order
of the files stays when the uploads finish in another order, and a failed
upload leaves the others in place. An image uploaded while an image of a
gallery is selected joins that gallery, after it.

The person groups and ungroups images with the Gallery button of the
toolbar's Image group, which shows while an image is selected: Gallery
makes a gallery of the selected image and the images next to it (empty
paragraphs between them go), and in a gallery puts its images back as
blocks of their own. Move image left and Move image right (and
`Alt+Left`, `Alt+Right`) reorder the images; Backspace and Delete remove
one. A gallery with one image left becomes that image.

A gallery is part of the `attachments` feature, and valid only under the
root. Its HTML is a `div.kotoba-gallery` with the `figure` of each image,
and `kotoba.css` lays it out as a grid. `Kotoba.Document.attachments/1`
returns the attachments of galleries too, in order.

## PDF and video previews

A PDF and a video show in the document, not as a file name:

* **PDF**: the browser's PDF viewer shows it, in the editor and in the
  rendered HTML (an `object` element). A browser with no viewer (most
  phones) shows a download link instead. The caption is always a download
  link.
* **Video**: MP4 (`video/mp4`) and WebM (`video/webm`) files play in a
  `video` element with the browser's controls. It loads only the metadata
  (`preload="metadata"`) and never plays by itself. In the editor, a video
  that the browser cannot play (a codec it does not have, a missing file)
  shows as a file. Other formats (QuickTime `.mov`, Matroska `.mkv`) are
  files: convert them to MP4 (H.264 and AAC plays in every browser) before
  or after the upload.

Add the extensions to the upload, and a size limit for videos:

```elixir
allow_upload(:attachments,
  accept: ~w(.png .jpg .jpeg .gif .webp .pdf .mp4 .webm),
  max_file_size: 100_000_000,
  ...
)
```

### Preview images

A PDF can show an image of its first page, and a video a poster frame,
instead. Kotoba does not make them: give `:preview` to
`Kotoba.Live.consume_uploads/4`, a function of the stored attachment and
the path of the uploaded file that returns the URL of the image, or `nil`.
It runs while the file is still there. With Poppler and FFmpeg installed:

```elixir
Kotoba.Live.consume_uploads(socket, :attachments, "post-body",
  preview: &MyApp.Previews.make/2
)
```

```elixir
defmodule MyApp.Previews do
  alias Kotoba.Nodes.Attachment

  # The first page of a PDF (Poppler), the first frame of a video (FFmpeg).
  def make(%Attachment{} = node, path) do
    cond do
      Attachment.pdf?(node) -> store(node, ".png", &pdftoppm(path, &1))
      Attachment.video?(node) -> store(node, ".jpg", &ffmpeg(path, &1))
      true -> nil
    end
  end

  defp pdftoppm(path, image),
    do: System.cmd("pdftoppm", ["-png", "-singlefile", "-r", "72", path, Path.rootname(image)])

  defp ffmpeg(path, image),
    do: System.cmd("ffmpeg", ["-v", "error", "-i", path, "-frames:v", "1", image])

  # Renders the image to a temporary file and stores it next to the file.
  defp store(node, extension, render) do
    image = Path.join(System.tmp_dir!(), "preview-#{System.unique_integer([:positive])}#{extension}")

    try do
      with {_output, 0} <- render.(image),
           {:ok, %File.Stat{size: bytes}} <- File.stat(image),
           meta = %{
             name: node.name,
             content_type: Kotoba.Attachments.content_type(extension),
             bytes: bytes
           },
           {:ok, url} <- Kotoba.Storage.adapter().put(node.key <> extension, image, meta) do
        url
      else
        _error -> nil
      end
    after
      File.rm(image)
    end
  end
end
```

The URL goes into the attachment's `preview`. A result that is not a safe
URL, or an exception, gives no preview and logs a warning: the upload is
stored either way. The function runs in the LiveView process: give the
tools a time limit (for example in a `Task` with `Task.yield/2`), and run
them only on the checked PDFs and videos (`pdf?/1` and `video?/1` read the
checked type, as above).

### Serving PDFs and videos

The editor and the rendered page load the file from its URL, so:

* **Same origin, private files**: a URL on your app (the local plug, or a
  controller that checks access) works as it is: the browser sends the
  page's cookies with the `object` and `video` requests.
* **Signed URLs**: a URL that expires breaks the preview of a stored
  document. Give a path in your app that redirects to a fresh signed URL.
* **Range requests**: a video needs them to seek, and Safari to play at
  all. `Kotoba.Storage.Local.Plug` answers `Range` with `206`; S3 and most
  stores do too. A controller that sends a file with `send_file/3` does
  not: use `Plug.Static`'s range handling or `Kotoba.Storage.Local.Plug`.
* **Headers**: `Content-Type` from the checked type, and
  `Content-Disposition: inline` (`Kotoba.Attachments.inline?/1` is `true`
  for PDF, MP4 and WebM). `Content-Security-Policy: default-src 'none';
  sandbox` on the file does not stop the PDF viewer or the player.
* **Your page's CSP**: if your app sends a `Content-Security-Policy`, allow
  the files' origin in `object-src` (PDF), `media-src` (video) and
  `img-src` (images and previews).

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
