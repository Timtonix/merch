defmodule StickerShop.Orders.OrderItem do
  @moduledoc """
  A line on an order: one sticker and its quantity, with the unit price
  frozen at checkout time.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "order_items" do
    field :quantity, :integer
    field :unit_price_cents, :integer
    field :format, :string, default: "standard_6x6"
    field :width_mm, :integer, default: 60
    field :height_mm, :integer, default: 60

    belongs_to :order, StickerShop.Orders.Order
    belongs_to :sticker, StickerShop.Catalog.Sticker

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(order_item, attrs) do
    order_item
    |> cast(attrs, [:quantity, :unit_price_cents, :sticker_id, :format, :width_mm, :height_mm])
    |> validate_required([
      :quantity,
      :unit_price_cents,
      :sticker_id,
      :format,
      :width_mm,
      :height_mm
    ])
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:unit_price_cents, greater_than: 0)
    |> assoc_constraint(:sticker)
    |> unique_constraint([:order_id, :sticker_id, :format])
  end
end
