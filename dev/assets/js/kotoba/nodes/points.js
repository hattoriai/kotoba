// The extension points: an extension that changes what the editor has
// already, for the browser tests (KotobaDev.PointsLive, /points).
//
//   * `link.suggest`: the link form lists the LiveView's pages
//     (`dev:pages`, with `context.request`) for the words typed.
//   * `link.open`: with `window.kotobaDevOwnLinkForm` set, the extension has
//     the link form; it keeps the request in `window.kotobaDevLinkRequest`.
//   * A built-in node's state: "Open in a new tab" puts the state `target`
//     on the link at the selection (Lexical's NodeState, `"$"` in its JSON),
//     and a mutation listener of the LinkNode shows it in the DOM. The
//     server half is KotobaDev.Overrides.Links.
//   * A text mark: a spoiler, an inline element over the text
//     (`api.inline`), KotobaDev.Nodes.Spoiler on the server.
//
// `window.kotobaDevApi` has the names that the API gives, for the tests.

export default (api) => {
  const { lexical, utils, link, inline } = api
  window.kotobaDevApi = Object.keys(api).sort()

  class SpoilerNode extends lexical.ElementNode {
    static getType() {
      return "dev-spoiler"
    }

    static clone(node) {
      return new SpoilerNode(node.__key)
    }

    static importJSON(json) {
      return new SpoilerNode().updateFromJSON(json)
    }

    exportJSON() {
      return {...super.exportJSON(), type: "dev-spoiler", version: 1}
    }

    createDOM() {
      const element = document.createElement("span")
      element.className = "dev-spoiler"
      return element
    }

    updateDOM() {
      return false
    }

    isInline() {
      return true
    }

    canBeEmpty() {
      return false
    }

    canInsertTextBefore() {
      return false
    }

    canInsertTextAfter() {
      return false
    }
  }

  const target = lexical.createState("target", {
    parse: (value) => (typeof value === "string" ? value : undefined),
  })

  const $selectedLink = () => {
    const selection = lexical.$getSelection()
    if (!lexical.$isRangeSelection(selection)) return null
    return utils.$findMatchingParent(selection.anchor.getNode(), link.$isLinkNode)
  }

  return {
    name: "points",
    nodes: [SpoilerNode],

    toolbar: [
      {
        command: "spoiler",
        label: "Spoiler",
        run: (editor) => editor.update(() => inline.$toggle(SpoilerNode, () => new SpoilerNode())),
        isActive: () => inline.$isActive(SpoilerNode),
      },
      {
        command: "new-tab",
        label: "Open in a new tab",
        run: (editor) =>
          editor.update(() => {
            const node = $selectedLink()
            if (node === null) return
            lexical.$setState(node, target, lexical.$getState(node, target) === "_blank" ? undefined : "_blank")
          }),
        isActive: () => {
          const node = $selectedLink()
          return node !== null && lexical.$getState(node, target) === "_blank"
        },
        isEnabled: () => $selectedLink() !== null,
      },
    ],

    link: {
      async suggest(query, context) {
        const reply = await context.request("dev:pages", {query})
        return reply.pages
      },
      open(request) {
        if (!window.kotobaDevOwnLinkForm) return false
        window.kotobaDevLinkRequest = request
        return true
      },
    },

    register(editor) {
      // The state shows in the DOM: the link's element gets data-target.
      return editor.registerMutationListener(link.LinkNode, (mutations) => {
        editor.getEditorState().read(() => {
          for (const [key, mutation] of mutations) {
            if (mutation === "destroyed") continue
            const node = lexical.$getNodeByKey(key)
            const element = editor.getElementByKey(key)
            if (node === null || element === null) continue
            const value = lexical.$getState(node, target)
            if (value === undefined) delete element.dataset.target
            else element.dataset.target = value
          }
        })
      })
    },
  }
}
