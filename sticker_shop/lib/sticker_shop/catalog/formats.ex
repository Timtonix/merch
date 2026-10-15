defmodule StickerShop.Catalog.Formats do
  @moduledoc """
  Définition des formats de stickers disponibles et calcul des prix unitaires.
  """

  @formats [
    %{
      id: "standard_6x6",
      label: "Standard",
      dimensions_label: "6×6 cm",
      width_mm: 60,
      height_mm: 60,
      fixed_price_cents: nil
    },
    %{
      id: "medium_10x10",
      label: "Moyen",
      dimensions_label: "10×10 cm",
      width_mm: 100,
      height_mm: 100,
      fixed_price_cents: nil
    },
    %{
      id: "large_14x14",
      label: "Grand",
      dimensions_label: "14×14 cm",
      width_mm: 140,
      height_mm: 140,
      fixed_price_cents: nil
    },
    %{
      id: "poster_a4",
      label: "Pleine Page A4",
      dimensions_label: "19×27 cm",
      width_mm: 190,
      height_mm: 270,
      fixed_price_cents: 250
    }
  ]

  @default_format_id "standard_6x6"

  def all, do: @formats

  def default_id, do: @default_format_id

  def get(format_id) when is_binary(format_id) do
    Enum.find(@formats, &(&1.id == format_id)) || get(@default_format_id)
  end

  def get(_), do: get(@default_format_id)

  @doc """
  Calcule le prix unitaire en centimes selon le prix de base du sticker et le format choisi.
  - Standard 6×6 cm : prix de base (ex: 20c ou 30c)
  - Moyen 10×10 cm : 50c (classique) / 70c (shiny) ou 2.5×
  - Grand 14×14 cm : 100c / 1€ (classique) / 130c (shiny) ou 5.0×
  - Pleine page A4 : 2,50 € (250 centimes)
  """
  def price_for(base_price_cents, format_id) when is_integer(base_price_cents) do
    case format_id do
      "poster_a4" ->
        250

      "large_14x14" ->
        cond do
          base_price_cents <= 20 -> 100
          base_price_cents <= 30 -> 130
          true -> round(base_price_cents * 5.0)
        end

      "medium_10x10" ->
        cond do
          base_price_cents <= 20 -> 50
          base_price_cents <= 30 -> 70
          true -> round(base_price_cents * 2.5)
        end

      _ ->
        base_price_cents
    end
  end
end
