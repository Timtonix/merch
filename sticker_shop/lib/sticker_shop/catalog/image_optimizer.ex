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
  Vérifie qu'un fichier existe sur le disque et n'est pas vide (`size > 0`).
  """
  def valid_file?(path) when is_binary(path) do
    case File.stat(path) do
      {:ok, %File.Stat{type: :regular, size: size}} when size > 0 -> true
      _ -> false
    end
  end

  @doc """
  Retourne la liste des répertoires physiques d'uploads (dédupliqués par inode pour éviter
  d'écraser un fichier sur lui-même lorsque des symlinks pointent vers le même dossier en prod).
  Le premier répertoire retourné est toujours celui servi par `Plug.Static`.
  """
  def storage_dirs do
    priv_dir = Path.join([:code.priv_dir(:sticker_shop), "static", "uploads", "stickers"])

    candidates =
      [
        priv_dir,
        if(File.dir?("/app/uploads"), do: "/app/uploads/stickers", else: nil),
        if(File.dir?("/app/priv/static"), do: "/app/priv/static/uploads/stickers", else: nil),
        if(File.dir?("priv/static"), do: Path.expand("priv/static/uploads/stickers"), else: nil)
      ]
      |> Enum.reject(&is_nil/1)

    Enum.each(candidates, fn dir ->
      _ = File.mkdir_p(dir)
    end)

    candidates
    |> Enum.filter(&File.dir?/1)
    |> Enum.uniq_by(fn dir ->
      case File.stat(dir) do
        {:ok, %File.Stat{inode: inode, major_device: dev}} when inode != 0 ->
          {:inode, dev, inode}

        _ ->
          {:path, Path.expand(dir)}
      end
    end)
  end

  @doc """
  Vérifie si la miniature WebP existe dans le dossier servi par `Plug.Static`
  (ou la synchronise depuis un autre dossier de stockage si disponible).
  """
  def thumbnail_exists?(thumb_filename) when is_binary(thumb_filename) do
    priv_thumb =
      Path.join([:code.priv_dir(:sticker_shop), "static", "uploads", "stickers", thumb_filename])

    if valid_file?(priv_thumb) do
      true
    else
      case Enum.find(storage_dirs(), &valid_file?(Path.join(&1, thumb_filename))) do
        nil ->
          false

        source_dir ->
          _ = File.mkdir_p(Path.dirname(priv_thumb))
          _ = File.cp(Path.join(source_dir, thumb_filename), priv_thumb)
          valid_file?(priv_thumb)
      end
    end
  end

  @doc """
  Sauvegarde un sticker nouvellement téléversé, l'optimise, génère sa miniature WebP
  et synchronise les fichiers vers tous les dossiers physiques de stockage.
  """
  def save_uploaded_sticker(temp_source_path, filename) do
    dirs = storage_dirs()
    primary_dir = hd(dirs)
    primary_target = Path.join(primary_dir, filename)

    optimize(temp_source_path, primary_target)

    thumb_name = thumbnail_filename(filename)
    primary_thumb = Path.join(primary_dir, thumb_name)

    for extra_dir <- tl(dirs) do
      _ = File.cp(primary_target, Path.join(extra_dir, filename))

      if valid_file?(primary_thumb) do
        _ = File.cp(primary_thumb, Path.join(extra_dir, thumb_name))
      end
    end

    {:ok, "/uploads/stickers/#{filename}"}
  end

  @doc """
  Supprime un sticker et sa miniature WebP de tous les dossiers physiques de stockage.
  """
  def remove_uploaded_sticker(image_path) when is_binary(image_path) do
    if String.starts_with?(image_path, "/uploads/stickers/") do
      filename = Path.basename(image_path)
      thumb_name = thumbnail_filename(filename)

      for dir <- storage_dirs() do
        _ = File.rm(Path.join(dir, filename))
        _ = File.rm(Path.join(dir, thumb_name))
      end
    end

    :ok
  end

  def remove_uploaded_sticker(_), do: :ok

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
  et génère les miniatures WebP (`thumb_<nom>.webp`) manquantes ou vides (0 octet).
  Fonctionne quel que soit le répertoire courant (`WORKDIR` ou `/app/bin`).
  """
  def optimize_all_uploads do
    dirs = storage_dirs()
    primary_dir = hd(dirs)

    # Rassemble tous les fichiers sources présents dans l'un quelconque des dossiers de stockage
    all_raster_filenames =
      dirs
      |> Enum.flat_map(fn dir ->
        case File.ls(dir) do
          {:ok, files} -> files
          _ -> []
        end
      end)
      |> Enum.uniq()
      |> Enum.filter(fn filename ->
        ext = Path.extname(filename) |> String.downcase()

        ext in ~w(.png .jpg .jpeg .webp) and
          not String.starts_with?(filename, "thumb_") and
          not String.ends_with?(filename, ".gitkeep")
      end)

    stats =
      Enum.reduce(all_raster_filenames, %{thumbnails_created: 0, optimized: 0}, fn filename,
                                                                                   acc ->
        # Trouve le dossier contenant une version valide du fichier original
        source_dir = Enum.find(dirs, &valid_file?(Path.join(&1, filename)))

        if is_nil(source_dir) do
          acc
        else
          source_file = Path.join(source_dir, filename)
          primary_file = Path.join(primary_dir, filename)

          # S'assure que le fichier original est présent dans primary_dir (servi par Plug.Static)
          if not valid_file?(primary_file) do
            _ = File.cp(source_file, primary_file)
          end

          # 1. Optimisation de l'image originale si elle est lourde (> 250 Ko)
          acc =
            if valid_file?(primary_file) and File.stat!(primary_file).size > 250_000 do
              temp_target = Path.join(System.tmp_dir!(), "opt_#{filename}")

              case optimize(primary_file, temp_target, generate_thumbnail: false) do
                {:ok, ^temp_target} ->
                  for dir <- dirs do
                    _ = File.cp(temp_target, Path.join(dir, filename))
                  end

                  _ = File.rm(temp_target)
                  Logger.info("[ImageOptimizer] Image originale optimisée : #{filename}")
                  %{acc | optimized: acc.optimized + 1}

                _ ->
                  _ = File.rm(temp_target)
                  acc
              end
            else
              acc
            end

          # 2. Génération de la miniature WebP si absente ou de taille 0
          thumb_name = thumbnail_filename(filename)
          primary_thumb = Path.join(primary_dir, thumb_name)

          acc =
            if not valid_file?(primary_thumb) do
              case generate_thumbnail(primary_file, primary_thumb) do
                {:ok, ^primary_thumb} ->
                  for extra_dir <- tl(dirs) do
                    _ = File.cp(primary_thumb, Path.join(extra_dir, thumb_name))
                  end

                  Logger.info("[ImageOptimizer] Miniature WebP générée : #{thumb_name}")
                  %{acc | thumbnails_created: acc.thumbnails_created + 1}

                _ ->
                  _ = File.rm(primary_thumb)
                  acc
              end
            else
              for extra_dir <- tl(dirs) do
                extra_thumb = Path.join(extra_dir, thumb_name)
                if not valid_file?(extra_thumb), do: _ = File.cp(primary_thumb, extra_thumb)
              end

              acc
            end

          acc
        end
      end)

    {:ok, stats}
  end
end
