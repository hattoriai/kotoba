defmodule Kotoba.StorageTest do
  # The store is application config.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Kotoba.Storage

  setup do
    on_exit(fn ->
      Application.delete_env(:kotoba, :storage)
      Application.delete_env(:kotoba, Kotoba.Storage.Local)
      :persistent_term.erase({Storage, :warned})
    end)
  end

  describe "adapter/0" do
    test "is Storehouse's store by default" do
      assert Storage.adapter() == Storehouse.adapter()
    end

    test "is the store of config :kotoba, storage:, with a deprecation warning, once" do
      Application.put_env(:kotoba, :storage, MyApp.KotobaStorage)

      log = capture_log(fn -> assert Storage.adapter() == MyApp.KotobaStorage end)
      assert log =~ "config :kotoba, storage: MyApp.KotobaStorage is deprecated"
      assert log =~ "config :storehouse, adapter: MyApp.KotobaStorage"

      assert capture_log(fn -> Storage.adapter() end) == ""
    end

    test "is Kotoba.Storage.Local when the app configures it" do
      Application.put_env(:kotoba, Kotoba.Storage.Local, root: "tmp")
      assert Storage.adapter() == Kotoba.Storage.Local

      Application.put_env(:kotoba, :storage, Kotoba.Storage.Local)
      assert capture_log(fn -> assert Storage.adapter() == Kotoba.Storage.Local end) == ""
    end
  end

  test "uploads without Storehouse in the deps say what is missing" do
    assert_raise ArgumentError, ~r/\{:storehouse, "~> 0.1"\}/, fn ->
      Kotoba.Live.missing_storehouse!()
    end
  end
end
