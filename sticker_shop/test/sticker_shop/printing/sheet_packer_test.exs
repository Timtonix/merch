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

  test "estimate_pages/2 calculates page counts correctly" do
    assert SheetPacker.estimate_pages(0) == 0
    assert SheetPacker.estimate_pages(1) == 1
    assert SheetPacker.estimate_pages(12) == 1
    assert SheetPacker.estimate_pages(13) == 2
    assert SheetPacker.estimate_pages(24) == 2
    assert SheetPacker.estimate_pages(25) == 3
  end
end
