defmodule StickerShopWeb.Admin.PrintSheetControllerTest do
  use StickerShopWeb.ConnCase, async: true

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

  test "GET /admin/print-sheet requires authentication", %{conn: conn} do
    conn = get(conn, ~p"/admin/print-sheet")
    assert response(conn, 401)
  end

  test "GET /admin/print-sheet renders multi-order A4 imposition sheet", %{
    conn: conn,
    order1: order1,
    order2: order2
  } do
    conn =
      conn
      |> admin_conn()
      |> get(~p"/admin/print-sheet")

    html = response(conn, 200)

    # Verifies A4 sheet markup
    assert html =~ "sheet-page"
    assert html =~ "width: 210mm"
    assert html =~ "297mm"
    assert html =~ "12 STICKERS"
    assert html =~ "##{order1.id}"
    assert html =~ "##{order2.id}"
    assert html =~ "window.print()"
    assert html =~ "/images/stickers/phoenix.svg"
  end

  test "GET /admin/print-sheet?order_id=ID renders a single order sheet", %{
    conn: conn,
    order1: order1
  } do
    conn =
      conn
      |> admin_conn()
      |> get(~p"/admin/print-sheet?order_id=#{order1.id}")

    html = response(conn, 200)
    assert html =~ "sheet-page"
    assert html =~ "##{order1.id}"
    assert html =~ "3 STICKERS"
  end

  test "POST /admin/print-sheet/mark-printed marks orders and redirects to admin", %{
    conn: conn,
    order1: order1,
    order2: order2
  } do
    conn =
      conn
      |> admin_conn()
      |> post(~p"/admin/print-sheet/mark-printed", %{"order_ids" => [order1.id, order2.id]})

    assert redirected_to(conn) == ~p"/admin"
    assert Orders.get_order!(order1.id).status == :printed
    assert Orders.get_order!(order2.id).status == :printed
  end
end
