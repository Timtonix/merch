defmodule StickerShopWeb.Admin.PrintSheetHTML do
  @moduledoc """
  Composants et templates pour le rendu des planches d'imposition d'impression A4.
  """
  use StickerShopWeb, :html

  embed_templates "print_sheet_html/*"
end
