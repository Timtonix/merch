defmodule StickerShop.Catalog.ImageOptimizer do
  @moduledoc """
  Optimisation et redimensionnement automatique des visuels de stickers :
  - Image haute résolution (max 1200 px, 300+ DPI) conservée pour les planches d'impression A4 et le zoom Lightbox.
  - Miniature WebP ultra-légère (`thumb_<nom>.webp`, max 360 px, ~10-25 Ko) générée pour un chargement instantané de la boutique.
  """

  require Logger

  # 1200 px correspond à 508 DPI pour un sticker standard 6×6 cm, et >300 DPI pour du 10×10 cm.
  @max_dimension_px 1200
  # 360 px couvre un affichage Retina 2x impeccable dans les cartes de la galerie (max-h-32 = 128px CSS).
  @thumbnail_dimension_px 360

  @doc """
  Retourne le nom du fichier miniature WebP correspondant à un nom de fichier d'image.
  Ex: `"sticker_123.png"` -> `"thumb_sticker_123.webp"`
  """
  def thumbnail_filename(filename) when is_binary(filename) do
    root = filename |> Path.basename() |> Path.rootname()
    "thumb_#{root}.webp"
  end

  @doc """
  Génère une miniature WebP légère (~360x360 px max, qualité 82, sans métadonnées)
  à partir d'un fichier image source vers `thumb_path`.
  """
  def generate_thumbnail(source_path, thumb_path, opts \\ []) do
    ext = Path.extname(source_path) |> String.downcase()
    thumb_dim = Keyword.get(opts, :max_dimension, @thumbnail_dimension_px)

    if ext in ~w(.png .jpg .jpeg .webp) do
      case Image.open(source_path) do
        {:ok, img} ->
          {w, h, _bands} = Image.shape(img)
          max_side = max(w, h)

          thumb_img =
            if max_side > thumb_dim do
              case Image.thumbnail(img, thumb_dim) do
                {:ok, resized} -> resized
                _ -> img
              end
            else
              img
            end

          case Image.write(thumb_img, thumb_path, quality: 82, strip_metadata: true) do
            {:ok, _} ->
              {:ok, thumb_path}

            {:error, reason} ->
              Logger.warning(
                "Échec d'écriture miniature WebP (#{thumb_path}) : #{inspect(reason)}"
              )

              {:error, reason}
          end

        {:error, reason} ->
          Logger.warning(
            "Impossible d'ouvrir l'image pour miniature (#{source_path}) : #{inspect(reason)}"
          )

          {:error, reason}
      end
    else
      {:skip, :not_raster}
    end
  end

  @doc """
  Optimise un fichier image source vers le chemin cible ET génère sa miniature WebP
  dans le même dossier si c'est une image matricielle (PNG, JPG, WebP).
  - SVG : conservé intact (vectoriel pur, 0 perte, poids plume).
  - PNG / JPG / WebP : redimensionné proportionnellement si > 1200 px avec rééchantillonnage
    haute fidélité (Lanczos3), suppression des métadonnées superflues et compression maximale.
  """
  def optimize(source_path, target_path, opts \\ []) do
    ext = Path.extname(target_path) |> String.downcase()
    max_dim = Keyword.get(opts, :max_dimension, @max_dimension_px)

    result =
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

    # Génère également la miniature WebP dans le même dossier que target_path
    if ext in ~w(.png .jpg .jpeg .webp) and Keyword.get(opts, :generate_thumbnail, true) do
      target_dir = Path.dirname(target_path)
      thumb_path = Path.join(target_dir, thumbnail_filename(target_path))
      _ = generate_thumbnail(target_path, thumb_path)
    end

    result
  end

  @doc """
  Optimise rétroactivement tous les stickers du catalogue stockés dans `/uploads/stickers/`
  et génère les miniatures WebP (`thumb_<nom>.webp`) manquantes.
  Idempotent : ne régénère que les miniatures absentes et n'optimise que les originaux > 250 Ko.
  """
  def optimize_all_uploads do
    uploads_dir = Path.expand("priv/static/uploads/stickers")
    build_dir = Path.join([:code.priv_dir(:sticker_shop), "static", "uploads", "stickers"])

    # En production ou dev, on s'assure que les deux dossiers existent
    File.mkdir_p!(uploads_dir)
    if File.dir?(Path.dirname(build_dir)), do: File.mkdir_p!(build_dir)

    case File.ls(uploads_dir) do
      {:ok, files} ->
        raster_files =
          Enum.filter(files, fn filename ->
            ext = Path.extname(filename) |> String.downcase()

            ext in ~w(.png .jpg .jpeg .webp) and
              not String.starts_with?(filename, "thumb_") and
              not String.ends_with?(filename, ".gitkeep")
          end)

        stats =
          Enum.reduce(raster_files, %{thumbnails_created: 0, optimized: 0}, fn filename, acc ->
            source_file = Path.join(uploads_dir, filename)
            thumb_name = thumbnail_filename(filename)
            thumb_file = Path.join(uploads_dir, thumb_name)
            build_thumb_file = Path.join(build_dir, thumb_name)

            # 1. Optimisation de l'image originale si elle est très lourde (> 250 Ko)
            acc =
              if File.regular?(source_file) and File.stat!(source_file).size > 250_000 do
                temp_target = Path.join(System.tmp_dir!(), "opt_#{filename}")

                case optimize(source_file, temp_target, generate_thumbnail: false) do
                  {:ok, ^temp_target} ->
                    File.cp!(temp_target, source_file)

                    if File.dir?(build_dir) and Path.expand(build_dir) != uploads_dir do
                      File.cp!(temp_target, Path.join(build_dir, filename))
                    end

                    File.rm(temp_target)
                    Logger.info("[ImageOptimizer] Image originale optimisée : #{filename}")
                    %{acc | optimized: acc.optimized + 1}

                  _ ->
                    acc
                end
              else
                acc
              end

            # 2. Génération de la miniature WebP si absente
            acc =
              if File.regular?(source_file) and not File.regular?(thumb_file) do
                case generate_thumbnail(source_file, thumb_file) do
                  {:ok, ^thumb_file} ->
                    if File.dir?(build_dir) and Path.expand(build_dir) != uploads_dir do
                      File.cp!(thumb_file, build_thumb_file)
                    end

                    Logger.info("[ImageOptimizer] Miniature WebP générée : #{thumb_name}")
                    %{acc | thumbnails_created: acc.thumbnails_created + 1}

                  _ ->
                    acc
                end
              else
                # Si la miniature existe dans source_dir mais pas encore dans build_dir
                if File.regular?(thumb_file) and File.dir?(build_dir) and
                     Path.expand(build_dir) != uploads_dir and not File.regular?(build_thumb_file) do
                  File.cp!(thumb_file, build_thumb_file)
                end

                acc
              end

            acc
          end)

        {:ok, stats}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
