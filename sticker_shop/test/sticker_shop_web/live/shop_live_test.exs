defmodule StickerShopWeb.ShopLiveTest do
  use StickerShopWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StickerShop.Catalog
  alias StickerShop.Orders

  setup do
    {:ok, phoenix} =
      Catalog.create_sticker(%{
        name: "Phoenix",
        category: "general",
        unit_price_cents: 20,
        image_path: "/images/stickers/phoenix.svg",
        width_mm: 60,
        height_mm: 60
      })

    {:ok, hex} =
      Catalog.create_sticker(%{
        name: "Hex",
        category: "general",
        unit_price_cents: 30,
        image_path: "/images/stickers/hex.svg",
        width_mm: 60,
        height_mm: 60
      })

    {:ok, bicus_sam} =
      Catalog.create_sticker(%{
        name: "Bicus Sam",
        category: "bicus",
        unit_price_cents: 20,
        image_path: "/images/stickers/elixir.svg",
        width_mm: 60,
        height_mm: 60
      })

    %{phoenix: phoenix, hex: hex, bicus_sam: bicus_sam}
  end

  test "renders gallery with general stickers and hides bicus stickers by default", %{
    conn: conn,
    phoenix: phoenix,
    hex: hex,
    bicus_sam: bicus_sam
  } do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#sticker-gallery")
    assert has_element?(view, "#sticker-inc-#{phoenix.id}")
    assert has_element?(view, "#sticker-inc-#{hex.id}")
    refute has_element?(view, "#sticker-inc-#{bicus_sam.id}")
    assert has_element?(view, "#cart-total", "0,00 €")
  end

  test "bicus category requires password and unlocks stickers upon correct password", %{
    conn: conn,
    bicus_sam: bicus_sam
  } do
    {:ok, view, _html} = live(conn, ~p"/")

    # 1. Clic sur le filtre Bicus sans être déverrouillé -> ouvre la modale
    view |> element("#filter-category-bicus") |> render_click()
    assert has_element?(view, "#bicus-password-modal")

    # 2. Mauvais mot de passe -> erreur
    view
    |> form("#bicus-password-modal form", %{"password" => "mauvaiscode"})
    |> render_submit()

    assert render(view) =~ "Mot de passe incorrect"
    assert has_element?(view, "#bicus-password-modal")

    # 3. Bon mot de passe (défaut: bicus123) -> déverrouille et affiche les stickers Bicus
    view
    |> form("#bicus-password-modal form", %{"password" => "bicus123"})
    |> render_submit()

    refute has_element?(view, "#bicus-password-modal")
    assert render(view) =~ "Catégorie Bicus déverrouillée"
    assert has_element?(view, "#sticker-inc-#{bicus_sam.id}")
  end

  test "format selector updates pricing and supports multiple formats of the same sticker in cart",
       %{
         conn: conn,
         phoenix: phoenix
       } do
    {:ok, view, _html} = live(conn, ~p"/")

    # Prix initial standard 6x6 : 0,20 €
    assert has_element?(view, "#sticker-price-#{phoenix.id}", "0,20 €")

    # Sélection format Pleine Page A4 -> prix passe à 2,50 €
    view |> element("#sticker-#{phoenix.id}-format-poster_a4") |> render_click()
    assert has_element?(view, "#sticker-price-#{phoenix.id}", "2,50 €")

    # Ajout de 1 poster A4
    view |> element("#sticker-inc-#{phoenix.id}") |> render_click()
    assert has_element?(view, "#cart-line-#{phoenix.id}-poster_a4")
    assert has_element?(view, "#cart-total", "2,50 €")

    # Re-sélection format Standard 6x6 -> prix revient à 0,20 €
    view |> element("#sticker-#{phoenix.id}-format-standard_6x6") |> render_click()
    assert has_element?(view, "#sticker-price-#{phoenix.id}", "0,20 €")

    # Ajout de 2 standards 6x6
    view |> element("#sticker-inc-#{phoenix.id}") |> render_click()
    view |> element("#sticker-inc-#{phoenix.id}") |> render_click()
    assert has_element?(view, "#cart-line-#{phoenix.id}-standard_6x6")

    # Total panier = 2,50 + 2 * 0,20 = 2,90 €
    assert has_element?(view, "#cart-count", "3")
    assert has_element?(view, "#cart-total", "2,90 €")
  end

  test "places an order with customer details and format snapshot", %{
    conn: conn,
    phoenix: phoenix,
    hex: hex
  } do
    {:ok, view, _html} = live(conn, ~p"/")

    # 1 Phoenix format Moyen 10x10 (0,50 €)
    view |> element("#sticker-#{phoenix.id}-format-medium_10x10") |> render_click()
    view |> element("#sticker-inc-#{phoenix.id}") |> render_click()

    # 2 Hex format Standard 6x6 (2 * 0,30 € = 0,60 €)
    view |> element("#sticker-inc-#{hex.id}") |> render_click()
    view |> element("#sticker-inc-#{hex.id}") |> render_click()

    # Total = 0,50 + 0,60 = 1,10 € (110 cents)
    assert has_element?(view, "#cart-total", "1,10 €")

    view
    |> form("#checkout-form",
      checkout: %{first_name: "Tim", last_name: "Tonix", email: "tim@example.com"}
    )
    |> render_submit()

    assert has_element?(view, "#order-confirmation")
    assert [order] = Orders.list_orders()
    assert order.customer_name == "Tim Tonix"
    assert order.customer_email == "tim@example.com"
    assert order.total_cents == 110
    assert length(order.order_items) == 2

    phoenix_item = Enum.find(order.order_items, &(&1.sticker_id == phoenix.id))
    assert phoenix_item.quantity == 1
    assert phoenix_item.format == "medium_10x10"
    assert phoenix_item.width_mm == 100
    assert phoenix_item.height_mm == 100
    assert phoenix_item.unit_price_cents == 50

    hex_item = Enum.find(order.order_items, &(&1.sticker_id == hex.id))
    assert hex_item.quantity == 2
    assert hex_item.format == "standard_6x6"
    assert hex_item.width_mm == 60
    assert hex_item.height_mm == 60
    assert hex_item.unit_price_cents == 30
  end

  test "closing password modal via backdrop or cancel button", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    # Ouvre la modale
    view |> element("#filter-category-bicus") |> render_click()
    assert has_element?(view, "#bicus-password-modal")

    # Clic sur le bouton Annuler
    view |> element("#bicus-password-modal button", "Annuler") |> render_click()
    refute has_element?(view, "#bicus-password-modal")

    # Ré-ouvre puis clic sur le backdrop
    view |> element("#filter-category-bicus") |> render_click()
    assert has_element?(view, "#bicus-password-modal")
    view |> element("#bicus-password-backdrop") |> render_click()
    refute has_element?(view, "#bicus-password-modal")
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
