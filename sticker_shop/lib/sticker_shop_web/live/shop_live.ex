defmodule StickerShopWeb.ShopLive do
  use StickerShopWeb, :live_view

  alias StickerShop.Catalog
  alias StickerShop.Catalog.{Category, Formats}
  alias StickerShop.Orders
  alias StickerShop.Orders.OrderNotifier

  @max_quantity 99
  @checkout_types %{
    first_name: :string,
    last_name: :string,
    email: :string,
    payment_method: :string,
    notes: :string
  }

  @impl true
  def mount(_params, _session, socket) do
    categories = Catalog.list_categories()
    categories_by_slug = Map.new(categories, &{&1.slug, &1})

    unlocked_categories =
      categories
      |> Enum.reject(&Category.protected?/1)
      |> Enum.map(& &1.slug)

    all_stickers = Catalog.list_active_stickers()

    socket =
      socket
      |> assign(:page_title, "Boutique · Stickers")
      |> assign(:current_scope, nil)
      |> assign(:categories, categories)
      |> assign(:categories_by_slug, categories_by_slug)
      |> assign(:all_stickers, all_stickers)
      |> assign(:stickers_by_id, Map.new(all_stickers, &{&1.id, &1}))
      |> assign(:formats, Formats.all())
      |> assign(:selected_formats, %{})
      |> assign(:selected_category, "all")
      |> assign(:search_query, "")
      |> assign(:unlocked_categories, unlocked_categories)
      |> assign(:pending_unlock_category, nil)
      |> assign(:show_password_modal, false)
      |> assign(:preview_sticker, nil)
      |> assign(:quantities, %{})
      |> assign(:cart_lines, [])
      |> assign(:cart_total_cents, 0)
      |> assign(:cart_count, 0)
      |> assign(:placed_order, nil)
      |> assign(:payment_info, OrderNotifier.config_info())
      |> assign(:form, to_form(checkout_changeset(%{}), as: :checkout))
      |> stream(
        :stickers,
        filter_stickers(all_stickers, "all", unlocked_categories, categories_by_slug, "")
      )

    {:ok, socket}
  end

  @impl true
  def handle_event("filter_category", %{"category" => "all"}, socket) do
    filtered =
      filter_stickers(
        socket.assigns.all_stickers,
        "all",
        socket.assigns.unlocked_categories,
        socket.assigns.categories_by_slug,
        socket.assigns.search_query
      )

    {:noreply,
     socket
     |> assign(:selected_category, "all")
     |> stream(:stickers, filtered, reset: true)}
  end

  def handle_event("filter_category", %{"category" => slug}, socket) do
    cat = Map.get(socket.assigns.categories_by_slug, slug)

    if cat && Category.protected?(cat) && slug not in socket.assigns.unlocked_categories do
      {:noreply,
       socket
       |> assign(:pending_unlock_category, cat)
       |> assign(:show_password_modal, true)}
    else
      filtered =
        filter_stickers(
          socket.assigns.all_stickers,
          slug,
          socket.assigns.unlocked_categories,
          socket.assigns.categories_by_slug,
          socket.assigns.search_query
        )

      {:noreply,
       socket
       |> assign(:selected_category, slug)
       |> stream(:stickers, filtered, reset: true)}
    end
  end

  def handle_event("search", %{"query" => query}, socket) do
    trimmed = String.trim(query)

    filtered =
      filter_stickers(
        socket.assigns.all_stickers,
        socket.assigns.selected_category,
        socket.assigns.unlocked_categories,
        socket.assigns.categories_by_slug,
        trimmed
      )

    {:noreply,
     socket
     |> assign(:search_query, query)
     |> stream(:stickers, filtered, reset: true)}
  end

  def handle_event("clear_search", _params, socket) do
    filtered =
      filter_stickers(
        socket.assigns.all_stickers,
        socket.assigns.selected_category,
        socket.assigns.unlocked_categories,
        socket.assigns.categories_by_slug,
        ""
      )

    {:noreply,
     socket
     |> assign(:search_query, "")
     |> stream(:stickers, filtered, reset: true)}
  end

  def handle_event("open_preview", %{"id" => raw_id}, socket) do
    case Integer.parse(raw_id) do
      {id, ""} ->
        {:noreply, assign(socket, :preview_sticker, Map.get(socket.assigns.stickers_by_id, id))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("close_preview", _params, socket) do
    {:noreply, assign(socket, :preview_sticker, nil)}
  end

  def handle_event("unlock_category", %{"password" => pwd}, socket) do
    target_cat =
      socket.assigns.pending_unlock_category ||
        Map.get(socket.assigns.categories_by_slug, "bicus")

    if target_cat && Category.valid_password?(target_cat, pwd) do
      unlocked = [target_cat.slug | socket.assigns.unlocked_categories] |> Enum.uniq()

      filtered =
        filter_stickers(
          socket.assigns.all_stickers,
          target_cat.slug,
          unlocked,
          socket.assigns.categories_by_slug,
          socket.assigns.search_query
        )

      {:noreply,
       socket
       |> assign(:unlocked_categories, unlocked)
       |> assign(:selected_category, target_cat.slug)
       |> assign(:pending_unlock_category, nil)
       |> assign(:show_password_modal, false)
       |> stream(:stickers, filtered, reset: true)
       |> put_flash(:info, "Catégorie #{target_cat.name} déverrouillée !")}
    else
      {:noreply, put_flash(socket, :error, "Mot de passe incorrect.")}
    end
  end

  def handle_event("close_password_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_password_modal, false)
     |> assign(:pending_unlock_category, nil)}
  end

  def handle_event("select_format", %{"id" => raw_id, "format" => format_id}, socket) do
    with {id, ""} <- Integer.parse(raw_id),
         %{} = sticker <- Map.get(socket.assigns.stickers_by_id, id) do
      selected_formats = Map.put(socket.assigns.selected_formats, id, format_id)

      {:noreply,
       socket
       |> assign(:selected_formats, selected_formats)
       |> stream_insert(:stickers, sticker)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("inc", %{"id" => id} = params, socket) do
    format =
      Map.get(params, "format") || selected_format(socket.assigns.selected_formats, parse_id(id))

    {:noreply, bump_quantity(socket, id, format, 1)}
  end

  def handle_event("dec", %{"id" => id} = params, socket) do
    format =
      Map.get(params, "format") || selected_format(socket.assigns.selected_formats, parse_id(id))

    {:noreply, bump_quantity(socket, id, format, -1)}
  end

  def handle_event("remove_line", %{"id" => raw_id, "format" => format_id}, socket) do
    with {id, ""} <- Integer.parse(raw_id),
         %{} = sticker <- Map.get(socket.assigns.stickers_by_id, id) do
      quantities = Map.delete(socket.assigns.quantities, {id, format_id})

      {:noreply,
       socket
       |> assign(:quantities, quantities)
       |> assign_cart(cart_lines(socket.assigns.stickers_by_id, quantities))
       |> stream_insert(:stickers, sticker)}
    else
      _ -> {:noreply, socket}
    end
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
          customer_email: String.trim(checkout.email),
          notes: build_order_notes(checkout)
        }

        items =
          Enum.map(socket.assigns.cart_lines, fn line ->
            %{
              sticker_id: line.sticker.id,
              format: line.format.id,
              quantity: line.quantity
            }
          end)

        case Orders.create_order(attrs, items) do
          {:ok, order} ->
            all_stickers = Catalog.list_active_stickers()

            filtered =
              filter_stickers(
                all_stickers,
                socket.assigns.selected_category,
                socket.assigns.unlocked_categories,
                socket.assigns.categories_by_slug,
                socket.assigns.search_query
              )

            {:noreply,
             socket
             |> assign(:all_stickers, all_stickers)
             |> assign(:stickers_by_id, Map.new(all_stickers, &{&1.id, &1}))
             |> assign(:quantities, %{})
             |> assign_cart([])
             |> assign(:placed_order, order)
             |> assign(:form, to_form(checkout_changeset(%{}), as: :checkout))
             |> stream(:stickers, filtered, reset: true)
             |> put_flash(
               :info,
               "Commande ##{order.id} enregistrée ! Un email récapitulatif t'a été envoyé."
             )}

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

  defp filter_stickers(stickers, category, unlocked_categories, categories_by_slug, search_query) do
    normalized_query =
      search_query
      |> to_string()
      |> String.trim()
      |> String.downcase()

    Enum.filter(stickers, fn sticker ->
      sticker_cat = Map.get(categories_by_slug, sticker.category)
      is_protected = Category.protected?(sticker_cat)
      is_unlocked = sticker.category in unlocked_categories or not is_protected

      category_match =
        case category do
          "all" ->
            is_unlocked

          other ->
            sticker.category == other and is_unlocked
        end

      search_match =
        normalized_query == "" or
          String.contains?(String.downcase(sticker.name), normalized_query)

      category_match and search_match
    end)
  end

  def category_name(categories_by_slug, slug) do
    case Map.get(categories_by_slug, slug) do
      %Category{name: name} -> name
      _ -> String.capitalize(to_string(slug))
    end
  end

  def category_protected?(categories_by_slug, slug) do
    case Map.get(categories_by_slug, slug) do
      %Category{} = cat -> Category.protected?(cat)
      _ -> false
    end
  end

  defp bump_quantity(socket, raw_id, format_id, delta) do
    with {id, ""} <- Integer.parse(raw_id),
         %{} = sticker <- Map.get(socket.assigns.stickers_by_id, id) do
      key = {id, format_id}

      quantities =
        Map.update(socket.assigns.quantities, key, max(delta, 0), fn qty ->
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
    |> Enum.filter(fn {_key, qty} -> qty > 0 end)
    |> Enum.map(fn {{id, format_id}, qty} ->
      sticker = Map.fetch!(stickers_by_id, id)
      format = Formats.get(format_id)
      unit_price = Formats.price_for(sticker.unit_price_cents, format.id)

      %{
        sticker: sticker,
        format: format,
        quantity: qty,
        unit_price_cents: unit_price,
        line_total_cents: qty * unit_price
      }
    end)
    |> Enum.sort_by(&{&1.sticker.name, &1.format.id})
  end

  defp checkout_changeset(attrs) do
    {%{}, @checkout_types}
    |> Ecto.Changeset.cast(attrs, [:first_name, :last_name, :email, :payment_method, :notes])
    |> Ecto.Changeset.validate_required([:first_name, :last_name, :email], message: "obligatoire")
    |> Ecto.Changeset.validate_length(:first_name, min: 1, max: 60)
    |> Ecto.Changeset.validate_length(:last_name, min: 1, max: 60)
    |> Ecto.Changeset.validate_length(:notes, max: 500)
    |> Ecto.Changeset.validate_format(:email, ~r/^[^\s]+@[^\s]+$/,
      message: "adresse email invalide"
    )
  end

  defp build_order_notes(checkout) do
    payment_label =
      case Map.get(checkout, :payment_method) do
        "cash" -> "Paiement prévu : Cash (espèces)"
        "wero" -> "Paiement prévu : Wero"
        "rib" -> "Paiement prévu : Virement (RIB demandé)"
        _ -> nil
      end

    custom_notes =
      case Map.get(checkout, :notes) do
        notes when is_binary(notes) ->
          trimmed = String.trim(notes)
          if trimmed == "", do: nil, else: trimmed

        _ ->
          nil
      end

    [payment_label, custom_notes]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
    |> case do
      "" -> nil
      combined -> combined
    end
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

  def selected_format(selected_formats, sticker_id) do
    Map.get(selected_formats, sticker_id, Formats.default_id())
  end

  def quantity(quantities, sticker_id, format_id) do
    Map.get(quantities, {sticker_id, format_id}, 0)
  end

  def quantity(quantities, sticker_id) do
    quantity(quantities, sticker_id, Formats.default_id())
  end

  def total_sticker_quantity(quantities, sticker_id) do
    Enum.reduce(quantities, 0, fn
      {{^sticker_id, _format_id}, qty}, acc when qty > 0 -> acc + qty
      _, acc -> acc
    end)
  end

  defp parse_id(id) when is_integer(id), do: id

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> int
      _ -> 0
    end
  end
end
