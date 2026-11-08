defmodule StickerShop.OrdersTest do
  use StickerShop.DataCase, async: true

  import Swoosh.TestAssertions

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
      assert item.format == "standard_6x6"
      assert item.width_mm == 60
      assert item.height_mm == 60
      assert item.sticker.id == sticker.id
    end

    test "create_order/2 computes prices and dimensions for custom formats", %{sticker: sticker} do
      attrs = %{customer_name: "Tim", customer_email: "tim@example.com"}

      items = [
        %{sticker_id: sticker.id, quantity: 1, format: "poster_a4"},
        %{sticker_id: sticker.id, quantity: 2, format: "medium_10x10"}
      ]

      assert {:ok, %Order{} = order} = Orders.create_order(attrs, items)
      # poster_a4 = 250c, medium_10x10 for 200c base = 500c * 2 = 1000c. Total = 1250c
      assert order.total_cents == 1250
      assert length(order.order_items) == 2

      poster = Enum.find(order.order_items, &(&1.format == "poster_a4"))
      assert poster.quantity == 1
      assert poster.unit_price_cents == 250
      assert poster.width_mm == 190
      assert poster.height_mm == 270

      medium = Enum.find(order.order_items, &(&1.format == "medium_10x10"))
      assert medium.quantity == 2
      assert medium.unit_price_cents == 500
      assert medium.width_mm == 100
      assert medium.height_mm == 100
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

    test "update_order_status/2 moves an order through the print workflow and sends printed email",
         %{sticker: sticker} do
      {:ok, order} =
        Orders.create_order(
          %{customer_name: "Tim", customer_email: "tim@example.com"},
          [%{sticker_id: sticker.id, quantity: 1}]
        )

      assert_email_sent(fn email ->
        assert email.subject =~ "Récapitulatif de ta commande ##{order.id}"
        assert email.html_body =~ "Espèces (Cash)"
        assert email.html_body =~ "Wero"
        assert email.html_body =~ "Virement bancaire (RIB)"
      end)

      assert {:ok, updated} = Orders.update_order_status(order, :printed)
      assert updated.status == :printed

      assert_email_sent(fn email ->
        assert email.subject =~ "Tes stickers sont imprimés ! (Commande ##{order.id})"
        assert email.html_body =~ "Phoenix"
      end)
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

      assert_email_sent(subject: "Récapitulatif de ta commande ##{order1.id} · Stickers")
      assert_email_sent(subject: "Récapitulatif de ta commande ##{order2.id} · Stickers")
      assert_email_sent(subject: "Tes stickers sont imprimés ! (Commande ##{order1.id})")
      assert_email_sent(subject: "Tes stickers sont imprimés ! (Commande ##{order2.id})")
    end
  end
end
