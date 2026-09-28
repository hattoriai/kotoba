# Theming

Kotoba has two style sheets:

* `kotoba.css`: the structure of the editor (the layout, the toolbar, the
  menus, the nodes). Every colour, font, space and radius comes from a
  `--kotoba-*` custom property.
* `kotoba-sumi.css`: the Sumi theme. Sumi is the design system of Hattori
  AI, the makers of Kotoba: ink colours on paper surfaces, with the Outfit
  and Cormorant Garamond fonts. The theme sets every `--kotoba-*` property
  from the Sumi tokens, and it also works on a page that does not use
  Sumi.

```css
/* assets/css/app.css */
@import "../../deps/kotoba/priv/static/kotoba.css";
@import "../../deps/kotoba/priv/static/kotoba-sumi.css"; /* optional */
```

## The properties

The defaults of `kotoba.css` have no specificity (`:where(:root)`), so a
value that you set on `:root`, on an ancestor or on `.kotoba` wins:

```css
.kotoba {
  --kotoba-accent: #0f766e;
  --kotoba-radius: 0;
}
```

| Property | Default | Use |
|---|---|---|
| `--kotoba-font` | `system-ui, …` | the text of the editor |
| `--kotoba-heading-font` | `--kotoba-font` | headings |
| `--kotoba-font-mono` | `ui-monospace, …` | code |
| `--kotoba-font-size` | `1rem` | the text size |
| `--kotoba-line-height` | `1.6` | the line height |
| `--kotoba-small` | `0.875em` | small text (menus, hints, captions) |
| `--kotoba-h1-size` … `--kotoba-h4-size` | `1.75em` … `1.05em` | heading sizes |
| `--kotoba-heading-line-height` | `1.25` | the line height of headings |
| `--kotoba-text` | `#1f1f23` | the text colour |
| `--kotoba-muted` | `#6b6b76` | the placeholder, hints, quotes |
| `--kotoba-background` | `#ffffff` | the editor and the menus |
| `--kotoba-surface` | `#f6f6f7` | the toolbar, code, pressed buttons |
| `--kotoba-border` | `#d9d9de` | borders |
| `--kotoba-accent` | `#2f5bd3` | links, focus, the active option |
| `--kotoba-accent-text` | `#ffffff` | text on the accent |
| `--kotoba-selection` | the accent at 16% | selected nodes |
| `--kotoba-highlight` | a light yellow | highlighted text, the default highlight |
| `--kotoba-color-<name>` | the hue, mixed with the text colour | the text colors of the palette |
| `--kotoba-highlight-<name>` | the hue, faint | the highlights of the palette |
| `--kotoba-mention-text` | the accent | the text of a mention |
| `--kotoba-mention-background` | the selection | the tint behind a mention |
| `--kotoba-focus-ring` | `0 0 0 2px` accent | the `box-shadow` of focus |
| `--kotoba-shadow` | a soft shadow | the menus and the link form |
| `--kotoba-radius` | `6px` | corners |
| `--kotoba-space` | `0.5rem` | gaps |
| `--kotoba-padding` | `0.75rem 1rem` | the padding of the editable area |
| `--kotoba-min-height` | `8rem` | the height of an empty editor |
| `--kotoba-icon-size` | `18px` | toolbar icons |
| `--kotoba-token-*` | a light palette | code highlighting: `comment`, `keyword`, `string`, `constant`, `function`, `attr`, `variable`, `operator`, `punctuation`, `inserted`, `deleted` |

## Dark mode without Sumi

`kotoba.css` has one light palette. For a dark theme, set the colour
properties in your own dark rule:

```css
[data-theme="dark"] .kotoba,
.dark .kotoba {
  --kotoba-text: #e7e5e4;
  --kotoba-muted: #a8a29e;
  --kotoba-background: #1c1917;
  --kotoba-surface: #292524;
  --kotoba-border: #44403c;
}
```

## The Sumi theme

`kotoba-sumi.css` sets every `--kotoba-*` property. For each one it reads,
in this order:

