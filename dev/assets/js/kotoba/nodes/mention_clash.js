// A node module whose node has the type of a built-in node ("mention").
// The editor must refuse the node, log it, and still mount. The browser
// tests load it on /nodes?case=builtin.
export default (lexical) =>
  class MentionClashNode extends lexical.DecoratorNode {
    static getType() {
      return "mention"
    }

    static clone(node) {
      return new MentionClashNode(node.__key)
    }

    static importJSON() {
      return new MentionClashNode()
    }

    exportJSON() {
      return {type: "mention", version: 1}
    }

    createDOM() {
      return document.createElement("span")
    }

    updateDOM() {
      return false
    }

    decorate() {
      return document.createElement("span")
    }
  }
