defmodule StickerShop.Catalog.Sticker do
  @moduledoc """
  A merch sticker available in the shop, with print dimensions used later
  for compact PDF imposition.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "stickers" do
    field :name, :string
    field :unit_price_cents, :integer
    field :image_path, :string
    field :width_mm, :integer
    field :height_mm, :integer
    field :category, :string, default: "general"
    field :active, :boolean, default: true

    has_many :order_items, StickerShop.Orders.OrderItem

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(sticker, attrs) do
    sticker
    |> cast(attrs, [
      :name,
      :unit_price_cents,
      :image_path,
      :width_mm,
      :height_mm,
      :category,
      :active
    ])
    |> validate_required([:name, :unit_price_cents, :image_path, :width_mm, :height_mm])
    |> validate_length(:name, min: 1, max: 120)
    |> validate_length(:category, min: 1, max: 60)
    |> validate_number(:unit_price_cents, greater_than: 0)
    |> validate_number(:width_mm, greater_than: 0)
    |> validate_number(:height_mm, greater_than: 0)
    |> validate_length(:image_path, min: 1, max: 500)
  end
end
