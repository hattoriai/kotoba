defmodule Kotoba.SanitizerTest do
  use ExUnit.Case, async: false

  alias Kotoba.Nodes
  alias Kotoba.Sanitizer

  doctest Kotoba.Sanitizer

  describe "link_url/2" do
    test "accepts http, https and mailto URLs, in any case" do
      for url <- ["http://a.b", "https://a.b/c?d=e#f", "mailto:a@b.c", "HTTPS://A.B"] do
        assert Sanitizer.link_url(url) == url
      end
    end

    test "accepts relative URLs" do
      for url <- [
            "/a",
            "a/b",
            "../c",
            "#top",
            "?q=1",
            "//a.b/c",
            "/a:b"
          ] do
        assert Sanitizer.link_url(url) == url
      end
    end

    test "trims the URL" do
      assert Sanitizer.link_url("  https://a.b  ") == "https://a.b"
    end

    test "refuses other schemes" do
      for url <- [
            "javascript:alert(1)",
            "JAVASCRIPT:alert(1)",
            " javascript:alert(1)",
            "vbscript:x",
            "data:text/html;base64,PHNjcmlwdD4=",
            "file:///etc/passwd",
            "tel:+100"
          ] do
        assert Sanitizer.link_url(url) == nil, url
      end
    end

    test "refuses control characters, empty and long URLs, and values that are not strings" do
      for url <- [
            "java\tscript:alert(1)",
            "java\nscript:x",
            "/a\u0000b",
            "/a\u0085b",
            "",
            "   ",
            nil,
            1
          ] do
        assert Sanitizer.link_url(url) == nil
      end

      assert Sanitizer.link_url("/" <> String.duplicate("a", 2047))
      refute Sanitizer.link_url("/" <> String.duplicate("a", 2048))
    end

    test "reads the schemes from the options, then from the config" do
      assert Sanitizer.link_url("tel:+100", schemes: ["TEL"]) == "tel:+100"
      refute Sanitizer.link_url("https://a.b", schemes: ["tel"])

      Application.put_env(:kotoba, :allowed_link_schemes, ~w(https tel))
      on_exit(fn -> Application.delete_env(:kotoba, :allowed_link_schemes) end)

      assert Sanitizer.link_url("tel:+100") == "tel:+100"
      refute Sanitizer.link_url("mailto:a@b.c")
    end
  end

  describe "policy/1" do
    test "the two policies" do
      assert Sanitizer.policy(:default) == %{name: :default, links: true, attachments: true}
      assert Sanitizer.policy(:untrusted) == %{name: :untrusted, links: false, attachments: false}
    end

    test "returns a policy map with no change" do
      policy = Sanitizer.policy(:untrusted)
      assert Sanitizer.policy(policy) == policy
    end

    test "raises for an unknown policy" do
      assert_raise ArgumentError, fn -> Sanitizer.policy(:none) end
    end
  end

  describe "check/3" do
    test "accepts a valid node in a valid parent" do
      item = %Nodes.ListItem{children: [%Nodes.Text{text: "a"}]}
      assert :ok = Sanitizer.check(item, %Nodes.List{list_type: "bullet", tag: "ul"})
      assert :ok = Sanitizer.check(%Nodes.Root{}, nil)
      assert :ok = Sanitizer.check(%Nodes.Unknown{type: "x", raw: %{}}, %Nodes.Code{})
    end

    test "refuses a node that is not valid" do
      assert {:error, "text is required"} = Sanitizer.check(%Nodes.Text{}, nil)
    end

    test "bounds the labels and the URLs" do
      mention = %Nodes.Mention{kind: "p", id: "1", label: String.duplicate("a", 200)}
      assert :ok = Sanitizer.check(mention, nil)

      assert {:error, "label is longer than 200 characters"} =
               Sanitizer.check(%{mention | label: mention.label <> "a"}, nil)

      attachment = %Nodes.Attachment{
        key: String.duplicate("k", 2049),
        url: "/a",
        name: "a",
        content_type: "text/plain",
        bytes: 1
      }

      assert {:error, "key is longer than 2048 characters"} = Sanitizer.check(attachment, nil)
    end

    test "the text of a text node is not bounded" do
      assert :ok = Sanitizer.check(%Nodes.Text{text: String.duplicate("a", 5000) <> "\t"}, nil)
    end

    test "refuses an attachment with a URL that is not safe" do
      attachment = %Nodes.Attachment{
        key: "k",
        url: "javascript:x",
        name: "a",
        content_type: "text/plain",
        bytes: 1
      }

      assert {:error, "url is not a safe URL"} = Sanitizer.check(attachment, nil)
    end

    test "checks the nesting" do
      list = %Nodes.List{list_type: "bullet", tag: "ul"}
      text = %Nodes.Text{text: "a"}

      assert {:error, "a list holds only list items"} = Sanitizer.check(text, list)
      assert {:error, _reason} = Sanitizer.check(%Nodes.Paragraph{}, %Nodes.Code{})
      assert :ok = Sanitizer.check(%Nodes.LineBreak{}, %Nodes.Code{})
      assert {:error, _reason} = Sanitizer.check(%Nodes.Quote{}, %Nodes.Paragraph{})

      assert {:error, "a link holds no other link"} =
               Sanitizer.check(%Nodes.Link{url: "/a"}, %Nodes.AutoLink{url: "/b"})
    end
  end
end
