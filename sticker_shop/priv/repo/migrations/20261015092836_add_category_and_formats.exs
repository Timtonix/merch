defmodule StickerShop.Repo.Migrations.AddCategoryAndFormats do
  use Ecto.Migration

  def change do
    alter table(:stickers) do
      add :category, :string, default: "general", null: false
    end

    create index(:stickers, [:category])

    alter table(:order_items) do
      add :format, :string, default: "standard_6x6", null: false
      add :width_mm, :integer, default: 60, null: false
      add :height_mm, :integer, default: 60, null: false
    end

    drop_if_exists unique_index(:order_items, [:order_id, :sticker_id])
    create unique_index(:order_items, [:order_id, :sticker_id, :format])
  end
end
