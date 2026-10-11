defmodule StickerShopWeb.ShopLive do
  use StickerShopWeb, :live_view

  alias StickerShop.Catalog
  alias StickerShop.Orders

  @max_quantity 99
  @checkout_types %{first_name: :string, last_name: :string, email: :string}

  @impl true
  def mount(_params, _session, socket) do
    stickers = Catalog.list_active_stickers()

    {:ok,
     socket
     |> assign(:page_title, "Boutique")
     |> assign(:current_scope, nil)
     |> assign(:stickers_by_id, Map.new(stickers, &{&1.id, &1}))
     |> assign(:quantities, %{})
     |> assign(:cart_lines, [])
     |> assign(:cart_total_cents, 0)
     |> assign(:cart_count, 0)
     |> assign(:placed_order, nil)
     |> assign(:form, to_form(checkout_changeset(%{}), as: :checkout))
     |> stream(:stickers, stickers)}
  end

  @impl true
  def handle_event("inc", %{"id" => id}, socket) do
    {:noreply, bump_quantity(socket, id, 1)}
  end

  def handle_event("dec", %{"id" => id}, socket) do
    {:noreply, bump_quantity(socket, id, -1)}
  end

  def handle_event("validate", %{"checkout" => params}, socket) do
    form =
      params
      |> checkout_changeset()
      |> Map.put(:action, :validate)
      |> to_form(as: :checkout)

    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("place_order", %{"checkout" => params}, socket) do
    changeset = checkout_changeset(params)

    cond do
      socket.assigns.cart_count == 0 ->
        {:noreply, put_flash(socket, :error, "Ajoute au moins un sticker avant de commander.")}

      not changeset.valid? ->
        {:noreply,
         assign(socket, :form, to_form(Map.put(changeset, :action, :validate), as: :checkout))}

      true ->
        checkout = Ecto.Changeset.apply_changes(changeset)

        attrs = %{
          customer_name: "#{String.trim(checkout.first_name)} #{String.trim(checkout.last_name)}",
          customer_email: String.trim(checkout.email)
        }

        items =
          Enum.map(socket.assigns.cart_lines, fn line ->
            %{sticker_id: line.sticker.id, quantity: line.quantity}
          end)

        case Orders.create_order(attrs, items) do
          {:ok, order} ->
            stickers = Catalog.list_active_stickers()

            {:noreply,
             socket
             |> assign(:stickers_by_id, Map.new(stickers, &{&1.id, &1}))
             |> assign(:quantities, %{})
             |> assign_cart([])
             |> assign(:placed_order, order)
             |> assign(:form, to_form(checkout_changeset(%{}), as: :checkout))
             |> stream(:stickers, stickers, reset: true)
             |> put_flash(:info, "Commande ##{order.id} enregistrée. Merci !")}

          {:error, %Ecto.Changeset{} = order_changeset} ->
            {:noreply,
             socket
             |> assign(:form, to_form(Map.put(changeset, :action, :validate), as: :checkout))
             |> put_flash(:error, checkout_error_message(order_changeset))}

          {:error, :empty_cart} ->
            {:noreply,
             put_flash(socket, :error, "Ajoute au moins un sticker avant de commander.")}

          {:error, :sticker_unavailable} ->
            {:noreply, put_flash(socket, :error, "Un sticker du panier n'est plus disponible.")}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, "Impossible d'enregistrer la commande.")}
        end
    end
  end

  def handle_event("shop_again", _params, socket) do
    {:noreply, assign(socket, :placed_order, nil)}
  end

  defp bump_quantity(socket, raw_id, delta) do
    with {id, ""} <- Integer.parse(raw_id),
         %{} = sticker <- Map.get(socket.assigns.stickers_by_id, id) do
      quantities =
        Map.update(socket.assigns.quantities, id, max(delta, 0), fn qty ->
          (qty + delta) |> max(0) |> min(@max_quantity)
        end)

      socket
      |> assign(:quantities, quantities)
      |> assign_cart(cart_lines(socket.assigns.stickers_by_id, quantities))
      |> assign(:placed_order, nil)
      |> stream_insert(:stickers, sticker)
    else
      _ -> socket
    end
  end

  defp assign_cart(socket, cart_lines) do
    socket
    |> assign(:cart_lines, cart_lines)
    |> assign(:cart_count, Enum.reduce(cart_lines, 0, &(&1.quantity + &2)))
    |> assign(:cart_total_cents, Enum.reduce(cart_lines, 0, &(&1.line_total_cents + &2)))
  end

  defp cart_lines(stickers_by_id, quantities) do
    quantities
    |> Enum.filter(fn {_id, qty} -> qty > 0 end)
    |> Enum.map(fn {id, qty} ->
      sticker = Map.fetch!(stickers_by_id, id)

      %{
        sticker: sticker,
        quantity: qty,
        line_total_cents: qty * sticker.unit_price_cents
      }
    end)
    |> Enum.sort_by(& &1.sticker.name)
  end

  defp checkout_changeset(attrs) do
    {%{}, @checkout_types}
    |> Ecto.Changeset.cast(attrs, [:first_name, :last_name, :email])
    |> Ecto.Changeset.validate_required([:first_name, :last_name, :email], message: "obligatoire")
    |> Ecto.Changeset.validate_length(:first_name, min: 1, max: 60)
    |> Ecto.Changeset.validate_length(:last_name, min: 1, max: 60)
    |> Ecto.Changeset.validate_format(:email, ~r/^[^\s]+@[^\s]+$/,
      message: "adresse email invalide"
    )
  end

  defp checkout_error_message(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Map.values()
    |> List.flatten()
    |> Enum.join(" ")
    |> case do
      "" -> "Impossible d'enregistrer la commande."
      message -> message
    end
  end

  defp quantity(quantities, sticker_id), do: Map.get(quantities, sticker_id, 0)
end
