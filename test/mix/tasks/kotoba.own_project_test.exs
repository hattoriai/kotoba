defmodule Mix.Tasks.Kotoba.OwnProjectTest do
  # Mix.Project.in_project/4 changes the current Mix project for the whole
  # VM, so this module does not run in parallel with other tests.
  use ExUnit.Case, async: false

  alias Mix.Tasks.Kotoba.{Build, ReleaseCheck}

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    File.write!(Path.join(tmp_dir, "mix.exs"), """
    defmodule KotobaHostApp.MixProject do
      use Mix.Project
      def project, do: [app: :kotoba_host_app, version: "1.0.0"]
    end
    """)

    static = Path.join(tmp_dir, "priv/static")
    File.mkdir_p!(static)
    robots = Path.join(static, "robots.txt")
    File.write!(robots, "User-agent: *")

    %{robots: robots}
  end

  test "the guards accept only the Kotoba project" do
    assert Build.ensure_kotoba!(app: :kotoba) == :ok
    assert ReleaseCheck.ensure_kotoba!(app: :kotoba) == :ok

    assert_raise Mix.Error, ~r/^mix kotoba.build is for work on Kotoba itself/, fn ->
      Build.ensure_kotoba!(app: :my_app)
    end

    assert_raise Mix.Error, ~r/^mix kotoba.release_check is for work on Kotoba itself/, fn ->
      ReleaseCheck.ensure_kotoba!(app: :my_app)
    end
  end

  test "mix kotoba.build stops in an application and keeps its priv/static", %{
    tmp_dir: tmp_dir,
    robots: robots
  } do
    Mix.Project.in_project(:kotoba_host_app, tmp_dir, fn _module ->
      assert_raise Mix.Error, ~r/an app gets the built files in the Hex package/, fn ->
        Build.run([])
      end
    end)

    assert File.read!(robots) == "User-agent: *"
  end

  test "mix kotoba.release_check stops in an application", %{tmp_dir: tmp_dir} do
    Mix.Project.in_project(:kotoba_host_app, tmp_dir, fn _module ->
      assert_raise Mix.Error, ~r/checks the files of a Kotoba release/, fn ->
        ReleaseCheck.run([])
      end
    end)
  end
end
