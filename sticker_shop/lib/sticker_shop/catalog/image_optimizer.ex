defmodule StickerShop.Catalog.ImageOptimizer do
  @moduledoc """
  Optimisation et redimensionnement automatique des visuels de stickers
  pour garantir une impression 300 DPI nette tout en gardant un poids de fichier très léger.
  """

  require Logger

  # 1200 px correspond à 508 DPI pour un sticker standard 6×6 cm, et >300 DPI pour du 10×10 cm.
  @max_dimension_px 1200

  @doc """
  Optimise un fichier image source vers le chemin cible.
  - SVG : conservé intact (vectoriel pur, 0 perte, poids plume).
  - PNG / JPG / WebP : redimensionné proportionnellement si > 1200 px avec rééchantillonnage
    haute fidélité (Lanczos3), suppression des métadonnées superflues et compression maximale.
  """
  def optimize(source_path, target_path, opts \\ []) do
    ext = Path.extname(target_path) |> String.downcase()
    max_dim = Keyword.get(opts, :max_dimension, @max_dimension_px)

    case ext do
      ".svg" ->
        File.cp!(source_path, target_path)
        {:ok, target_path}

      ext when ext in ~w(.png .jpg .jpeg .webp) ->
        case Image.open(source_path) do
          {:ok, img} ->
            {w, h, _bands} = Image.shape(img)
            max_side = max(w, h)

            img_to_write =
              if max_side > max_dim do
                case Image.thumbnail(img, max_dim) do
                  {:ok, resized} -> resized
                  _ -> img
                end
              else
                img
              end

            write_opts =
              case ext do
                ".png" -> [compression: 9, strip_metadata: true]
                ext when ext in ~w(.jpg .jpeg) -> [quality: 90, strip_metadata: true]
                ".webp" -> [quality: 90, strip_metadata: true]
              end

            case Image.write(img_to_write, target_path, write_opts) do
              {:ok, _} ->
                {:ok, target_path}

              {:error, reason} ->
                Logger.warning("Échec de compression Image, copie directe : #{inspect(reason)}")
                File.cp!(source_path, target_path)
                {:ok, target_path}
            end

          {:error, reason} ->
            Logger.warning(
              "Impossible d'ouvrir l'image avec Image : #{inspect(reason)}, copie brute."
            )

            File.cp!(source_path, target_path)
            {:ok, target_path}
        end

      _ ->
        File.cp!(source_path, target_path)
        {:ok, target_path}
    end
  end

  @doc """
  Optimise rétroactivement tous les stickers du catalogue stockés dans `/uploads/stickers/`.
  """
  def optimize_all_uploads do
    uploads_dir = Path.expand("priv/static/uploads/stickers")
    build_dir = Path.join([:code.priv_dir(:sticker_shop), "static", "uploads", "stickers"])

    case File.ls(uploads_dir) do
      {:ok, files} ->
        for filename <- files,
            ext = Path.extname(filename) |> String.downcase(),
            ext in ~w(.png .jpg .jpeg .webp),
            not String.ends_with?(filename, ".gitkeep") do
          source_file = Path.join(uploads_dir, filename)

          if File.regular?(source_file) and File.stat!(source_file).size > 200_000 do
            temp_target = Path.join(System.tmp_dir!(), "opt_#{filename}")

            case optimize(source_file, temp_target) do
              {:ok, ^temp_target} ->
                File.cp!(temp_target, source_file)

                if File.dir?(build_dir) do
                  File.cp!(temp_target, Path.join(build_dir, filename))
                end

                File.rm(temp_target)
                Logger.info("Image optimisée avec succès : #{filename}")

              _ ->
                :ok
            end
          end
        end

      _ ->
        :ok
    end
  end
end
