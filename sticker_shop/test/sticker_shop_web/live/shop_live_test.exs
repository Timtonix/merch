defmodule StickerShopWeb.ShopLiveTest do
  use StickerShopWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StickerShop.Catalog
  alias StickerShop.Orders

  setup do
    {:ok, phoenix} =
      Catalog.create_sticker(%{
        name: "Phoenix",
        unit_price_cents: 200,
        image_path: "/images/stickers/phoenix.svg",
        width_mm: 60,
        height_mm: 60
      })

    {:ok, hex} =
      Catalog.create_sticker(%{
        name: "Hex",
        unit_price_cents: 350,
        image_path: "/images/stickers/hex.svg",
        width_mm: 60,
        height_mm: 60
      })

    %{phoenix: phoenix, hex: hex}
  end

  test "renders the sticker gallery", %{conn: conn, phoenix: phoenix} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#sticker-gallery")
    assert has_element?(view, "#sticker-inc-#{phoenix.id}")
    assert has_element?(view, "#sticker-qty-#{phoenix.id}", "0")
    assert has_element?(view, "#cart-total", "0,00 €")
  end

  test "updates quantities and the running total", %{conn: conn, phoenix: phoenix, hex: hex} do
    {:ok, view, _html} = live(conn, ~p"/")

    view |> element("#sticker-inc-#{phoenix.id}") |> render_click()
    view |> element("#sticker-inc-#{phoenix.id}") |> render_click()
    view |> element("#sticker-inc-#{hex.id}") |> render_click()
    html = view |> element("#sticker-dec-#{phoenix.id}") |> render_click()

    assert has_element?(view, "#sticker-qty-#{phoenix.id}", "1")
    assert has_element?(view, "#sticker-qty-#{hex.id}", "1")
    assert has_element?(view, "#cart-count", "2")
    assert html =~ "5,50 €"
    assert has_element?(view, "#cart-line-#{phoenix.id}")
  end

  test "places an order with customer details", %{conn: conn, phoenix: phoenix} do
    {:ok, view, _html} = live(conn, ~p"/")

    view |> element("#sticker-inc-#{phoenix.id}") |> render_click()
    view |> element("#sticker-inc-#{phoenix.id}") |> render_click()

    view
    |> form("#checkout-form",
      checkout: %{first_name: "Tim", last_name: "Tonix", email: "tim@example.com"}
    )
    |> render_submit()

    assert has_element?(view, "#order-confirmation")
    assert [order] = Orders.list_orders()
    assert order.customer_name == "Tim Tonix"
    assert order.customer_email == "tim@example.com"
    assert order.total_cents == 400
    assert hd(order.order_items).quantity == 2
  end

  test "rejects checkout when the cart is empty", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> form("#checkout-form",
      checkout: %{first_name: "Tim", last_name: "Tonix", email: "tim@example.com"}
    )
    |> render_submit()

    assert has_element?(view, "#cart-empty")
    assert Orders.list_orders() == []
  end
end
