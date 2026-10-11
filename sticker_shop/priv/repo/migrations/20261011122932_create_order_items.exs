defmodule StickerShop.Repo.Migrations.CreateOrderItems do
  use Ecto.Migration

  def change do
    create table(:order_items) do
      add :quantity, :integer, null: false
      add :unit_price_cents, :integer, null: false
      add :order_id, references(:orders, on_delete: :delete_all), null: false
      add :sticker_id, references(:stickers, on_delete: :restrict), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:order_items, [:order_id])
    create index(:order_items, [:sticker_id])
    create unique_index(:order_items, [:order_id, :sticker_id])
  end
end
