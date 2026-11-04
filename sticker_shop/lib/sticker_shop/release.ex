defmodule StickerShop.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :sticker_shop

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    seed()
  end

  def seed do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn _repo ->
          if StickerShop.Repo.aggregate(StickerShop.Catalog.Sticker, :count) == 0 do
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
              {:ok, _} = StickerShop.Catalog.create_sticker(attrs)
            end)
          end
        end)
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
