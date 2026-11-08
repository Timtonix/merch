defmodule StickerShop.Repo.Migrations.CreateCategories do
  use Ecto.Migration

  def up do
    create table(:categories) do
      add :slug, :string, null: false
      add :name, :string, null: false
      add :password, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:categories, [:slug])

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    execute(fn ->
      repo().insert_all(
        "categories",
        [
          %{
            slug: "general",
            name: "Général",
            password: nil,
            inserted_at: now,
            updated_at: now
          },
          %{
            slug: "bicus",
            name: "Bicus",
            password: System.get_env("BICUS_PASSWORD") || "bicus123",
            inserted_at: now,
            updated_at: now
          }
        ],
        on_conflict: :nothing
      )
    end)
  end

  def down do
    drop table(:categories)
  end
end
