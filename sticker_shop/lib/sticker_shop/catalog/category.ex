defmodule StickerShop.Catalog.Category do
  @moduledoc """
  A category for organizing stickers in the shop.
  Can be public (`password` is `nil` or empty) or password-protected (`password` is a non-empty string).
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "categories" do
    field :slug, :string
    field :name, :string
    field :password, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(category, attrs) do
    category
    |> cast(attrs, [:slug, :name, :password])
    |> normalize_fields()
    |> validate_required([:name, :slug])
    |> validate_length(:name, min: 1, max: 60)
    |> validate_length(:slug, min: 1, max: 60)
    |> validate_Exclusion()
    |> unique_constraint(:slug, message: "cette catégorie existe déjà")
  end

  defp validate_Exclusion(changeset) do
    validate_exclusion(changeset, :slug, ["all"],
      message: "le nom « all » est réservé au filtre global"
    )
  end

  defp normalize_fields(changeset) do
    name = get_field(changeset, :name) |> normalize_string()
    slug = get_field(changeset, :slug)
    password = get_field(changeset, :password) |> normalize_password()

    slug =
      cond do
        is_binary(slug) and String.trim(slug) != "" -> slugify(slug)
        is_binary(name) and name != "" -> slugify(name)
        true -> nil
      end

    changeset
    |> put_change(:name, name)
    |> put_change(:slug, slug)
    |> put_change(:password, password)
  end

  defp normalize_string(nil), do: nil
  defp normalize_string(str) when is_binary(str), do: String.trim(str)

  defp normalize_password(nil), do: nil

  defp normalize_password(str) when is_binary(str) do
    case String.trim(str) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  @doc """
  Generates a URL/DB-safe slug from a human category name.
  """
  def slugify(str) when is_binary(str) do
    str
    |> String.normalize(:nfd)
    |> String.replace(~r/[^A-Za-z0-9\s_-]/u, "")
    |> String.downcase()
    |> String.trim()
    |> String.replace(~r/[\s_-]+/, "-")
    |> String.trim("-")
  end

  @doc """
  Returns true if the category requires a password to be unlocked in the shop.
  """
  def protected?(%__MODULE__{password: pwd}) when is_binary(pwd) do
    String.trim(pwd) != ""
  end

  def protected?(_), do: false

  @doc """
  Checks whether the given input password matches the category's password.
  For the `"bicus"` category, if `BICUS_PASSWORD` environment variable is set,
  it is also accepted if the DB password is still the default `"bicus123"`.
  """
  def valid_password?(%__MODULE__{slug: "bicus", password: db_pwd}, input_pwd)
      when is_binary(input_pwd) do
    trimmed = String.trim(input_pwd)
    env_pwd = System.get_env("BICUS_PASSWORD")

    cond do
      is_binary(db_pwd) and trimmed == String.trim(db_pwd) ->
        true

      is_binary(env_pwd) and String.trim(env_pwd) != "" and trimmed == String.trim(env_pwd) ->
        true

      true ->
        false
    end
  end

  def valid_password?(%__MODULE__{password: db_pwd}, input_pwd)
      when is_binary(db_pwd) and is_binary(input_pwd) do
    String.trim(input_pwd) == String.trim(db_pwd)
  end

  def valid_password?(_, _), do: false
end
