defmodule Kotoba.AttachmentsTest do
  use ExUnit.Case, async: true

  alias Kotoba.Attachments
  alias Kotoba.Nodes.Attachment

  doctest Kotoba.Attachments

  setup do
    dir = Path.join(System.tmp_dir!(), "kotoba-attachments-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  defp describe_bytes(dir, bytes, type) do
    path = Path.join(dir, "file")
    File.write!(path, bytes)
    {:ok, description} = Attachments.describe(path, type)
    description
  end

  test "reads PNG, GIF, JPEG and WebP sizes from the bytes", %{dir: dir} do
    png = <<0x89, "PNG\r\n", 0x1A, "\n", 13::32, "IHDR", 640::32, 480::32, 8, 6, 0, 0, 0>>
    gif = <<"GIF89a", 10::little-16, 20::little-16, 0, 0, 0>>

    jpeg =
      <<0xFF, 0xD8, 0xFF, 0xE0, 16::16, "JFIF", 0, 1, 1, 0, 0, 1, 0, 1, 0, 0>> <>
        <<0xFF, 0xDB, 4::16, 0, 0>> <> <<0xFF, 0xC0, 17::16, 8, 300::16, 400::16, 3>>

    webp_x =
      <<"RIFF", 0::little-32, "WEBPVP8X", 10::little-32, 0::32, 99::little-24, 49::little-24>>

    webp_l = <<"RIFF", 0::little-32, "WEBPVP8L", 5::little-32, 0x2F, 0x0C0027::little-32>>

    assert %{content_type: "image/png", width: 640, height: 480} =
             describe_bytes(dir, png, "application/octet-stream")

    assert %{content_type: "image/gif", width: 10, height: 20} = describe_bytes(dir, gif, nil)

    assert %{content_type: "image/jpeg", width: 400, height: 300} =
             describe_bytes(dir, jpeg, "image/jpeg")

    assert %{content_type: "image/webp", width: 100, height: 50} = describe_bytes(dir, webp_x, "")
    assert %{content_type: "image/webp", width: 40, height: 49} = describe_bytes(dir, webp_l, "")
  end

  @png <<0x89, "PNG\r\n", 0x1A, "\n", 13::32, "IHDR", 2::32, 3::32, 8, 6, 0, 0, 0>>

  test "active and unknown claims become application/octet-stream", %{dir: dir} do
    for {bytes, claim} <- [
          {"<html><script>alert(1)</script></html>", "text/html"},
          {"<html><script>alert(1)</script></html>", "TEXT/HTML; charset=utf-8"},
          {"<html xmlns=\"http://www.w3.org/1999/xhtml\"/>", "application/xhtml+xml"},
          {"alert(1)", "text/javascript"},
          {"alert(1)", "application/javascript"},
          {"<svg xmlns=\"http://www.w3.org/2000/svg\" onload=\"alert(1)\"/>", "image/svg+xml"},
          {"<svg/>", "image/png"},
          {"<?xml version=\"1.0\"?><x/>", "text/xml"},
          {"a,b", "text/csv"},
          {"anything", "application/x-custom"},
          {"", nil}
        ] do
      assert %{content_type: "application/octet-stream", width: nil} =
               describe_bytes(dir, bytes, claim),
             "#{inspect(claim)} was kept"
    end
  end

  test "a PDF is proven by its bytes", %{dir: dir} do
    assert %{content_type: "application/pdf", bytes: 8} =
             describe_bytes(dir, "%PDF-1.7", "application/octet-stream")

    assert %{content_type: "application/octet-stream"} =
             describe_bytes(dir, "not a pdf", "application/pdf")
  end

  test "a renamed PNG is a PNG, whatever the claim", %{dir: dir} do
    for claim <- ["text/html", "image/svg+xml", "application/pdf", nil] do
      assert %{content_type: "image/png", width: 2, height: 3} = describe_bytes(dir, @png, claim)
    end
  end

  test "text/plain needs the claim and valid UTF-8 with no NUL", %{dir: dir} do
    assert %{content_type: "text/plain"} = describe_bytes(dir, "héllo", "text/plain")

    assert %{content_type: "text/plain"} =
             describe_bytes(dir, "héllo", "text/plain; charset=utf-8")

    assert %{content_type: "application/octet-stream"} = describe_bytes(dir, "héllo", nil)

    assert %{content_type: "application/octet-stream"} =
             describe_bytes(dir, <<"a", 0, "b">>, "text/plain")

    assert %{content_type: "application/octet-stream"} =
             describe_bytes(dir, <<0xFF, 0xFE>>, "text/plain")
  end

  test "a long text file may cut a character at the end of the head", %{dir: dir} do
    text = String.duplicate("a", 65_535) <> "é" <> "more"
    assert %{content_type: "text/plain"} = describe_bytes(dir, text, "text/plain")
  end

  test "ZIP and Office files by their signatures", %{dir: dir} do
    docx = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    zip = <<"PK", 3, 4, "rest">>
    ole = <<0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, "rest">>

    assert %{content_type: ^docx} = describe_bytes(dir, zip, docx)
    assert %{content_type: "application/zip"} = describe_bytes(dir, zip, "text/html")
    assert %{content_type: "application/msword"} = describe_bytes(dir, ole, "application/msword")
    assert %{content_type: "application/octet-stream"} = describe_bytes(dir, ole, "text/html")
    assert %{content_type: "application/octet-stream"} = describe_bytes(dir, "no", docx)
  end

  test "every checked type has an extension, and content_type/1 reverses it" do
    for type <- ["image/png", "application/pdf", "text/plain", "application/zip"] do
      assert type |> Attachments.extension() |> Attachments.content_type() == type
    end

    assert Attachments.content_type(".PNG") == "image/png"
    assert Attachments.content_type(".html") == "application/octet-stream"
  end

  test "describe/2 gives an error for a missing file" do
    assert {:error, :enoent} = Attachments.describe("/no/such/file", "text/plain")
  end

  test "node/2 builds a valid attachment" do
    node =
      Attachments.node(%{content_type: "image/png", bytes: 3, width: 1, height: 2},
        key: "k",
        url: "/k",
        name: " cat\u0007.png "
      )

    assert node.name == "cat.png"
    assert Attachment.validate(node) == :ok
  end

  test "clean_name/1 limits the length and never gives an empty name" do
    assert String.length(Attachments.clean_name(String.duplicate("é", 300))) == 200
    assert Attachments.clean_name("\u0000") == "file"
    assert Attachments.clean_name(<<0xFF, "a">>) == "a"
    assert Attachments.clean_name(nil) == "file"
    assert Attachments.clean_name("a\u200Eb\u2066c\u2069\uFEFF.pdf") == "abc.pdf"
  end
end
