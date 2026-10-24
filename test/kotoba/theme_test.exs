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

  test "the Sumi palette is dark in Sumi's dark themes, and light in its light ones" do
    sumi = File.read!(Path.join(@css, "kotoba-sumi.css"))

    for theme <- ~w(dark smoke stone lacquer) do
      assert sumi =~ ~r/\[data-theme="#{theme}"\][^{]*\{\s*--kotoba-sumi-base-100: oklch\(12%/
    end

    assert sumi =~
             ":root:not([data-theme=\"light\"], [data-theme=\"snow\"], [data-theme=\"silk\"]) {"
  end

  test "the Sumi orange is orange in every theme, not the theme's ember" do
    sumi = File.read!(Path.join(@css, "kotoba-sumi.css"))

    for property <- ["--kotoba-color-orange", "--kotoba-highlight-orange"] do
      [value] = Regex.run(~r/^\s*#{property}:([^;]+);/m, sumi, capture: :all_but_first)
      refute value =~ "ember"
    end
  end
end
