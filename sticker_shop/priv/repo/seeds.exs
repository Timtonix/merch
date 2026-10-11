# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs

alias StickerShop.Catalog
alias StickerShop.Repo
alias StickerShop.Catalog.Sticker

if Repo.aggregate(Sticker, :count) == 0 do
  stickers = [
    %{
      name: "Phoenix",
      unit_price_cents: 350,
      image_path: "/images/stickers/phoenix.svg",
      width_mm: 60,
      height_mm: 60
    },
    %{
      name: "Beam",
      unit_price_cents: 350,
      image_path: "/images/stickers/beam.svg",
      width_mm: 60,
      height_mm: 60
    },
    %{
      name: "Hex",
      unit_price_cents: 400,
      image_path: "/images/stickers/hex.svg",
      width_mm: 60,
      height_mm: 60
    },
    %{
      name: "Atom",
      unit_price_cents: 300,
      image_path: "/images/stickers/atom.svg",
      width_mm: 60,
      height_mm: 60
    }
  ]

  Enum.each(stickers, fn attrs ->
    {:ok, _} = Catalog.create_sticker(attrs)
  end)
end
