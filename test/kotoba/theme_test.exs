defmodule Kotoba.ThemeTest do
  use ExUnit.Case, async: true

  @css Path.expand("../../assets/css", __DIR__)

  defp properties(file, pattern) do
    @css
    |> Path.join(file)
    |> File.read!()
    |> then(&Regex.scan(pattern, &1, capture: :all_but_first))
    |> List.flatten()
    |> MapSet.new()
  end

  test "kotoba-sumi.css sets every --kotoba-* property that kotoba.css uses" do
    used = properties("kotoba.css", ~r/(--kotoba-[a-z0-9]+(?:-[a-z0-9]+)*)/)
    set = properties("kotoba-sumi.css", ~r/^\s*(--kotoba-[a-z0-9-]+)\s*:/m)

    assert MapSet.difference(used, set) |> Enum.sort() == []
  end

  test "kotoba-sumi.css reads the Sumi tokens first" do
    sumi = File.read!(Path.join(@css, "kotoba-sumi.css"))

    for {property, token} <- [
          {"--kotoba-font", "--font-body"},
          {"--kotoba-heading-font", "--font-display"},
          {"--kotoba-text", "--color-base-content"},
          {"--kotoba-background", "--color-base-100"},
          {"--kotoba-surface", "--color-base-200"},
          {"--kotoba-border", "--color-base-300"},
          {"--kotoba-muted", "--sumi-text-muted"},
          {"--kotoba-accent", "--color-sumi-blade"}
        ] do
      assert sumi =~ ~r/^\s*#{property}: var\(#{token},/m, "#{property} does not read #{token}"
    end
  end

  test "the Sumi mention is ink on a tint, never the blade" do
    sumi = File.read!(Path.join(@css, "kotoba-sumi.css"))

    for property <- ["--kotoba-mention-text", "--kotoba-mention-background"] do
      [value] = Regex.run(~r/^\s*#{property}:([^;]+);/m, sumi, capture: :all_but_first)
      assert value =~ "--color-base-content"
      refute value =~ "blade"
    end
  end
end
