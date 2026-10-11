defmodule StickerShop.Repo.Migrations.CreateStickers do
  use Ecto.Migration

  def change do
    create table(:stickers) do
      add :name, :string, null: false
      add :unit_price_cents, :integer, null: false
      add :image_path, :string, null: false
      add :width_mm, :integer, null: false
      add :height_mm, :integer, null: false
      add :active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create index(:stickers, [:active])
  end
end
