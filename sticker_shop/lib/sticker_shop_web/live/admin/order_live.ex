defmodule StickerShopWeb.Admin.OrderLive do
  use StickerShopWeb, :live_view

  alias StickerShop.Catalog
  alias StickerShop.Catalog.{Category, Formats, ImageOptimizer}
  alias StickerShop.Orders
  alias StickerShop.Orders.OrderNotifier
  alias StickerShop.Printing.SheetPacker

  @default_slot_size 60

  @impl true
  def mount(_params, _session, socket) do
    categories = Catalog.list_categories()

    socket =
      socket
      |> assign(:page_title, "Administration · Merch")
      |> assign(:current_scope, nil)
      |> assign(:tab, :orders)
      |> assign(:status_filter, :pending)
      |> refresh_stats()
      |> assign(:orders, Orders.list_pending_orders())
      |> assign(:categories, categories)
      |> assign(:categories_by_slug, Map.new(categories, &{&1.slug, &1}))
      |> assign(:stickers, Catalog.list_stickers())
      |> assign_new_sticker_form(%{})
      |> assign_new_category_form(%{})
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
      extra_msg =
        if status_atom == :printed and order.status != :printed do
          " (email d'impression envoyé à #{order.customer_email})"
        else
          ""
        end

      {:noreply,
       socket
       |> put_flash(
         :info,
         "Statut de la commande ##{order_id} mis à jour : #{status_atom}#{extra_msg}."
       )
       |> refresh_all()}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Impossible de mettre à jour le statut.")}
    end
  end

  def handle_event("resend_email", %{"order_id" => id, "type" => type}, socket) do
    with {order_id, ""} <- Integer.parse(id),
         order when not is_nil(order) <- Enum.find(socket.assigns.orders, &(&1.id == order_id)) do
      result =
        case type do
          "printed" -> OrderNotifier.deliver_order_printed(order)
          _ -> OrderNotifier.deliver_order_confirmation(order)
        end

      case result do
        {:ok, _} ->
          {:noreply,
           put_flash(
             socket,
             :info,
             "Email (#{type}) renvoyé à #{order.customer_email} pour la commande ##{order.id}."
           )}

        {:error, reason} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             "Erreur lors de l'envoi de l'email : #{inspect(reason)}"
           )}
      end
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Commande introuvable.")}
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
         |> put_flash(
           :info,
           "#{count} commande(s) marquée(s) comme imprimée(s) et notification(s) email envoyée(s)."
         )
         |> refresh_all()}
    end
  end

  # --- Gestion des Catégories ---

  def handle_event("validate_category", %{"new_category" => params}, socket) do
    {:noreply, assign_new_category_form(socket, params)}
  end

  def handle_event("save_category", %{"new_category" => params}, socket) do
    case Catalog.create_category(params) do
      {:ok, category} ->
        mode_label = if Category.protected?(category), do: "privée 🔒", else: "publique"

        {:noreply,
         socket
         |> put_flash(:info, "Catégorie « #{category.name} » (#{mode_label}) créée !")
         |> refresh_categories()
         |> assign_new_category_form(%{})}

      {:error, changeset} ->
        msg =
          changeset
          |> Ecto.Changeset.traverse_errors(fn {m, _} -> m end)
          |> Enum.map(fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)
          |> Enum.join(" · ")

        {:noreply,
         socket
         |> put_flash(:error, "Impossible de créer la catégorie (#{msg}).")
         |> assign_new_category_form(params)}
    end
  end

  def handle_event(
        "update_category_password",
        %{"category_id" => raw_id, "password" => pwd},
        socket
      ) do
    with {id, ""} <- Integer.parse(raw_id),
         %Category{} = cat <- Catalog.get_category(id),
         {:ok, updated} <- Catalog.update_category(cat, %{password: pwd}) do
      status =
        if Category.protected?(updated),
          do: "protégée par mot de passe 🔒",
          else: "publique (sans mot de passe)"

      {:noreply,
       socket
       |> put_flash(:info, "Catégorie « #{updated.name} » désormais #{status}.")
       |> refresh_categories()}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Impossible de modifier la catégorie.")}
    end
  end

  def handle_event("delete_category", %{"id" => raw_id}, socket) do
    with {id, ""} <- Integer.parse(raw_id),
         %Category{} = cat <- Catalog.get_category(id) do
      case Catalog.delete_category(cat) do
        {:ok, deleted} ->
          {:noreply,
           socket
           |> put_flash(
             :info,
             "Catégorie « #{deleted.name} » supprimée (ses stickers ont été basculés en Général)."
           )
           |> refresh_categories()
           |> assign(:stickers, Catalog.list_stickers())}

        {:error, :cannot_delete_default} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             "La catégorie par défaut Général ne peut pas être supprimée."
           )}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Erreur lors de la suppression de la catégorie.")}
      end
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Catégorie introuvable.")}
    end
  end

  # --- Optimisation & Miniatures WebP ---

  def handle_event("optimize_all_uploads", _params, socket) do
    {:ok, stats} = ImageOptimizer.optimize_all_uploads()

    {:noreply,
     put_flash(
       socket,
       :info,
       "Optimisation terminée : #{stats.thumbnails_created} miniature(s) WebP générée(s), #{stats.optimized} image(s) lourde(s) compressée(s)."
     )}
  end

  # --- Gestion des Stickers ---

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
         sticker when not is_nil(sticker) <- Catalog.get_sticker(sticker_id) do
      case Catalog.delete_sticker(sticker) do
        {:ok, deleted_sticker} ->
          remove_uploaded_file(deleted_sticker.image_path)

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

  def handle_event("set_sticker_category", %{"id" => id, "category" => category_slug}, socket) do
    with {sticker_id, ""} <- Integer.parse(id),
         sticker when not is_nil(sticker) <- Catalog.get_sticker(sticker_id),
         %Category{} = cat <- Map.get(socket.assigns.categories_by_slug, category_slug),
         {:ok, updated} <- Catalog.update_sticker(sticker, %{category: cat.slug}) do
      label = category_badge_label(cat)

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

        ImageOptimizer.save_uploaded_sticker(path, filename)
      end)

    image_path = List.first(uploaded_files)

    requested_cat = params["category"] || "general"

    category =
      if Map.has_key?(socket.assigns.categories_by_slug, requested_cat) do
        requested_cat
      else
        "general"
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
          remove_uploaded_file(image_path)

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
        remove_uploaded_file(image_path)

        {:noreply,
         socket
         |> put_flash(:error, reason)
         |> assign_new_sticker_form(params)}

      _ ->
        remove_uploaded_file(image_path)

        {:noreply,
         socket
         |> put_flash(:error, "Vérifie les informations saisies (nom, prix et dimensions).")
         |> assign_new_sticker_form(params)}
    end
  end

  def format_label(format_id) do
    format = Formats.get(format_id)
    "#{Map.get(format, :short_label, format.label)} (#{format.dimensions_label})"
  end

  def status_label(:pending), do: "En attente"
  def status_label(:confirmed), do: "Confirmée"
  def status_label(:printed), do: "Imprimée"
  def status_label(:fulfilled), do: "Livrée"
  def status_label(:cancelled), do: "Annulée"
  def status_label(other), do: to_string(other)

  def category_select_options(categories) do
    Enum.map(categories, fn cat ->
      suffix = if Category.protected?(cat), do: " (protégé par code 🔒)", else: " (public)"
      {"#{cat.name}#{suffix}", cat.slug}
    end)
  end

  def category_badge_label(%Category{} = cat) do
    if Category.protected?(cat), do: "#{cat.name} 🔒", else: cat.name
  end

  def sticker_category_badge(categories_by_slug, slug) do
    case Map.get(categories_by_slug, slug) do
      %Category{} = cat -> category_badge_label(cat)
      _ -> String.capitalize(to_string(slug))
    end
  end

  def sticker_category_protected?(categories_by_slug, slug) do
    case Map.get(categories_by_slug, slug) do
      %Category{} = cat -> Category.protected?(cat)
      _ -> false
    end
  end

  defp remove_uploaded_file(image_path) when is_binary(image_path) do
    ImageOptimizer.remove_uploaded_sticker(image_path)
  end

  defp remove_uploaded_file(_), do: :ok

  defp refresh_categories(socket) do
    categories = Catalog.list_categories()

    socket
    |> assign(:categories, categories)
    |> assign(:categories_by_slug, Map.new(categories, &{&1.slug, &1}))
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

  defp assign_new_category_form(socket, params) do
    default_params = %{
      "name" => "",
      "password" => ""
    }

    form_params = Map.merge(default_params, params)
    assign(socket, :new_category_form, to_form(form_params, as: :new_category))
  end

  defp refresh_stats(socket) do
    all_orders = Orders.list_orders()
    pending_orders = Enum.filter(all_orders, &(&1.status == :pending))
    printed_orders = Enum.filter(all_orders, &(&1.status == :printed))
    fulfilled_orders = Enum.filter(all_orders, &(&1.status == :fulfilled))
    cancelled_orders = Enum.filter(all_orders, &(&1.status == :cancelled))
    pending_stickers_count = Orders.count_stickers_in_orders(pending_orders)

    socket
    |> assign(:all_orders_count, length(all_orders))
    |> assign(:pending_orders_count, length(pending_orders))
    |> assign(:printed_orders_count, length(printed_orders))
    |> assign(:fulfilled_orders_count, length(fulfilled_orders))
    |> assign(:cancelled_orders_count, length(cancelled_orders))
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
