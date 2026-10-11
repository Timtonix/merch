defmodule StickerShopWeb.Admin.OrderLiveTest do
  use StickerShopWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias StickerShop.Catalog
  alias StickerShop.Orders

  setup do
    {:ok, sticker} =
      Catalog.create_sticker(%{
        name: "Phoenix",
        unit_price_cents: 200,
        image_path: "/images/stickers/phoenix.svg",
        width_mm: 60,
        height_mm: 60
      })

    {:ok, order1} =
      Orders.create_order(
        %{customer_name: "Alice", customer_email: "alice@example.com"},
        [%{sticker_id: sticker.id, quantity: 3}]
      )

    {:ok, order2} =
      Orders.create_order(
        %{customer_name: "Bob", customer_email: "bob@example.com"},
        [%{sticker_id: sticker.id, quantity: 9}]
      )

    %{sticker: sticker, order1: order1, order2: order2}
  end

  test "blocks unauthenticated access with 401 Unauthorized", %{conn: conn} do
    conn = get(conn, ~p"/admin")
    assert response(conn, 401)
  end

  test "mounts and displays orders and print banner with valid auth", %{
    conn: conn,
    order1: order1,
    order2: order2
  } do
    conn = admin_conn(conn)
    {:ok, view, _html} = live(conn, ~p"/admin")

    assert has_element?(view, "#print-summary-banner")
    assert has_element?(view, "#summary-pending-orders", "2")
    assert has_element?(view, "#summary-pending-stickers", "12")
    assert has_element?(view, "#summary-estimated-pages", "1")
    assert has_element?(view, "#order-card-#{order1.id}")
    assert has_element?(view, "#order-card-#{order2.id}")
    assert has_element?(view, "#print-all-btn")
  end

  test "marks all pending orders as printed", %{conn: conn, order1: order1, order2: order2} do
    conn = admin_conn(conn)
    {:ok, view, _html} = live(conn, ~p"/admin")

    view |> element("#mark-all-printed-btn") |> render_click()

    assert Orders.get_order!(order1.id).status == :printed
    assert Orders.get_order!(order2.id).status == :printed

    assert has_element?(view, "#summary-pending-orders", "0")
    assert has_element?(view, "#orders-empty")
  end

  test "switches to catalog tab and toggles sticker active status", %{
    conn: conn,
    sticker: sticker
  } do
    conn = admin_conn(conn)
    {:ok, view, _html} = live(conn, ~p"/admin")

    view |> element("#tab-stickers-btn") |> render_click()

    assert has_element?(view, "#new-sticker-form")
    assert has_element?(view, "#admin-sticker-#{sticker.id}")
    assert has_element?(view, "#admin-sticker-#{sticker.id}", "Actif")

    view |> element("#toggle-sticker-#{sticker.id}") |> render_click()

    assert has_element?(view, "#admin-sticker-#{sticker.id}", "Inactif")
    assert Catalog.get_sticker!(sticker.id).active == false
  end

  test "updates individual order status", %{conn: conn, order1: order1} do
    conn = admin_conn(conn)
    {:ok, view, _html} = live(conn, ~p"/admin")

    # Order 1 has pending status, click "-> Imprimée"
    view
    |> element("#order-card-#{order1.id} button", "-> Imprimée")
    |> render_click()

    assert Orders.get_order!(order1.id).status == :printed
  end

  test "uploads a new sticker and adds it to the catalog", %{conn: conn} do
    conn = admin_conn(conn)
    {:ok, view, _html} = live(conn, ~p"/admin")

    view |> element("#tab-stickers-btn") |> render_click()

    image =
      file_input(view, "#new-sticker-form", :sticker_image, [
        %{
          name: "logo_community.png",
          content: <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13>>,
          type: "image/png"
        }
      ])

    render_upload(image, "logo_community.png")

    view
    |> form("#new-sticker-form",
      new_sticker: %{
        "name" => "Super Logo Community",
        "price_euros" => "4.50",
        "width_mm" => "60",
        "height_mm" => "60"
      }
    )
    |> render_submit()

    assert render(view) =~ "Super Logo Community"
    assert render(view) =~ "4,50 €"

    # Verifies it is saved in database
    assert [new_sticker | _] =
             Catalog.list_stickers() |> Enum.filter(&(&1.name == "Super Logo Community"))

    assert new_sticker.unit_price_cents == 450
    assert new_sticker.width_mm == 60
    assert new_sticker.height_mm == 60
    assert String.starts_with?(new_sticker.image_path, "/uploads/stickers/")
  end
end
