defmodule KotobaTest.ErrorHTML do
  @moduledoc "Error pages for the test endpoint."

  def render(template, _assigns), do: Phoenix.Controller.status_message_from_template(template)
end

defmodule KotobaTest.Router do
  @moduledoc "The router of the test endpoint."
  use Phoenix.Router

  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:fetch_session)
  end

  scope "/" do
    pipe_through(:browser)
    live("/editor", KotobaTest.EditorLive)
  end
end

defmodule KotobaTest.Endpoint do
  @moduledoc "A Phoenix endpoint for the `Kotoba.Live` tests. It runs no server."
  use Phoenix.Endpoint, otp_app: :kotoba

  plug(Plug.Session, store: :cookie, key: "_kotoba_test", signing_salt: "kotoba-test")
  plug(KotobaTest.Router)
end
