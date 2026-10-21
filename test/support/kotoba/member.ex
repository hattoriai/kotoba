if Code.ensure_loaded?(Issho) do
  defmodule KotobaTest.Member do
    @moduledoc false
    # A user of the app's own, whose key in every room is the app's.
    defstruct [:id, :name]

    defimpl Issho.Actor do
      def key(member), do: "member:#{member.id}"
      def display(member), do: %{name: member.name}
    end
  end
end
