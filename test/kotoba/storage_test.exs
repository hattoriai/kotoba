defmodule Kotoba.StorageTest do
  use ExUnit.Case, async: true

  alias Kotoba.Storage

  doctest Kotoba.Storage

  describe "key/1" do
    test "is yyyy/mm/<uuid>-<safe name> for this month" do
      now = DateTime.utc_now()
      key = Storage.key("cat.png")

      assert [year, month, file] = String.split(key, "/")
      assert year == Integer.to_string(now.year)
      assert month == now.month |> Integer.to_string() |> String.pad_leading(2, "0")

      assert file =~
               ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}-cat\.png\z/

      assert Storage.valid_key?(key)
    end

    test "is new each time" do
      refute Storage.key("a") == Storage.key("a")
    end

    test "is valid for any name" do
      for name <- ["../../x", "..", ".", "", "a/b\\c", "名前.txt", String.duplicate("x", 500)] do
        assert Storage.valid_key?(Storage.key(name)), "not valid for #{inspect(name)}"
      end
    end
  end

  describe "safe_name/1" do
    test "keeps only safe characters, and at most 100" do
      assert Storage.safe_name("a b/c\\d:e.txt") == "a_b_c_d_e.txt"
      assert Storage.safe_name("..") == "file"
      assert Storage.safe_name("...hidden") == ".hidden"

      long = Storage.safe_name(String.duplicate("x", 300) <> ".jpeg")
      assert byte_size(long) == 100
      assert String.ends_with?(long, "xx.jpeg")
    end
  end

  describe "valid_key?/1" do
    test "refuses keys that can leave the root" do
      for key <- [
            "",
            "/",
            "a//b",
            "a/",
            "..",
            "a/../b",
            "./a",
            "a\\b",
            "a/b\u0000",
            "~/a",
            nil,
            1
          ] do
        refute Storage.valid_key?(key), "valid: #{inspect(key)}"
      end

      refute Storage.valid_key?(String.duplicate("a", 256))
    end
  end

  test "adapter/0 is Kotoba.Storage.Local by default" do
    assert Storage.adapter() == Kotoba.Storage.Local
  end
end
