defmodule StickerShop.Catalog do
  @moduledoc """
  Catalog of merch stickers and categories shown in the public shop.
  """

  import Ecto.Query, warn: false
  alias StickerShop.Repo
  alias StickerShop.Catalog.{Category, Sticker}

  # --- Stickers ---

  def list_stickers do
    Repo.all(from s in Sticker, order_by: [asc: s.name])
  end

  def list_active_stickers(opts \\ []) do
    base = from s in Sticker, where: s.active == true, order_by: [asc: s.name]

    Enum.reduce(opts, base, fn
      {:category, category}, query when is_binary(category) and category != "all" ->
        from s in query, where: s.category == ^category

      _, query ->
        query
    end)
    |> Repo.all()
  end

  def get_sticker!(id), do: Repo.get!(Sticker, id)

  def get_sticker(id), do: Repo.get(Sticker, id)

  def create_sticker(attrs) do
    %Sticker{}
    |> Sticker.changeset(attrs)
    |> Repo.insert()
  end

  def update_sticker(%Sticker{} = sticker, attrs) do
    sticker
    |> Sticker.changeset(attrs)
    |> Repo.update()
  end

  def change_sticker(%Sticker{} = sticker, attrs \\ %{}) do
    Sticker.changeset(sticker, attrs)
  end

  def toggle_sticker_active(%Sticker{} = sticker) do
    update_sticker(sticker, %{active: !sticker.active})
  end

  def delete_sticker(%Sticker{} = sticker) do
    sticker
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.no_assoc_constraint(:order_items,
      message: "des commandes sont associées à ce sticker"
    )
    |> Repo.delete()
  end

  # --- Categories ---

  @doc """
  Lists all categories ordered with `"general"` first, `"bicus"` second,
  and all other categories alphabetically by name.
  Ensures default categories exist if the table is empty.
  """
  def list_categories do
    categories = Repo.all(from c in Category, order_by: [asc: c.name])

    categories =
      if Enum.any?(categories, &(&1.slug == "general")) do
        categories
      else
        ensure_default_categories()
        Repo.all(from c in Category, order_by: [asc: c.name])
      end

    Enum.sort_by(categories, fn cat ->
      case cat.slug do
        "general" -> {0, cat.name}
        "bicus" -> {1, cat.name}
        _ -> {2, String.downcase(cat.name)}
      end
    end)
  end

  @doc """
  Ensures `"general"` and `"bicus"` default categories exist in the database.
  """
  def ensure_default_categories do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert_all(
      Category,
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
      on_conflict: :nothing,
      conflict_target: :slug
    )

    :ok
  end

  def get_category!(id), do: Repo.get!(Category, id)

  def get_category(id), do: Repo.get(Category, id)

  def get_category_by_slug(slug) when is_binary(slug) do
    Repo.get_by(Category, slug: slug)
  end

  def create_category(attrs) do
    %Category{}
    |> Category.changeset(attrs)
    |> Repo.insert()
  end

  def update_category(%Category{} = category, attrs) do
    category
    |> Category.changeset(attrs)
    |> Repo.update()
  end

  def change_category(%Category{} = category, attrs \\ %{}) do
    Category.changeset(category, attrs)
  end

  @doc """
  Deletes a category and reassigns any stickers belonging to it back to `"general"`.
  The default `"general"` category cannot be deleted.
  """
  def delete_category(%Category{slug: "general"}) do
    {:error, :cannot_delete_default}
  end

  def delete_category(%Category{} = category) do
    Repo.transaction(fn ->
      from(s in Sticker, where: s.category == ^category.slug)
      |> Repo.update_all(
        set: [category: "general", updated_at: DateTime.utc_now() |> DateTime.truncate(:second)]
      )

      case Repo.delete(category) do
        {:ok, deleted} -> deleted
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  # --- Thumbnails & Formatting ---

  @doc """
  Returns the lightweight WebP thumbnail URL path for a given `%Sticker{}` or `image_path`
  ONLY if the thumbnail file actually exists on disk and is non-empty.
  Otherwise, falls back to the original `image_path` so broken/404 links never happen.
  """
  def thumbnail_path(%Sticker{image_path: image_path}), do: thumbnail_path(image_path)

  def thumbnail_path(image_path) when is_binary(image_path) do
    ext = Path.extname(image_path) |> String.downcase()

    if String.starts_with?(image_path, "/uploads/stickers/") and ext in ~w(.png .jpg .jpeg .webp) do
      thumb_name = StickerShop.Catalog.ImageOptimizer.thumbnail_filename(image_path)

      if StickerShop.Catalog.ImageOptimizer.thumbnail_exists?(thumb_name) do
        "/uploads/stickers/#{thumb_name}"
      else
        image_path
      end
    else
      image_path
    end
  end

  def thumbnail_path(_), do: ""

  @doc """
  Formats an integer amount in euro cents, e.g. `350` becomes `"3,50 €"`.
  """
  def format_price_cents(cents) when is_integer(cents) do
    sign = if cents < 0, do: "-", else: ""
    cents = abs(cents)
    euros = div(cents, 100)
    remainder = cents |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{sign}#{euros},#{remainder} €"
  end
end
