{:ok, _pid} = Phoenix.PubSub.Supervisor.start_link(name: KotobaTest.PubSub)
{:ok, _pid} = KotobaTest.Endpoint.start_link()
# The :build tests run `mix kotoba.build` (npm and network on the first
# run) and `mix hex.build`: `mix test --include build`.
ExUnit.start(exclude: [:build])
