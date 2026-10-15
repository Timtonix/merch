defmodule StickerShop.Printing.SheetPackerTest do
  use ExUnit.Case, async: true

  alias StickerShop.Catalog.Sticker
  alias StickerShop.Orders.{Order, OrderItem}
  alias StickerShop.Printing.SheetPacker

  setup do
    sticker_a = %Sticker{
      id: 1,
      name: "Phoenix",
      width_mm: 60,
      height_mm: 60,
      image_path: "/images/stickers/phoenix.svg"
    }

    sticker_b = %Sticker{
      id: 2,
      name: "Hex",
      width_mm: 60,
      height_mm: 60,
      image_path: "/images/stickers/hex.svg"
    }

    %{sticker_a: sticker_a, sticker_b: sticker_b}
  end

  test "pack_orders/2 groups multiple orders on a single A4 sheet without wasted space", %{
    sticker_a: sticker_a,
    sticker_b: sticker_b
  } do
    # Order 1: 3 stickers A
    order1 = %Order{
      id: 101,
      customer_name: "Alice",
      order_items: [
        %OrderItem{quantity: 3, sticker: sticker_a}
      ]
    }

    # Order 2: 9 stickers B
    order2 = %Order{
      id: 102,
      customer_name: "Bob",
      order_items: [
        %OrderItem{quantity: 9, sticker: sticker_b}
      ]
    }

    packed = SheetPacker.pack_orders([order1, order2])

    assert packed.total_items == 12
    assert packed.total_pages == 1
    assert length(packed.pages) == 1

    [page1] = packed.pages
    assert page1.items_count == 12

    # Check order badges and positions
    order1_items = Enum.filter(page1.items, &(&1.order_id == 101))
    order2_items = Enum.filter(page1.items, &(&1.order_id == 102))

    assert length(order1_items) == 3
    assert length(order2_items) == 9

    # Check that positions are strictly spaced and within A4 bounds
    for item <- page1.items do
      assert item.x_mm >= packed.margin_x_mm
      assert item.x_mm + item.width_mm <= packed.page_width_mm
      assert item.y_mm >= packed.margin_y_mm
      assert item.y_mm + item.height_mm <= packed.page_height_mm
    end
  end

  test "pack_items/2 creates multiple pages when quantity exceeds 12 slots" do
    items =
      for i <- 1..15 do
        %{
          order_id: i,
          customer_name: "Client #{i}",
          sticker: %Sticker{id: i, name: "Sticker #{i}", width_mm: 60, height_mm: 60}
        }
      end

    packed = SheetPacker.pack_items(items)

    assert packed.total_items == 15
    assert packed.total_pages == 2
    assert length(packed.pages) == 2

    [page1, page2] = packed.pages
    assert page1.page_number == 1
    assert page1.items_count == 12

    assert page2.page_number == 2
    assert page2.items_count == 3
  end

  test "pack_orders/2 allocates a dedicated page for poster_a4 format", %{sticker_a: sticker_a} do
    order = %Order{
      id: 201,
      customer_name: "Charlie",
      order_items: [
        %OrderItem{
          quantity: 2,
          sticker: sticker_a,
          format: "poster_a4",
          width_mm: 190,
          height_mm: 270
        }
      ]
    }

    packed = SheetPacker.pack_orders([order])

    assert packed.total_items == 2
    assert packed.total_pages == 2
    assert length(packed.pages) == 2

    for page <- packed.pages do
      assert page.layout_type == :poster_a4
      assert page.items_count == 1
      [item] = page.items
      assert item.width_mm == 190.0
      assert item.height_mm == 270.0
      assert item.format == "poster_a4"
    end
  end

  test "pack_orders/2 packs large 14x14 with up to 8 standard 6x6 stickers on the same page", %{
    sticker_a: sticker_a,
    sticker_b: sticker_b
  } do
    # 1 grand 14x14 + 10 standards 6x6
    order = %Order{
      id: 202,
      customer_name: "Dana",
      order_items: [
        %OrderItem{
          quantity: 1,
          sticker: sticker_a,
          format: "large_14x14",
          width_mm: 140,
          height_mm: 140
        },
        %OrderItem{
          quantity: 10,
          sticker: sticker_b,
          format: "standard_6x6",
          width_mm: 60,
          height_mm: 60
        }
      ]
    }

    packed = SheetPacker.pack_orders([order])

    assert packed.total_items == 11
    assert packed.total_pages == 2

    [page1, page2] = packed.pages

    # Page 1 : 1 grand 14x14 + 8 standards 6x6 = 9 items
    assert page1.layout_type == :mixed_large
    assert page1.items_count == 9

    large_item = Enum.find(page1.items, &(&1.format == "large_14x14"))
    assert large_item.width_mm == 140.0
    assert large_item.height_mm == 140.0

    standard_items_p1 = Enum.filter(page1.items, &(&1.format == "standard_6x6"))
    assert length(standard_items_p1) == 8

    # Page 2 : les 2 standards restants
    assert page2.layout_type == :standard_6x6
    assert page2.items_count == 2
  end

  test "pack_orders/2 packs medium 10x10 stickers in a 2x2 grid (up to 4 per page)", %{
    sticker_a: sticker_a
  } do
    order = %Order{
      id: 203,
      customer_name: "Evan",
      order_items: [
        %OrderItem{
          quantity: 5,
          sticker: sticker_a,
          format: "medium_10x10",
          width_mm: 100,
          height_mm: 100
        }
      ]
    }

    packed = SheetPacker.pack_orders([order])

    assert packed.total_items == 5
    assert packed.total_pages == 2

    [page1, page2] = packed.pages
    assert page1.layout_type == :medium_10x10
    assert page1.items_count == 4
    assert page2.layout_type == :medium_10x10
    assert page2.items_count == 1
  end

  test "estimate_pages/2 calculates page counts correctly" do
    assert SheetPacker.estimate_pages(0) == 0
    assert SheetPacker.estimate_pages(1) == 1
    assert SheetPacker.estimate_pages(12) == 1
    assert SheetPacker.estimate_pages(13) == 2
    assert SheetPacker.estimate_pages(24) == 2
    assert SheetPacker.estimate_pages(25) == 3
  end
end
