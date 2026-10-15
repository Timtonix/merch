defmodule StickerShop.Printing.SheetPacker do
  @moduledoc """
  Algorithme d'imposition adaptatif pour regrouper les stickers de plusieurs commandes
  sur des planches A4 standards (210 × 297 mm) avec marges de sécurité,
  espacement inter-stickers pour la découpe, repères et étiquetage de commande.

  Prend en charge :
  - Standard 6×6 cm (jusqu'à 12 par feuille A4)
  - Moyen 10×10 cm (jusqu'à 4 par feuille A4)
  - Grand 14×14 cm (1 grand sticker + jusqu'à 8 stickers 6×6 cm autour sur la même feuille)
  - Pleine page A4 19×27 cm (1 poster par feuille A4 dédiée)
  """

  alias StickerShop.Catalog.Formats

  @page_width_mm 210.0
  @page_height_mm 297.0
  @default_spacing_mm 3.0

  @doc """
  Prend une liste de commandes (avec `order_items` et leurs `stickers` préchargés)
  et retourne la structure des pages d'imposition A4 prêtes pour l'impression.
  """
  def pack_orders(orders, opts \\ []) when is_list(orders) do
    flattened_items =
      orders
      |> Enum.flat_map(fn order ->
        Enum.flat_map(order.order_items, fn item ->
          format_id = item.format || Formats.default_id()
          format = Formats.get(format_id)

          width_mm = item.width_mm || format.width_mm || 60
          height_mm = item.height_mm || format.height_mm || 60

          for _ <- 1..item.quantity do
            %{
              order_id: order.id,
              customer_name: order.customer_name,
              sticker: item.sticker,
              format: format_id,
              width_mm: width_mm * 1.0,
              height_mm: height_mm * 1.0
            }
          end
        end)
      end)

    pack_items(flattened_items, opts)
  end

  @doc """
  Prend une liste d'éléments individuels démultipliés et les répartit en pages A4.
  """
  def pack_items(items, _opts \\ []) when is_list(items) do
    if items == [] do
      %{
        page_width_mm: @page_width_mm,
        page_height_mm: @page_height_mm,
        total_items: 0,
        total_pages: 0,
        pages: []
      }
    else
      # 1. Partitionner les items par catégorie de format
      posters = Enum.filter(items, &(Map.get(&1, :format) == "poster_a4"))
      larges = Enum.filter(items, &(Map.get(&1, :format) == "large_14x14"))
      mediums = Enum.filter(items, &(Map.get(&1, :format) == "medium_10x10"))

      standards =
        Enum.reject(items, &(Map.get(&1, :format) in ~w(poster_a4 large_14x14 medium_10x10)))

      # 2. Construire les pages
      {pages_posters, _} = build_poster_pages(posters)
      {pages_larges, remaining_standards} = build_large_pages(larges, standards)
      {pages_mediums, _} = build_medium_pages(mediums)
      {pages_standards, _} = build_standard_pages(remaining_standards)

      all_pages = pages_posters ++ pages_larges ++ pages_mediums ++ pages_standards
      total_pages = max(length(all_pages), 1)

      # Re-numéroter les pages séquentiellement
      final_pages =
        all_pages
        |> Enum.with_index(1)
        |> Enum.map(fn {page, page_num} ->
          %{page | page_number: page_num, total_pages: total_pages}
        end)

      %{
        page_width_mm: @page_width_mm,
        page_height_mm: @page_height_mm,
        margin_x_mm: 12.0,
        margin_y_mm: 24.0,
        spacing_mm: @default_spacing_mm,
        total_items: length(items),
        total_pages: total_pages,
        pages: final_pages
      }
    end
  end

  # Pages pour posters A4 (1 par page centrée)
  defp build_poster_pages(posters) do
    pages =
      Enum.map(posters, fn item ->
        positioned_item =
          Map.merge(item, %{
            index: 1,
            x_mm: 10.0,
            y_mm: 13.5,
            width_mm: 190.0,
            height_mm: 270.0
          })

        %{
          page_number: 0,
          total_pages: 0,
          items: [positioned_item],
          items_count: 1,
          layout_type: :poster_a4
        }
      end)

    {pages, []}
  end

  # Pages pour grands stickers 14×14 cm + comblement avec stickers 6×6 cm
  defp build_large_pages([], standards), do: {[], standards}

  defp build_large_pages([large | rest_larges], standards) do
    # On peut caler jusqu'à 8 stickers 6×6 cm autour d'un grand 14×14 cm :
    # 2 à droite (x=149) + 6 en bas (2 rangées de 3 à y=153 et y=216)
    {absorbed, remaining_standards} = Enum.split(standards, 8)

    large_positioned =
      Map.merge(large, %{
        index: 1,
        x_mm: 6.0,
        y_mm: 10.0,
        width_mm: 140.0,
        height_mm: 140.0
      })

    # Coordonnées des 8 slots disponibles autour
    companion_slots = [
      %{x: 149.0, y: 10.0},
      %{x: 149.0, y: 73.0},
      %{x: 6.0, y: 153.0},
      %{x: 69.0, y: 153.0},
      %{x: 132.0, y: 153.0},
      %{x: 6.0, y: 216.0},
      %{x: 69.0, y: 216.0},
      %{x: 132.0, y: 216.0}
    ]

    companions_positioned =
      absorbed
      |> Enum.zip(companion_slots)
      |> Enum.with_index(2)
      |> Enum.map(fn {{item, slot}, idx} ->
        Map.merge(item, %{
          index: idx,
          x_mm: slot.x,
          y_mm: slot.y,
          width_mm: 60.0,
          height_mm: 60.0
        })
      end)

    all_items = [large_positioned | companions_positioned]

    page = %{
      page_number: 0,
      total_pages: 0,
      items: all_items,
      items_count: length(all_items),
      layout_type: :mixed_large
    }

    {rest_pages, final_standards} = build_large_pages(rest_larges, remaining_standards)
    {[page | rest_pages], final_standards}
  end

  # Pages pour moyens stickers 10×10 cm (grille 2×2, jusqu'à 4 par page)
  defp build_medium_pages([]), do: {[], []}

  defp build_medium_pages(mediums) do
    pages =
      mediums
      |> Enum.chunk_every(4)
      |> Enum.map(fn chunk ->
        positioned =
          chunk
          |> Enum.with_index()
          |> Enum.map(fn {item, idx} ->
            col = rem(idx, 2)
            row = div(idx, 2)

            x_mm = Float.round(3.5 + col * (100.0 + 3.0), 2)
            y_mm = Float.round(47.0 + row * (100.0 + 3.0), 2)

            Map.merge(item, %{
              index: idx + 1,
              x_mm: x_mm,
              y_mm: y_mm,
              width_mm: 100.0,
              height_mm: 100.0
            })
          end)

        %{
          page_number: 0,
          total_pages: 0,
          items: positioned,
          items_count: length(positioned),
          layout_type: :medium_10x10
        }
      end)

    {pages, []}
  end

  # Pages pour stickers standards 6×6 cm (grille 3×4, jusqu'à 12 par page)
  defp build_standard_pages([]), do: {[], []}

  defp build_standard_pages(standards) do
    cols = 3
    slot_size_mm = 60.0
    spacing_mm = 3.0
    margin_x_mm = 12.0
    margin_y_mm = 24.0

    pages =
      standards
      |> Enum.chunk_every(12)
      |> Enum.map(fn chunk ->
        positioned =
          chunk
          |> Enum.with_index()
          |> Enum.map(fn {item, idx} ->
            col = rem(idx, cols)
            row = div(idx, cols)

            x_mm = Float.round(margin_x_mm + col * (slot_size_mm + spacing_mm), 2)
            y_mm = Float.round(margin_y_mm + row * (slot_size_mm + spacing_mm), 2)

            Map.merge(item, %{
              index: idx + 1,
              x_mm: x_mm,
              y_mm: y_mm,
              width_mm: slot_size_mm,
              height_mm: slot_size_mm
            })
          end)

        %{
          page_number: 0,
          total_pages: 0,
          items: positioned,
          items_count: length(positioned),
          layout_type: :standard_6x6
        }
      end)

    {pages, []}
  end

  @doc """
  Estime le nombre de pages A4 nécessaires pour une liste de commandes.
  """
  def estimate_pages_for_orders(orders) when is_list(orders) do
    pack = pack_orders(orders)
    pack.total_pages
  end

  def estimate_pages(total_stickers, capacity_per_page \\ 12) do
    if total_stickers <= 0 do
      0
    else
      ceil(total_stickers / capacity_per_page)
    end
  end
end
