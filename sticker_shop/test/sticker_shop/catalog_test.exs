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
  end
end
