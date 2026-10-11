defmodule StickerShop.Orders do
  @moduledoc """
  Customer orders and their line items. Checkout snapshots sticker prices
  onto each `OrderItem` so later catalog edits do not change past totals.
  """

  import Ecto.Query, warn: false
  alias Ecto.Multi
  alias StickerShop.Repo
  alias StickerShop.Catalog
  alias StickerShop.Catalog.Sticker
  alias StickerShop.Orders.{Order, OrderItem}

  def list_orders(criteria \\ []) do
    base_query =
      from o in Order,
        order_by: [desc: o.inserted_at],
        preload: [order_items: :sticker]

    Enum.reduce(criteria, base_query, fn
      {:status, status}, query
      when status in [:pending, :confirmed, :printed, :fulfilled, :cancelled] ->
        from q in query, where: q.status == ^status

      _, query ->
        query
    end)
    |> Repo.all()
  end

  def list_pending_orders do
    Repo.all(
      from o in Order,
        where: o.status == :pending,
        order_by: [asc: o.inserted_at],
        preload: [order_items: :sticker]
    )
  end

  def list_orders_by_ids(ids) when is_list(ids) do
    Repo.all(
      from o in Order,
        where: o.id in ^ids,
        order_by: [asc: o.inserted_at],
        preload: [order_items: :sticker]
    )
  end

  def total_stickers_count(%Order{} = order) do
    Enum.reduce(order.order_items, 0, &(&1.quantity + &2))
  end

  def count_stickers_in_orders(orders) when is_list(orders) do
    Enum.reduce(orders, 0, fn order, acc ->
      total_stickers_count(order) + acc
    end)
  end

  def mark_orders_as_printed(ids) when is_list(ids) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from(o in Order, where: o.id in ^ids)
    |> Repo.update_all(set: [status: :printed, updated_at: now])
  end

  def get_order!(id) do
    Order
    |> Repo.get!(id)
    |> Repo.preload(order_items: :sticker)
  end

  @doc """
  Creates an order from customer details and a list of cart lines.

  Each line is a map with `:sticker_id` and `:quantity`. Unit prices are
  taken from the current catalog, not from the client.
  """
  def create_order(attrs, items) when is_list(items) do
    Multi.new()
    |> Multi.run(:validated_items, fn _repo, _changes ->
      build_order_items(items)
    end)
    |> Multi.insert(:order, fn %{validated_items: validated_items} ->
      total_cents = Enum.reduce(validated_items, 0, &(&1.line_total + &2))

      %Order{}
      |> Order.changeset(attrs)
      |> Ecto.Changeset.put_change(:status, :pending)
      |> Ecto.Changeset.put_change(:total_cents, total_cents)
    end)
    |> Multi.insert_all(:order_items, OrderItem, fn %{
                                                      order: order,
                                                      validated_items: validated_items
                                                    } ->
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Enum.map(validated_items, fn item ->
        %{
          order_id: order.id,
          sticker_id: item.sticker_id,
          quantity: item.quantity,
          unit_price_cents: item.unit_price_cents,
          inserted_at: now,
          updated_at: now
        }
      end)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{order: order}} -> {:ok, get_order!(order.id)}
      {:error, :order, changeset, _} -> {:error, changeset}
      {:error, :validated_items, reason, _} -> {:error, reason}
    end
  end

  def update_order_status(%Order{} = order, status) do
    order
    |> Order.changeset(%{status: status})
    |> Repo.update()
  end

  def change_order(%Order{} = order, attrs \\ %{}) do
    Order.changeset(order, attrs)
  end

  def line_total_cents(%OrderItem{} = item) do
    item.quantity * item.unit_price_cents
  end

  defp build_order_items([]), do: {:error, :empty_cart}

  defp build_order_items(items) do
    items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case normalize_item(item) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_item(item) when is_map(item) do
    sticker_id = fetch_item_value(item, :sticker_id)
    quantity = fetch_item_value(item, :quantity)

    with {:ok, quantity} <- parse_positive_integer(quantity),
         %Sticker{active: true} = sticker <- Catalog.get_sticker(sticker_id) do
      {:ok,
       %{
         sticker_id: sticker.id,
         quantity: quantity,
         unit_price_cents: sticker.unit_price_cents,
         line_total: quantity * sticker.unit_price_cents
       }}
    else
      nil -> {:error, :sticker_not_found}
      %Sticker{active: false} -> {:error, :sticker_unavailable}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_item_value(item, key) do
    Map.get(item, key) || Map.get(item, Atom.to_string(key))
  end

  defp parse_positive_integer(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp parse_positive_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int > 0 -> {:ok, int}
      _ -> {:error, :invalid_quantity}
    end
  end

  defp parse_positive_integer(_), do: {:error, :invalid_quantity}
end
