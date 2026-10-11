defmodule StickerShopWeb.Plugs.AdminAuth do
  @moduledoc """
  Plug d'authentification HTTP Basic Auth pour l'espace administration.
  """

  def init(opts), do: opts

  def call(conn, _opts) do
    username = System.get_env("ADMIN_USERNAME") || "admin"
    password = System.get_env("ADMIN_PASSWORD") || "stickers123"

    Plug.BasicAuth.basic_auth(conn, username: username, password: password)
  end
end
