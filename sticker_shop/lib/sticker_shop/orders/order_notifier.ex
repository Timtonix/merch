defmodule StickerShop.Orders.OrderNotifier do
  @moduledoc """
  Envoi des emails transactionnels liés aux commandes :
  1. Récapitulatif automatique de commande + moyens de paiement possibles (Cash, Wero, RIB sur demande).
  2. Notification lorsque les stickers ont été imprimés et sont prêts à être récupérés.
  """

  import Swoosh.Email
  require Logger

  alias StickerShop.Catalog
  alias StickerShop.Catalog.Formats
  alias StickerShop.Mailer
  alias StickerShop.Orders.Order
  alias StickerShop.Repo

  @default_pickup_instructions "Tes stickers sont prêts à l'atelier ! Contacte-moi ou passe me voir pour les récupérer."

  @doc """
  Retourne les informations configurées pour le paiement et la récupération.
  """
  def config_info do
    configured = Application.get_env(:sticker_shop, :order_notifications, [])

    %{
      from_name:
        Keyword.get(configured, :from_name) ||
          System.get_env("MAILER_FROM_NAME") ||
          "Atelier Stickers",
      from_email:
        Keyword.get(configured, :from_email) ||
          System.get_env("MAILER_FROM_EMAIL") ||
          "commandes@stickers.local",
      reply_to:
        Keyword.get(configured, :reply_to) ||
          System.get_env("MAILER_REPLY_TO"),
      wero_phone:
        Keyword.get(configured, :wero_phone) ||
          System.get_env("PAYMENT_WERO_PHONE"),
      pickup_instructions:
        Keyword.get(configured, :pickup_instructions) ||
          System.get_env("PICKUP_INSTRUCTIONS") ||
          @default_pickup_instructions
    }
  end

  @doc """
  Envoie l'email automatique de récapitulatif de commande avec les moyens de paiement possibles.
  """
  def deliver_order_confirmation(%Order{} = order) do
    order = Repo.preload(order, order_items: :sticker)
    info = config_info()

    email =
      new()
      |> to({order.customer_name, order.customer_email})
      |> from({info.from_name, info.from_email})
      |> maybe_put_reply_to(info.reply_to)
      |> subject("Récapitulatif de ta commande ##{order.id} · Stickers")
      |> html_body(confirmation_html(order, info))
      |> text_body(confirmation_text(order, info))

    deliver_safely(email, "confirmation commande ##{order.id}")
  end

  @doc """
  Envoie l'email automatique lorsque les stickers de la commande ont été imprimés.
  """
  def deliver_order_printed(%Order{} = order) do
    order = Repo.preload(order, order_items: :sticker)
    info = config_info()

    email =
      new()
      |> to({order.customer_name, order.customer_email})
      |> from({info.from_name, info.from_email})
      |> maybe_put_reply_to(info.reply_to)
      |> subject("Tes stickers sont imprimés ! (Commande ##{order.id})")
      |> html_body(printed_html(order, info))
      |> text_body(printed_text(order, info))

    deliver_safely(email, "impression commande ##{order.id}")
  end

  defp maybe_put_reply_to(email, nil), do: email
  defp maybe_put_reply_to(email, ""), do: email
  defp maybe_put_reply_to(email, reply_to), do: reply_to(email, reply_to)

  defp deliver_safely(email, context) do
    case Mailer.deliver(email) do
      {:ok, metadata} ->
        {:ok, metadata}

      {:error, reason} ->
        Logger.error("Échec d'envoi de l'email (#{context}) : #{inspect(reason)}")
        {:error, reason}
    end
  rescue
    exception ->
      Logger.error("Exception lors de l'envoi de l'email (#{context}) : #{inspect(exception)}")
      {:error, exception}
  end

  defp confirmation_html(order, info) do
    total_formatted = Catalog.format_price_cents(order.total_cents)
    items_html = render_items_rows_html(order.order_items)

    wero_detail =
      if is_binary(info.wero_phone) and String.trim(info.wero_phone) != "" do
        "au <strong>#{escape_html(info.wero_phone)}</strong>"
      else
        "via numéro de téléphone"
      end

    notes_section =
      if is_binary(order.notes) and String.trim(order.notes) != "" do
        """
        <div style="margin-top: 16px; padding: 12px 16px; background-color: #f4f4f5; border-radius: 12px; font-size: 13px; color: #3f3f46;">
          <strong>Ta note / préférence :</strong> #{escape_html(order.notes)}
        </div>
        """
      else
        ""
      end

    """
    <!DOCTYPE html>
    <html lang="fr">
    <head>
      <meta charset="utf-8">
      <title>Commande ##{order.id}</title>
    </head>
    <body style="margin: 0; padding: 24px 12px; background-color: #f4f4f5; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; color: #18181b;">
      <div style="max-width: 600px; margin: 0 auto; background-color: #ffffff; border-radius: 20px; overflow: hidden; border: 1px solid #e4e4e7;">
        <div style="background-color: #18181b; color: #ffffff; padding: 24px 28px;">
          <p style="margin: 0; font-size: 11px; text-transform: uppercase; letter-spacing: 0.15em; color: #a1a1aa;">
            Atelier Stickers · Confirmation
          </p>
          <h1 style="margin: 6px 0 0 0; font-size: 22px; font-weight: 700;">
            Merci #{escape_html(order.customer_name)} !
          </h1>
          <p style="margin: 6px 0 0 0; font-size: 14px; color: #d4d4d8;">
            Ta commande <strong>##{order.id}</strong> est bien enregistrée.
          </p>
        </div>

        <div style="padding: 24px 28px;">
          <h2 style="margin: 0 0 12px 0; font-size: 15px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.05em; color: #52525b;">
            Récapitulatif de ta commande
          </h2>

          <table style="width: 100%; border-collapse: collapse; font-size: 14px;">
            <thead>
              <tr style="border-bottom: 1px solid #e4e4e7; text-align: left; color: #71717a; font-size: 12px;">
                <th style="padding: 8px 0;">Sticker & Format</th>
                <th style="padding: 8px 8px; text-align: center;">Qté</th>
                <th style="padding: 8px 0; text-align: right;">Total</th>
              </tr>
            </thead>
            <tbody>
              #{items_html}
            </tbody>
            <tfoot>
              <tr>
                <td colspan="2" style="padding: 14px 0 4px 0; font-weight: 700; font-size: 16px;">Total à régler</td>
                <td style="padding: 14px 0 4px 0; font-weight: 800; font-size: 18px; text-align: right; color: #18181b;">#{total_formatted}</td>
              </tr>
            </tfoot>
          </table>

          #{notes_section}

          <div style="margin-top: 24px; padding: 18px 20px; background-color: #fafafa; border: 1px solid #e4e4e7; border-radius: 16px;">
            <h3 style="margin: 0 0 10px 0; font-size: 15px; font-weight: 700; color: #18181b;">
              💳 Moyens de paiement possibles
            </h3>
            <p style="margin: 0 0 12px 0; font-size: 13px; color: #52525b; line-height: 1.5;">
              Pour régler ta commande de <strong>#{total_formatted}</strong>, tu peux utiliser l'un des moyens suivants (n'oublie pas d'indiquer <strong>Commande ##{order.id}</strong>) :
            </p>
            <ul style="margin: 0; padding-left: 18px; font-size: 13px; color: #27272a; line-height: 1.7;">
              <li><strong>Espèces (Cash) :</strong> directement lors de la remise en main propre des stickers.</li>
              <li><strong>Wero :</strong> paiement mobile instantané #{wero_detail}.</li>
              <li><strong>Virement bancaire (RIB) :</strong> sur demande — je t'envoie mon RIB directement (il suffit de répondre à ce mail ou de me le demander).</li>
            </ul>
          </div>

          <p style="margin: 20px 0 0 0; font-size: 13px; color: #71717a; line-height: 1.5;">
            🖨️ Tu recevras un nouveau mail dès que tes stickers auront été imprimés et seront prêts à être récupérés !
          </p>
        </div>
      </div>
    </body>
    </html>
    """
  end

  defp confirmation_text(order, info) do
    total_formatted = Catalog.format_price_cents(order.total_cents)
    items_text = render_items_text(order.order_items)

    wero_detail =
      if is_binary(info.wero_phone) and String.trim(info.wero_phone) != "" do
        " (#{info.wero_phone})"
      else
        ""
      end

    notes_text =
      if is_binary(order.notes) and String.trim(order.notes) != "" do
        "\nTa note / préférence : #{order.notes}\n"
      else
        ""
      end

    """
    Bonjour #{order.customer_name},

    Merci pour ta commande ##{order.id} ! Elle a bien été enregistrée et transmise à l'atelier.

    RÉCAPITULATIF DE TA COMMANDE ##{order.id}
    ----------------------------------------
    #{items_text}
    ----------------------------------------
    TOTAL À RÉGLER : #{total_formatted}
    #{notes_text}
    MOYENS DE PAIEMENT POSSIBLES :
    - Espèces (Cash) : directement lors de la remise en main propre des stickers.
    - Wero : paiement mobile instantané#{wero_detail} (indique "Commande ##{order.id}").
    - Virement bancaire (RIB) : sur demande, je t'envoie mon RIB moi-même (réponds simplement à ce mail).

    Tu recevras un second email dès que tes stickers seront imprimés !
    """
  end

  defp printed_html(order, info) do
    total_formatted = Catalog.format_price_cents(order.total_cents)
    items_html = render_items_rows_html(order.order_items)

    wero_detail =
      if is_binary(info.wero_phone) and String.trim(info.wero_phone) != "" do
        "au <strong>#{escape_html(info.wero_phone)}</strong>"
      else
        "via numéro de téléphone"
      end

    """
    <!DOCTYPE html>
    <html lang="fr">
    <head>
      <meta charset="utf-8">
      <title>Tes stickers sont imprimés ! Commande ##{order.id}</title>
    </head>
    <body style="margin: 0; padding: 24px 12px; background-color: #f4f4f5; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; color: #18181b;">
      <div style="max-width: 600px; margin: 0 auto; background-color: #ffffff; border-radius: 20px; overflow: hidden; border: 1px solid #e4e4e7;">
        <div style="background-color: #065f46; color: #ffffff; padding: 24px 28px;">
          <p style="margin: 0; font-size: 11px; text-transform: uppercase; letter-spacing: 0.15em; color: #a7f3d0;">
            Atelier Stickers · Impression terminée
          </p>
          <h1 style="margin: 6px 0 0 0; font-size: 22px; font-weight: 700;">
            Tes stickers sont imprimés ! 🎉
          </h1>
          <p style="margin: 6px 0 0 0; font-size: 14px; color: #d1fae5;">
            Commande <strong>##{order.id}</strong> pour #{escape_html(order.customer_name)}
          </p>
        </div>

        <div style="padding: 24px 28px;">
          <div style="margin-bottom: 22px; padding: 16px 18px; background-color: #ecfdf5; border: 1px solid #a7f3d0; border-radius: 14px; color: #065f46; font-size: 14px; line-height: 1.5;">
            <strong>Bonne nouvelle !</strong><br>
            #{escape_html(info.pickup_instructions)}
          </div>

          <h2 style="margin: 0 0 12px 0; font-size: 14px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.05em; color: #52525b;">
            Contenu de ta commande ##{order.id}
          </h2>

          <table style="width: 100%; border-collapse: collapse; font-size: 14px;">
            <thead>
              <tr style="border-bottom: 1px solid #e4e4e7; text-align: left; color: #71717a; font-size: 12px;">
                <th style="padding: 8px 0;">Sticker & Format</th>
                <th style="padding: 8px 8px; text-align: center;">Qté</th>
                <th style="padding: 8px 0; text-align: right;">Total</th>
              </tr>
            </thead>
            <tbody>
              #{items_html}
            </tbody>
            <tfoot>
              <tr>
                <td colspan="2" style="padding: 14px 0 4px 0; font-weight: 700; font-size: 15px;">Montant total</td>
                <td style="padding: 14px 0 4px 0; font-weight: 800; font-size: 17px; text-align: right; color: #18181b;">#{total_formatted}</td>
              </tr>
            </tfoot>
          </table>

          <div style="margin-top: 22px; padding: 16px 18px; background-color: #fafafa; border: 1px solid #e4e4e7; border-radius: 14px; font-size: 13px; color: #3f3f46; line-height: 1.6;">
            <strong>Rappel des moyens de paiement (si ce n'est pas déjà réglé) :</strong>
            <ul style="margin: 6px 0 0 0; padding-left: 18px;">
              <li><strong>Espèces (Cash) :</strong> lors de la remise en main propre.</li>
              <li><strong>Wero :</strong> paiement mobile #{wero_detail}.</li>
              <li><strong>Virement (RIB) :</strong> sur demande (je te l'envoie moi-même).</li>
            </ul>
          </div>
        </div>
      </div>
    </body>
    </html>
    """
  end

  defp printed_text(order, info) do
    total_formatted = Catalog.format_price_cents(order.total_cents)
    items_text = render_items_text(order.order_items)

    """
    Bonjour #{order.customer_name},

    Bonne nouvelle : les stickers de ta commande ##{order.id} ont été imprimés !

    #{info.pickup_instructions}

    RAPPEL DE TA COMMANDE ##{order.id}
    ----------------------------------------
    #{items_text}
    ----------------------------------------
    TOTAL : #{total_formatted}

    Rappel paiement (si pas encore réglé) :
    - Espèces (Cash) à la remise en main propre
    - Wero
    - Virement (RIB envoyé sur demande)

    À très vite !
    """
  end

  defp render_items_rows_html(order_items) do
    Enum.map_join(order_items, "\n", fn item ->
      format = Formats.get(item.format || Formats.default_id())
      sticker_name = if item.sticker, do: item.sticker.name, else: "Sticker"
      unit_price = Catalog.format_price_cents(item.unit_price_cents)
      line_total = Catalog.format_price_cents(item.quantity * item.unit_price_cents)

      """
      <tr style="border-bottom: 1px solid #f4f4f5;">
        <td style="padding: 10px 0;">
          <div style="font-weight: 600; color: #18181b;">#{escape_html(sticker_name)}</div>
          <div style="font-size: 12px; color: #71717a;">#{escape_html(format.label)} (#{escape_html(format.dimensions_label)}) · #{unit_price} / u</div>
        </td>
        <td style="padding: 10px 8px; text-align: center; font-weight: 600; color: #3f3f46;">
          ×#{item.quantity}
        </td>
        <td style="padding: 10px 0; text-align: right; font-weight: 700; color: #18181b;">
          #{line_total}
        </td>
      </tr>
      """
    end)
  end

  defp render_items_text(order_items) do
    Enum.map_join(order_items, "\n", fn item ->
      format = Formats.get(item.format || Formats.default_id())
      sticker_name = if item.sticker, do: item.sticker.name, else: "Sticker"
      unit_price = Catalog.format_price_cents(item.unit_price_cents)
      line_total = Catalog.format_price_cents(item.quantity * item.unit_price_cents)

      "- #{item.quantity}x #{sticker_name} [#{format.label} #{format.dimensions_label}] (#{unit_price}/u) = #{line_total}"
    end)
  end

  defp escape_html(nil), do: ""

  defp escape_html(text) when is_binary(text) do
    text
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end
end
