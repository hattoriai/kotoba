// The editor half of KotobaDev.Nodes.Tag (type "dev-tag").
//
// Kotoba calls this factory with the editor's copy of Lexical, so the
// class extends the same DecoratorNode as the built-in nodes. The keys of
// exportJSON() are the JSON keys of the fields of the Elixir module: a
// field with more than one word takes `key: "refId"` there, and the same
// "refId" key here.
// decorate() returns an HTMLElement, which Kotoba puts in the editor.
export default (lexical) =>
  class TagNode extends lexical.DecoratorNode {
    static getType() {
      return "dev-tag"
    }

    static clone(node) {
      return new TagNode(node.__label, node.__key)
    }

    static importJSON(json) {
      return new TagNode(String(json.label ?? ""))
    }

    constructor(label = "", key) {
      super(key)
      this.__label = label
    }

    exportJSON() {
      return {type: "dev-tag", version: 1, label: this.getLatest().__label}
    }

    createDOM() {
      const element = document.createElement(this.isInline() ? "span" : "div")
      element.className = "dev-tag"
      element.contentEditable = "false"
      return element
    }

    updateDOM() {
      return false
    }

    decorate() {
      const element = document.createElement("span")
      element.textContent = this.getLatest().__label
      return element
    }

    getTextContent() {
      return this.getLatest().__label
    }

    isInline() {
      return true
    }

    isKeyboardSelectable() {
      return true
    }
  }
