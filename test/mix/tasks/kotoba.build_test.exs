defmodule Mix.Tasks.Kotoba.BuildTest do
  # Builds the real bundles into priv/static, so it does not run in parallel
  # with other tests.
  use ExUnit.Case, async: false

  @root Path.expand("../../..", __DIR__)
  @static Path.join(@root, "priv/static")
  @files ~w(kotoba.esm.js kotoba.cjs.js kotoba.css kotoba-sumi.css)

  @moduletag timeout: 600_000

  unless System.find_executable("npm") do
    @moduletag skip: "npm is not on the path, so mix kotoba.build cannot run"
  end

  test "mix kotoba.build writes the bundles and the style sheets" do
    mix = System.find_executable("mix") || flunk("mix is not on the path")

    {output, status} =
      System.cmd(mix, ["kotoba.build"],
        cd: @root,
        env: [{"MIX_ENV", "dev"}],
        stderr_to_stdout: true
      )

    assert status == 0, "mix kotoba.build failed:\n" <> output

    for file <- @files do
      path = Path.join(@static, file)
      assert File.regular?(path), "#{file} is missing"
      assert File.stat!(path).size > 0, "#{file} is empty"
    end

    esm = File.read!(Path.join(@static, "kotoba.esm.js"))
    [exports] = Regex.run(~r/export\{([^}]*)\}/, esm, capture: :all_but_first)
    names = exports |> String.split(",") |> Enum.map(&(&1 |> String.split(" as ") |> List.last()))

    assert "Kotoba" in names
    assert "AttachmentNode" in names
    assert "MentionNode" in names

    cjs = File.read!(Path.join(@static, "kotoba.cjs.js"))
    assert cjs =~ "Kotoba:()=>"
  end
end
