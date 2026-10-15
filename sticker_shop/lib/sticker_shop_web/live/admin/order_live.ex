defmodule StickerShopWeb.Admin.OrderLive do
  use StickerShopWeb, :live_view

  alias StickerShop.Catalog
  alias StickerShop.Catalog.ImageOptimizer
  alias StickerShop.Orders
  alias StickerShop.Printing.SheetPacker

  @default_slot_size 60

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Administration · Merch")
      |> assign(:current_scope, nil)
      |> assign(:tab, :orders)
      |> assign(:status_filter, :pending)
      |> refresh_stats()
      |> assign(:orders, Orders.list_pending_orders())
      |> assign(:stickers, Catalog.list_stickers())
      |> assign_new_sticker_form(%{})
      |> allow_upload(:sticker_image,
        accept: ~w(.svg .png .jpg .jpeg .webp),
        max_entries: 1,
        max_file_size: 15_000_000
      )

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab =
      case params["tab"] do
        "stickers" -> :stickers
        _ -> :orders
      end

    filter =
      case params["status"] do
        "all" -> :all
        "printed" -> :printed
        "fulfilled" -> :fulfilled
        "cancelled" -> :cancelled
        _ -> :pending
      end

    {:noreply,
     socket
     |> assign(:tab, tab)
     |> assign(:status_filter, filter)
     |> refresh_orders(filter)}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, push_patch(socket, to: ~p"/admin?tab=#{tab}")}
  end

  def handle_event("filter_status", %{"status" => status}, socket) do
    {:noreply, push_patch(socket, to: ~p"/admin?tab=orders&status=#{status}")}
  end

  def handle_event("update_status", %{"order_id" => id, "status" => status}, socket) do
    with {order_id, ""} <- Integer.parse(id),
         order when not is_nil(order) <- Enum.find(socket.assigns.orders, &(&1.id == order_id)),
         status_atom when status_atom in [:pending, :confirmed, :printed, :fulfilled, :cancelled] <-
           String.to_existing_atom(status),
         {:ok, _updated} <- Orders.update_order_status(order, status_atom) do
      {:noreply,
       socket
       |> put_flash(:info, "Statut de la commande ##{order_id} mis à jour : #{status_atom}.")
       |> refresh_all()}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Impossible de mettre à jour le statut.")}
    end
  end

  def handle_event("mark_pending_printed", _params, socket) do
    pending_orders = Orders.list_pending_orders()
    ids = Enum.map(pending_orders, & &1.id)

    case ids do
      [] ->
        {:noreply,
         put_flash(socket, :info, "Aucune commande en attente à marquer comme imprimée.")}

      _ ->
        {count, _} = Orders.mark_orders_as_printed(ids)

        {:noreply,
         socket
         |> put_flash(:info, "#{count} commande(s) marquée(s) comme imprimée(s).")
         |> refresh_all()}
    end
  end

  def handle_event("toggle_sticker", %{"id" => id}, socket) do
    with {sticker_id, ""} <- Integer.parse(id),
         sticker <- Catalog.get_sticker(sticker_id),
         {:ok, updated} <- Catalog.toggle_sticker_active(sticker) do
      status_label = if updated.active, do: "activé", else: "désactivé"

      {:noreply,
       socket
       |> put_flash(:info, "Sticker « #{updated.name} » #{status_label}.")
       |> assign(:stickers, Catalog.list_stickers())}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Erreur lors de la modification du sticker.")}
    end
  end

  def handle_event("delete_sticker", %{"id" => id}, socket) do
    with {sticker_id, ""} <- Integer.parse(id),
         sticker <- Catalog.get_sticker(sticker_id) do
      case Catalog.delete_sticker(sticker) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, "Sticker supprimé du catalogue.")
           |> assign(:stickers, Catalog.list_stickers())}

        {:error, _changeset} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             "Impossible de supprimer ce sticker car des commandes y sont associées. Tu peux le désactiver."
           )}
      end
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Sticker introuvable.")}
    end
  end

  def handle_event("set_sticker_category", %{"id" => id, "category" => category}, socket) do
    with {sticker_id, ""} <- Integer.parse(id),
         sticker when not is_nil(sticker) <- Catalog.get_sticker(sticker_id),
         valid_category when valid_category in ["general", "bicus"] <- category,
         {:ok, updated} <- Catalog.update_sticker(sticker, %{category: valid_category}) do
      label = if updated.category == "bicus", do: "Bicus 🔒", else: "Général"

      {:noreply,
       socket
       |> put_flash(:info, "Catégorie de « #{updated.name} » mise à jour : #{label}.")
       |> assign(:stickers, Catalog.list_stickers())}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Impossible de modifier la catégorie.")}
    end
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :sticker_image, ref)}
  end

  def handle_event("validate_sticker", %{"new_sticker" => params}, socket) do
    {:noreply, assign_new_sticker_form(socket, params)}
  end

  def handle_event("save_sticker", %{"new_sticker" => params}, socket) do
    uploaded_files =
      consume_uploaded_entries(socket, :sticker_image, fn %{path: path}, entry ->
        ext = Path.extname(entry.client_name) |> String.downcase()
        timestamp = System.system_time(:millisecond)
        random_suffix = Base.url_encode64(:crypto.strong_rand_bytes(6), padding: false)
        clean_ext = if ext in ~w(.svg .png .jpg .jpeg .webp), do: ext, else: ".png"
        filename = "sticker_#{timestamp}_#{random_suffix}#{clean_ext}"

        # 1. Dossier source pour persistance au-delà des recompilations
        source_dir = Path.expand("priv/static/uploads/stickers")
        File.mkdir_p!(source_dir)
        source_target = Path.join(source_dir, filename)

        # 2. Dossier build pour service immédiat par Plug.Static
        build_dir = Path.join([:code.priv_dir(:sticker_shop), "static", "uploads", "stickers"])
        File.mkdir_p!(build_dir)
        build_target = Path.join(build_dir, filename)

        # Optimisation automatique 300 DPI (sans perte de netteté)
        ImageOptimizer.optimize(path, source_target)
        File.cp!(source_target, build_target)

        {:ok, "/uploads/stickers/#{filename}"}
      end)

    image_path = List.first(uploaded_files)

    category =
      case params["category"] do
        "bicus" -> "bicus"
        _ -> "general"
      end

    with {:ok, price_cents} <- parse_price_cents(params["price_euros"]),
         name when is_binary(name) and byte_size(name) > 0 <- String.trim(params["name"] || ""),
         {width_mm, ""} <- Integer.parse(params["width_mm"] || "#{@default_slot_size}"),
         {height_mm, ""} <- Integer.parse(params["height_mm"] || "#{@default_slot_size}"),
         true <- not is_nil(image_path) do
      attrs = %{
        name: name,
        category: category,
        unit_price_cents: price_cents,
        image_path: image_path,
        width_mm: width_mm,
        height_mm: height_mm,
        active: true
      }

      case Catalog.create_sticker(attrs) do
        {:ok, new_sticker} ->
          {:noreply,
           socket
           |> put_flash(:info, "Nouveau sticker « #{new_sticker.name} » ajouté au catalogue !")
           |> assign(:stickers, Catalog.list_stickers())
           |> assign_new_sticker_form(%{})}

        {:error, changeset} ->
          {:noreply,
           socket
           |> put_flash(
             :error,
             "Erreur dans les champs du sticker : #{inspect(changeset.errors)}"
           )
           |> assign_new_sticker_form(params)}
      end
    else
      false ->
        {:noreply,
         socket
         |> put_flash(:error, "Merci de téléverser un fichier image (SVG, PNG ou JPG).")
         |> assign_new_sticker_form(params)}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, reason)
         |> assign_new_sticker_form(params)}

      _ ->
        {:noreply,
         socket
         |> put_flash(:error, "Vérifie les informations saisies (nom, prix et dimensions).")
         |> assign_new_sticker_form(params)}
    end
  end

  defp assign_new_sticker_form(socket, params) do
    default_params = %{
      "name" => "",
      "category" => "general",
      "price_euros" => "0.20",
      "width_mm" => Integer.to_string(@default_slot_size),
      "height_mm" => Integer.to_string(@default_slot_size)
    }

    form_params = Map.merge(default_params, params)
    assign(socket, :new_sticker_form, to_form(form_params, as: :new_sticker))
  end

  defp refresh_stats(socket) do
    all_orders = Orders.list_orders()
    pending_orders = Enum.filter(all_orders, &(&1.status == :pending))
    printed_orders = Enum.filter(all_orders, &(&1.status == :printed))
    pending_stickers_count = Orders.count_stickers_in_orders(pending_orders)

    socket
    |> assign(:all_orders_count, length(all_orders))
    |> assign(:pending_orders_count, length(pending_orders))
    |> assign(:printed_orders_count, length(printed_orders))
    |> assign(:pending_stickers_count, pending_stickers_count)
    |> assign(:estimated_pages, SheetPacker.estimate_pages(pending_stickers_count))
  end

  defp refresh_all(socket) do
    socket
    |> refresh_stats()
    |> refresh_orders(socket.assigns.status_filter)
  end

  defp refresh_orders(socket, :all), do: assign(socket, :orders, Orders.list_orders())

  defp refresh_orders(socket, status) when is_atom(status) do
    assign(socket, :orders, Orders.list_orders(status: status))
  end

  defp parse_price_cents(nil), do: {:error, "Le prix est requis"}

  defp parse_price_cents(price_str) when is_binary(price_str) do
    cleaned =
      price_str
      |> String.trim()
      |> String.replace("€", "")
      |> String.replace(",", ".")
      |> String.trim()

    case Float.parse(cleaned) do
      {euros, ""} when euros > 0 ->
        {:ok, round(euros * 100)}

      _ ->
        case Integer.parse(cleaned) do
          {euros, ""} when euros > 0 -> {:ok, euros * 100}
          _ -> {:error, "Format de prix invalide (ex: 3.50 ou 4)"}
        end
    end
  end
end
