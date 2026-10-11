defmodule StickerShop.OrdersTest do
  use StickerShop.DataCase, async: true

  alias StickerShop.Catalog
  alias StickerShop.Orders
  alias StickerShop.Orders.Order

  describe "orders" do
    setup do
      {:ok, sticker} =
        Catalog.create_sticker(%{
          name: "Phoenix",
          unit_price_cents: 200,
          image_path: "priv/stickers/phoenix.png",
          width_mm: 40,
          height_mm: 40
        })

      {:ok, inactive} =
        Catalog.create_sticker(%{
          name: "Retired",
          unit_price_cents: 100,
          image_path: "priv/stickers/retired.png",
          width_mm: 40,
          height_mm: 40,
          active: false
        })

      %{sticker: sticker, inactive: inactive}
    end

    test "create_order/2 snapshots prices and computes the total", %{sticker: sticker} do
      attrs = %{customer_name: "Tim", customer_email: "tim@example.com"}
      items = [%{sticker_id: sticker.id, quantity: 3}]

      assert {:ok, %Order{} = order} = Orders.create_order(attrs, items)
      assert order.status == :pending
      assert order.total_cents == 600
      assert [item] = order.order_items
      assert item.quantity == 3
      assert item.unit_price_cents == 200
      assert item.sticker.id == sticker.id
    end

    test "create_order/2 ignores client-supplied prices", %{sticker: sticker} do
      attrs = %{customer_name: "Tim", customer_email: "tim@example.com"}
      items = [%{sticker_id: sticker.id, quantity: 2, unit_price_cents: 1}]

      assert {:ok, order} = Orders.create_order(attrs, items)
      assert order.total_cents == 400
      assert hd(order.order_items).unit_price_cents == 200
    end

    test "create_order/2 rejects an empty cart" do
      attrs = %{customer_name: "Tim", customer_email: "tim@example.com"}
      assert {:error, :empty_cart} = Orders.create_order(attrs, [])
    end

    test "create_order/2 rejects inactive stickers", %{inactive: inactive} do
      attrs = %{customer_name: "Tim", customer_email: "tim@example.com"}
      items = [%{sticker_id: inactive.id, quantity: 1}]

      assert {:error, :sticker_unavailable} = Orders.create_order(attrs, items)
    end

    test "create_order/2 rejects invalid customer data", %{sticker: sticker} do
      attrs = %{customer_name: "Tim", customer_email: "not-an-email"}
      items = [%{sticker_id: sticker.id, quantity: 1}]

      assert {:error, changeset} = Orders.create_order(attrs, items)
      assert "must be a valid email" in errors_on(changeset).customer_email
    end

    test "update_order_status/2 moves an order through the print workflow", %{sticker: sticker} do
      {:ok, order} =
        Orders.create_order(
          %{customer_name: "Tim", customer_email: "tim@example.com"},
          [%{sticker_id: sticker.id, quantity: 1}]
        )

      assert {:ok, updated} = Orders.update_order_status(order, :printed)
      assert updated.status == :printed
    end

    test "batch operations: list_pending_orders, count_stickers_in_orders, mark_orders_as_printed",
         %{sticker: sticker} do
      {:ok, order1} =
        Orders.create_order(
          %{customer_name: "Alice", customer_email: "alice@example.com"},
          [%{sticker_id: sticker.id, quantity: 3}]
        )

      {:ok, order2} =
        Orders.create_order(
          %{customer_name: "Bob", customer_email: "bob@example.com"},
          [%{sticker_id: sticker.id, quantity: 4}]
        )

      pending = Orders.list_pending_orders()
      assert length(pending) == 2
      assert Orders.total_stickers_count(order1) == 3
      assert Orders.count_stickers_in_orders([order1, order2]) == 7

      {2, _} = Orders.mark_orders_as_printed([order1.id, order2.id])
      assert Orders.list_pending_orders() == []
      assert Orders.get_order!(order1.id).status == :printed
      assert Orders.get_order!(order2.id).status == :printed
    end
  end
end
