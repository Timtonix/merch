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
      unit_price_cents: 20,
      image_path: "/images/stickers/phoenix.svg",
      width_mm: 60,
      height_mm: 60,
      category: "general"
    },
    %{
      name: "Beam",
      unit_price_cents: 20,
      image_path: "/images/stickers/beam.svg",
      width_mm: 60,
      height_mm: 60,
      category: "general"
    },
    %{
      name: "Hex (Shiny)",
      unit_price_cents: 30,
      image_path: "/images/stickers/hex.svg",
      width_mm: 60,
      height_mm: 60,
      category: "general"
    },
    %{
      name: "Atom Bicus",
      unit_price_cents: 30,
      image_path: "/images/stickers/atom.svg",
      width_mm: 60,
      height_mm: 60,
      category: "bicus"
    }
  ]

  Enum.each(stickers, fn attrs ->
    {:ok, _} = Catalog.create_sticker(attrs)
  end)
end
