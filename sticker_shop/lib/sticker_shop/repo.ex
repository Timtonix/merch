defmodule StickerShop.Repo do
  use Ecto.Repo,
    otp_app: :sticker_shop,
    adapter: Ecto.Adapters.Postgres
end
