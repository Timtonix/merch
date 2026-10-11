defmodule StickerShop.Repo.Migrations.CreateOrders do
  use Ecto.Migration

  def change do
    create table(:orders) do
      add :customer_name, :string, null: false
      add :customer_email, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :total_cents, :integer, null: false, default: 0
      add :notes, :string

      timestamps(type: :utc_datetime)
    end

    create index(:orders, [:status])
    create index(:orders, [:inserted_at])
  end
end
