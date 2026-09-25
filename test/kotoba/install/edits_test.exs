defmodule Kotoba.Install.EditsTest do
  use ExUnit.Case, async: true

  alias Kotoba.Install.Edits

  @fixtures Path.expand("../../fixtures/phoenix", __DIR__)

  defp fixture(name), do: File.read!(Path.join(@fixtures, name))

  defp socket(options), do: ~s|const liveSocket = new LiveSocket("/live", Socket, #{options})\n|

  describe "app_js/1" do
    test "adds the import and the hook to the Phoenix 1.8 app.js" do
      source = fixture("app.js")
      assert {:changed, new} = Edits.app_js(source)

      assert new =~
               ~s(import topbar from "../vendor/topbar"\nimport { Kotoba } from "kotoba"\n)

      assert new =~ "  hooks: {...colocatedHooks, Kotoba},\n"
      assert Edits.app_js(new) == :unchanged

      # Only the two lines change.
      assert length(String.split(new, "\n")) == length(String.split(source, "\n")) + 1
    end

    test "keeps an import that is there" do
      source = ~s(import { Kotoba } from "kotoba"\n) <> socket("{hooks: {}}")
      assert {:changed, new} = Edits.app_js(source)
      assert new == ~s(import { Kotoba } from "kotoba"\n) <> socket("{hooks: {Kotoba}}")
    end

    test "adds a hooks key to options without one" do
      assert {:changed, new} = Edits.app_js(socket("{params: {_csrf_token: csrfToken}}"))
      assert new =~ socket("{hooks: {Kotoba}, params: {_csrf_token: csrfToken}}")

      assert {:changed, new} = Edits.app_js(socket("{}"))
      assert new =~ socket("{hooks: {Kotoba}}")

      assert {:changed, new} = Edits.app_js(socket("{\n  params: {_csrf_token: csrfToken}\n}"))
      assert new =~ socket("{\n  hooks: {Kotoba},\n  params: {_csrf_token: csrfToken}\n}")
    end

    test "adds to a hooks object on several lines" do
      assert {:changed, new} =
               Edits.app_js(socket("{\n  hooks: {\n    ...colocatedHooks,\n    Chart\n  },\n}"))

      assert new =~
               socket("{\n  hooks: {\n    ...colocatedHooks,\n    Chart,\n    Kotoba,\n  },\n}")

      assert Edits.app_js(new) == :unchanged
    end

    test "spreads a hooks variable" do
      source = "let Hooks = {}\n" <> socket("{hooks: Hooks, params: {}}")
      assert {:changed, new} = Edits.app_js(source)
      assert new =~ socket("{hooks: {...Hooks, Kotoba}, params: {}}")
      assert Edits.app_js(new) == :unchanged
    end

    test "leaves a hooks variable that already has Kotoba" do
      source =
        ~s(import { Kotoba } from "kotoba"\nlet Hooks = {}\nHooks.Kotoba = Kotoba\n) <>
          socket("{hooks: Hooks}")

      assert Edits.app_js(source) == :unchanged
    end

    test "is not misled by strings and comments" do
      source =
        ~s|// new LiveSocket("/live", Socket, {hooks: {Kotoba}})\n| <>
          socket(~s|{params: {note: "hooks: {x}"}, /* hooks: {} */ hooks: {...colocatedHooks}}|)

      assert {:changed, new} = Edits.app_js(source)
      assert new =~ ~s|hooks: {...colocatedHooks, Kotoba}}|
      assert new =~ ~s|"hooks: {x}"|
      assert new =~ ~s|// new LiveSocket("/live", Socket, {hooks: {Kotoba}})|
    end

    test "gives the lines to add when it cannot find the constructor" do
      for source <- [
            "console.log(1)\n",
            socket("options"),
            socket("{hooks: makeHooks()}"),
            ~s|// new LiveSocket("/live", Socket, {hooks: {}})\n|
          ] do
        assert {:manual, text} = Edits.app_js(source)
        assert text =~ ~s(import { Kotoba } from "kotoba")
        assert text =~ "hooks: {...colocatedHooks, Kotoba}"
      end

      source = ~s(import { Kotoba } from "kotoba"\n) <> socket("options")
      assert {:manual, text} = Edits.app_js(source)
      refute text =~ "Add the import"
    end
  end

  describe "app_css/1" do
    test "adds the imports after the last @import of the Phoenix 1.8 app.css" do
      source = fixture("app.css")
      assert {:changed, new} = Edits.app_css(source)

      assert new =~
               """
               @import "tailwindcss" source(none);
               @import "../../deps/kotoba/priv/static/kotoba.css";
               /* @import "../../deps/kotoba/priv/static/kotoba-sumi.css"; */
               @source "../css";
               """

      assert Edits.app_css(new) == :unchanged
    end

    test "adds only what is missing" do
      source = ~s(@import "../../deps/kotoba/priv/static/kotoba.css";\nbody {}\n)
      assert {:changed, new} = Edits.app_css(source)

      assert new ==
               ~s(@import "../../deps/kotoba/priv/static/kotoba.css";\n) <>
                 ~s(/* @import "../../deps/kotoba/priv/static/kotoba-sumi.css"; */\nbody {}\n)

      source = ~s(@import "../../deps/kotoba/priv/static/kotoba-sumi.css";\n)
      assert {:changed, new} = Edits.app_css(source)
      assert new =~ ~s(@import "../../deps/kotoba/priv/static/kotoba.css";)
      refute new =~ "/* @import"
    end

    test "puts the imports at the top when there is no @import" do
      assert {:changed, new} = Edits.app_css("body { margin: 0 }\n")
      assert String.starts_with?(new, ~s(@import "../../deps/kotoba/priv/static/kotoba.css";\n))
    end
  end

  describe "config/2" do
    test "adds the storage config above import_config" do
      source = fixture("config.exs")
      assert {:changed, new} = Edits.config(source, :my_app)

      assert new =~
               """
               # Kotoba stores the files of the editor's uploads with this adapter.
               # Give it a directory in config/runtime.exs, an absolute path outside
               # the release:
               #
               #     config :kotoba, Kotoba.Storage.Local,
               #       root: System.get_env("KOTOBA_UPLOADS", "/var/lib/my_app/uploads"),
               #       url_prefix: "/uploads/kotoba"
               config :kotoba, storage: Kotoba.Storage.Local

               # Import environment specific config. This must remain at the end
               # of this file so it overrides the configuration above.
               import_config "\#{config_env()}.exs"
               """

      assert Code.string_to_quoted!(new)
      assert Edits.config(new, :my_app) == :unchanged
    end

    test "appends the config when there is no import_config" do
      assert {:changed, new} = Edits.config("import Config\n", :my_app)
      assert new =~ ~r/\Aimport Config\n\n# Kotoba stores/
      assert String.ends_with?(new, "config :kotoba, storage: Kotoba.Storage.Local\n")
    end

    test "leaves a storage config that is there" do
      assert Edits.config("config :kotoba, storage: MyApp.S3\n") == :unchanged

      assert Edits.config("config :kotoba,\n  nodes: [MyApp.Pointer],\n  storage: MyApp.S3\n") ==
               :unchanged
    end

    test "is not misled by other Kotoba config" do
      source =
        "config :kotoba, nodes: [MyApp.Pointer]\nconfig :kotoba, Kotoba.Storage.Local, root: \"/x\"\n"

      assert {:changed, _new} = Edits.config(source)
    end
  end

  test "node_path?/1" do
    assert Edits.node_path?(fixture("config.exs"))
    refute Edits.node_path?("config :esbuild, version: \"0.25.4\"\n")
  end

  test "diff/3 shows the changed lines with some context" do
    diff = Edits.diff("a.txt", "1\n2\n3\n4\n5\n6\n7\n", "1\n2\n3\nnew\n4\n5\n6\n7\n")

    assert diff == """
           --- a.txt
           +++ a.txt
             ...
             2
             3
           + new
             4
             5
             ...
           """
  end
end
