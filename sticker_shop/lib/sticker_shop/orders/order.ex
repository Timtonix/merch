defmodule StickerShop.Orders.Order do
  @moduledoc """
  A customer merch order. The cart is persisted as `order_items` with
  snapshotted unit prices so later catalog changes do not rewrite history.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @statuses [:pending, :confirmed, :printed, :fulfilled, :cancelled]

  schema "orders" do
    field :customer_name, :string
    field :customer_email, :string
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :total_cents, :integer, default: 0
    field :notes, :string

    has_many :order_items, StickerShop.Orders.OrderItem

    timestamps(type: :utc_datetime)
  end

  def statuses, do: @statuses

  @doc false
  def changeset(order, attrs) do
    order
    |> cast(attrs, [:customer_name, :customer_email, :status, :notes])
    |> validate_required([:customer_name, :customer_email])
    |> validate_length(:customer_name, min: 1, max: 120)
    |> validate_format(:customer_email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email")
    |> validate_inclusion(:status, @statuses)
    |> validate_length(:notes, max: 1000)
  end
end
