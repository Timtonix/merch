defmodule StickerShop.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      StickerShopWeb.Telemetry,
      StickerShop.Repo,
      {DNSCluster, query: Application.get_env(:sticker_shop, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: StickerShop.PubSub},
      # Start a worker by calling: StickerShop.Worker.start_link(arg)
      # {StickerShop.Worker, arg},
      # Start to serve requests, typically the last entry
      StickerShopWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: StickerShop.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    StickerShopWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
