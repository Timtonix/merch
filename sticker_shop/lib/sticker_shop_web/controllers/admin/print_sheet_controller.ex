defmodule StickerShopWeb.Admin.PrintSheetController do
  use StickerShopWeb, :controller

  alias StickerShop.Orders
  alias StickerShop.Printing.SheetPacker

  def sheet(conn, params) do
    orders =
      case params["order_id"] do
        nil ->
          Orders.list_pending_orders()

        id ->
          case Integer.parse(id) do
            {order_id, ""} -> [Orders.get_order!(order_id)]
            _ -> Orders.list_pending_orders()
          end
      end

    packed = SheetPacker.pack_orders(orders)

    conn
    |> put_layout(false)
    |> render(:sheet,
      orders: orders,
      packed: packed,
      order_ids: Enum.map(orders, & &1.id)
    )
  end

  def mark_printed(conn, %{"order_ids" => ids}) do
    order_ids =
      ids
      |> Enum.map(fn id ->
        case Integer.parse(to_string(id)) do
          {int, ""} -> int
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    case order_ids do
      [] ->
        conn
        |> put_flash(:info, "Aucune commande sélectionnée.")
        |> redirect(to: ~p"/admin")

      _ ->
        {count, _} = Orders.mark_orders_as_printed(order_ids)

        conn
        |> put_flash(:info, "#{count} commande(s) marquée(s) comme imprimée(s).")
        |> redirect(to: ~p"/admin")
    end
  end
end
