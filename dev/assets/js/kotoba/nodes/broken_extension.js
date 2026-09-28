// An extension whose register throws, for the browser tests: the editor
// logs it and mounts with its other extensions.
export default () => ({
  name: "broken",
  register() {
    throw new Error("broken on purpose")
  },
})
