defmodule StickerShop.Printing.SheetPacker do
  @moduledoc """
  Algorithme d'imposition pour regrouper les stickers de plusieurs commandes
  sur des planches A4 standards (210 × 297 mm) avec marges de sécurité,
  espacement inter-stickers pour la découpe, repères et étiquetage de commande.
  """

  @default_page_width_mm 210.0
  @default_page_height_mm 297.0
  @default_cols 3
  @default_rows 4
  @default_spacing_mm 3.0
  @default_sticker_size_mm 60.0

  @doc """
  Prend une liste de commandes (avec `order_items` et leurs `stickers` préchargés)
  et retourne la structure des pages d'imposition A4 prêtes pour l'impression.
  """
  def pack_orders(orders, opts \\ []) when is_list(orders) do
    flattened_items =
      orders
      |> Enum.flat_map(fn order ->
        Enum.flat_map(order.order_items, fn item ->
          for _ <- 1..item.quantity do
            %{
              order_id: order.id,
              customer_name: order.customer_name,
              sticker: item.sticker
            }
          end
        end)
      end)

    pack_items(flattened_items, opts)
  end

  @doc """
  Prend une liste d'éléments individuels démultipliés et les répartit en pages A4.
  """
  def pack_items(items, opts \\ []) when is_list(items) do
    page_width_mm = Keyword.get(opts, :page_width_mm, @default_page_width_mm)
    page_height_mm = Keyword.get(opts, :page_height_mm, @default_page_height_mm)
    cols = Keyword.get(opts, :cols, @default_cols)
    rows = Keyword.get(opts, :rows, @default_rows)
    spacing_mm = Keyword.get(opts, :spacing_mm, @default_spacing_mm)
    slot_size_mm = Keyword.get(opts, :sticker_size_mm, @default_sticker_size_mm)

    capacity_per_page = cols * rows

    # Calcul des marges pour centrer la grille sur la feuille A4
    grid_width_mm = cols * slot_size_mm + (cols - 1) * spacing_mm
    grid_height_mm = rows * slot_size_mm + (rows - 1) * spacing_mm

    margin_x_mm = Float.round(max((page_width_mm - grid_width_mm) / 2.0, 0.0), 2)
    margin_y_mm = Float.round(max((page_height_mm - grid_height_mm) / 2.0, 0.0), 2)

    chunked_pages =
      if items == [] do
        []
      else
        items
        |> Enum.chunk_every(capacity_per_page)
      end

    total_pages = max(length(chunked_pages), 1)

    pages =
      chunked_pages
      |> Enum.with_index(1)
      |> Enum.map(fn {page_items, page_num} ->
        positioned_items =
          page_items
          |> Enum.with_index()
          |> Enum.map(fn {item, idx} ->
            col = rem(idx, cols)
            row = div(idx, cols)

            x_mm = Float.round(margin_x_mm + col * (slot_size_mm + spacing_mm), 2)
            y_mm = Float.round(margin_y_mm + row * (slot_size_mm + spacing_mm), 2)

            width_mm =
              if item.sticker && item.sticker.width_mm,
                do: item.sticker.width_mm * 1.0,
                else: slot_size_mm

            height_mm =
              if item.sticker && item.sticker.height_mm,
                do: item.sticker.height_mm * 1.0,
                else: slot_size_mm

            %{
              index: idx + 1,
              col: col,
              row: row,
              x_mm: x_mm,
              y_mm: y_mm,
              slot_size_mm: slot_size_mm,
              width_mm: width_mm,
              height_mm: height_mm,
              order_id: item.order_id,
              customer_name: item.customer_name,
              sticker: item.sticker
            }
          end)

        %{
          page_number: page_num,
          total_pages: total_pages,
          items: positioned_items,
          items_count: length(positioned_items)
        }
      end)

    %{
      page_width_mm: page_width_mm,
      page_height_mm: page_height_mm,
      cols: cols,
      rows: rows,
      capacity_per_page: capacity_per_page,
      spacing_mm: spacing_mm,
      margin_x_mm: margin_x_mm,
      margin_y_mm: margin_y_mm,
      total_items: length(items),
      total_pages: total_pages,
      pages: pages
    }
  end

  @doc """
  Estime le nombre de pages A4 nécessaires pour un nombre total de stickers.
  """
  def estimate_pages(total_stickers, capacity_per_page \\ @default_cols * @default_rows) do
    if total_stickers <= 0 do
      0
    else
      ceil(total_stickers / capacity_per_page)
    end
  end
end
