defmodule StickerShop.Catalog do
  @moduledoc """
  Catalog of merch stickers shown in the public shop.
  """

  import Ecto.Query, warn: false
  alias StickerShop.Repo
  alias StickerShop.Catalog.Sticker

  def list_stickers do
    Repo.all(from s in Sticker, order_by: [asc: s.name])
  end

  def list_active_stickers do
    Repo.all(from s in Sticker, where: s.active == true, order_by: [asc: s.name])
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
    Repo.delete(sticker)
  end

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
