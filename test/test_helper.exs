{:ok, _pid} = Phoenix.PubSub.Supervisor.start_link(name: KotobaTest.PubSub)
{:ok, _pid} = KotobaTest.Endpoint.start_link()
ExUnit.start()