1. the Sumi tokens of the page: `--font-body`, `--font-display`,
   `--color-sumi-blade`, `--color-sumi-ember`, `--color-sumi-ink`,
   `--sumi-text-muted`, `--sumi-text-secondary`, and the colours of the
   Sumi daisyUI themes (`--color-base-100`, `--color-base-200`,
   `--color-base-300`, `--color-base-content`, `--color-primary-content`,
   `--color-info`, `--color-success`, `--color-error`, `--radius-box`);
   The monospace font reads `--font-mono` first, the variable of
   Tailwind 4's default theme (not a Sumi token);
2. the short names `--sumi-font`, `--sumi-display`, `--sumi-mono`,
   `--sumi-ink`, `--sumi-paper`, `--sumi-surface`, `--sumi-line`,
   `--sumi-muted`, `--sumi-accent`, `--sumi-accent-ink` and
   `--sumi-radius`, for a page that sets them itself;
3. a built-in Sumi palette, so that the editor looks like Sumi on a page
   with no Sumi tokens.

Sizes and spaces have no Sumi token, so the theme gives them the Sumi
values.

Dark and light: on a page with the Sumi themes, the editor follows them,
because their colours change with `data-theme`. Without them, the
built-in palette follows the `data-theme` attribute (`"dark"` or
`"light"`) first, then `prefers-color-scheme`. The theme is resolved again
on every element with a `data-theme` attribute, so a part of the page with
its own theme gets it.

In an app with daisyUI (a new Phoenix 1.8 app has it), the theme reads the
app's own daisyUI colours (`--color-base-*`), with the Sumi accent. Kotoba
does not load the Sumi fonts (Outfit and Cormorant Garamond); load them
yourself if you want them.

Import `kotoba-sumi.css` from `app.css`, after `kotoba.css`. Tailwind 4
then sees the tokens that the theme reads, and puts them in the built CSS.

## Rendered content

`Kotoba.Components.kotoba_content/1` renders semantic HTML (`p`, `h1`–`h4`,
`blockquote`, `ul`, `ol`, `li`, `pre`, `code`, `strong`, `em`, `s`, `a`,
`hr`, `figure`) in a `div.kotoba-content`. `kotoba.css` does not style it
(but for the colors, below), so it takes the typography of your app, for
example:

```heex
<.kotoba_content content={@post.body} class="prose" />
```

Check lists have `class="kotoba-check"`, mentions `span.kotoba-mention`,
attachments `figure.kotoba-attachment`, and unknown nodes an empty
`span.kotoba-unknown`.

## Colors

The palette has seven names: `red`, `orange`, `yellow`, `green`, `blue`,
`purple` and `gray`. The editor stores a color as the name, never a CSS
value, so a theme decides what each one looks like. A text color renders
as `span.kotoba-color-<name>` and a highlight as `mark.kotoba-highlight-<name>`
(the default yellow highlight is a plain `mark`). `kotoba.css` has these
classes, the only rules it has for rendered content, and they read the
`--kotoba-color-<name>` and `--kotoba-highlight-<name>` properties. The
default text colors are mixed with `--kotoba-text`, so that they read on
a dark background too; set the properties for a palette of your own:

```css
.dark {
  --kotoba-color-red: #ff8a80;
  --kotoba-highlight-red: rgba(255, 138, 128, 0.3);
}
```

## Toolbar icons

The toolbar icons are Lucide icons inside the bundle, sized with
`--kotoba-icon-size`. To use your own icons, give a custom toolbar with a
`button` slot for each command (see the [Forms](forms.md) guide).

## Code highlighting and `window.Prism`

The editor highlights code blocks with its own copy of Prism, inside the
bundle. It saves the page's `window.Prism` before it loads its copy, and
puts it back after. So a page that uses Prism keeps its own, and the
editor's Prism is not on `window`. The token colours are the
`--kotoba-token-*` properties.

## Motion

`kotoba.css` turns off transitions, animations and smooth scrolling in the
editor when the person asks for reduced motion
(`prefers-reduced-motion: reduce`).
