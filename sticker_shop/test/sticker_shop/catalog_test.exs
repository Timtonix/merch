defmodule StickerShop.CatalogTest do
  use StickerShop.DataCase, async: true

  alias StickerShop.Catalog
  alias StickerShop.Catalog.Sticker

  describe "stickers" do
    @valid_attrs %{
      name: "Logo hex",
      unit_price_cents: 350,
      image_path: "priv/stickers/logo-hex.png",
      width_mm: 50,
      height_mm: 50,
      active: true
    }

    test "create_sticker/1 with valid data creates a sticker" do
      assert {:ok, %Sticker{} = sticker} = Catalog.create_sticker(@valid_attrs)
      assert sticker.name == "Logo hex"
      assert sticker.unit_price_cents == 350
      assert sticker.image_path == "priv/stickers/logo-hex.png"
      assert sticker.width_mm == 50
      assert sticker.height_mm == 50
      assert sticker.active
    end

    test "create_sticker/1 rejects missing fields and non-positive prices" do
      assert {:error, changeset} = Catalog.create_sticker(%{})

      assert %{name: _, unit_price_cents: _, image_path: _, width_mm: _, height_mm: _} =
               errors_on(changeset)

      assert {:error, changeset} =
               Catalog.create_sticker(Map.put(@valid_attrs, :unit_price_cents, 0))

      assert "must be greater than 0" in errors_on(changeset).unit_price_cents
    end

    test "list_active_stickers/0 hides inactive stickers" do
      {:ok, active} = Catalog.create_sticker(@valid_attrs)

      {:ok, _inactive} =
        Catalog.create_sticker(Map.merge(@valid_attrs, %{name: "Old", active: false}))

      assert Catalog.list_active_stickers() == [active]
    end

    test "format_price_cents/1 formats euro amounts" do
      assert Catalog.format_price_cents(0) == "0,00 €"
      assert Catalog.format_price_cents(350) == "3,50 €"
      assert Catalog.format_price_cents(1000) == "10,00 €"
    end

    test "update_sticker/2 updates the sticker" do
      {:ok, sticker} = Catalog.create_sticker(@valid_attrs)
      assert {:ok, updated} = Catalog.update_sticker(sticker, %{unit_price_cents: 400})
      assert updated.unit_price_cents == 400
    end

    test "toggle_sticker_active/1 flips the active flag" do
      {:ok, sticker} = Catalog.create_sticker(@valid_attrs)
      assert sticker.active == true

      {:ok, disabled} = Catalog.toggle_sticker_active(sticker)
      assert disabled.active == false

      {:ok, reenabled} = Catalog.toggle_sticker_active(disabled)
      assert reenabled.active == true
    end

    test "delete_sticker/1 removes the sticker" do
      {:ok, sticker} = Catalog.create_sticker(@valid_attrs)
      assert {:ok, _} = Catalog.delete_sticker(sticker)
      assert Catalog.get_sticker(sticker.id) == nil
    end

    test "supports category assignment and filtering" do
      {:ok, general} =
        Catalog.create_sticker(
          Map.merge(@valid_attrs, %{name: "Général Sticker", category: "general"})
        )

      {:ok, bicus} =
        Catalog.create_sticker(
          Map.merge(@valid_attrs, %{name: "Bicus Sticker", category: "bicus"})
        )

      all_active = Catalog.list_active_stickers()
      assert general in all_active
      assert bicus in all_active

      general_only = Catalog.list_active_stickers(category: "general")
      assert general in general_only
      refute bicus in general_only

      bicus_only = Catalog.list_active_stickers(category: "bicus")
      assert bicus in bicus_only
      refute general in bicus_only

      categories = Catalog.list_categories()
      assert "general" in categories
      assert "bicus" in categories
    end
  end

  describe "formats" do
    alias StickerShop.Catalog.Formats

    test "calculates correct price according to base price and format" do
      # Base 20c (classique)
      assert Formats.price_for(20, "standard_6x6") == 20
      assert Formats.price_for(20, "medium_10x10") == 50
      assert Formats.price_for(20, "large_14x14") == 100
      assert Formats.price_for(20, "poster_a4") == 250

      # Base 30c (shiny)
      assert Formats.price_for(30, "standard_6x6") == 30
      assert Formats.price_for(30, "medium_10x10") == 70
      assert Formats.price_for(30, "large_14x14") == 130
      assert Formats.price_for(30, "poster_a4") == 250
    end
  end

  describe "image_optimizer" do
    alias StickerShop.Catalog.ImageOptimizer

    test "optimizes a large PNG down to max dimensions" do
      tmp_src = Path.join(System.tmp_dir!(), "test_large.png")
      tmp_dst = Path.join(System.tmp_dir!(), "test_optimized.png")

      # Crée une image 2000x2000
      {:ok, img} = Image.new(2000, 2000, color: :blue)
      Image.write(img, tmp_src)

      assert {:ok, ^tmp_dst} = ImageOptimizer.optimize(tmp_src, tmp_dst, max_dimension: 800)
      assert File.exists?(tmp_dst)

      {:ok, opt_img} = Image.open(tmp_dst)
      {w, h, _} = Image.shape(opt_img)
      assert w <= 800
      assert h <= 800

      File.rm(tmp_src)
      File.rm(tmp_dst)
    end

    test "preserves SVG files without modification" do
      tmp_svg_src = Path.join(System.tmp_dir!(), "test.svg")
      tmp_svg_dst = Path.join(System.tmp_dir!(), "test_out.svg")

      File.write!(tmp_svg_src, "<svg viewBox='0 0 10 10'><circle cx='5' cy='5' r='5'/></svg>")
      assert {:ok, ^tmp_svg_dst} = ImageOptimizer.optimize(tmp_svg_src, tmp_svg_dst)
      assert File.read!(tmp_svg_dst) == File.read!(tmp_svg_src)

      File.rm(tmp_svg_src)
      File.rm(tmp_svg_dst)
    end
  end
end
