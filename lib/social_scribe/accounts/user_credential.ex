defmodule SocialScribe.Accounts.UserCredential do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer() | nil,
          token: String.t(),
          uid: String.t(),
          provider: String.t(),
          refresh_token: String.t() | nil,
          expires_at: DateTime.t(),
          email: String.t(),
          metadata: map() | nil,
          user_id: integer(),
          user: Ecto.Schema.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "user_credentials" do
    field :token, :string
    field :uid, :string
    field :provider, :string
    field :refresh_token, :string
    field :expires_at, :utc_datetime
    field :email, :string
    field :metadata, :map, default: %{}

    belongs_to :user, SocialScribe.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(user_credential, attrs) do
    user_credential
    |> cast(attrs, [
      :provider,
      :uid,
      :token,
      :refresh_token,
      :expires_at,
      :user_id,
      :email,
      :metadata
    ])
    |> validate_required([:provider, :uid, :token, :expires_at, :user_id, :email])
  end

  def linkedin_changeset(user_credential, attrs) do
    user_credential
    |> cast(attrs, [
      :provider,
      :uid,
      :token,
      :refresh_token,
      :expires_at,
      :user_id,
      :email,
      :metadata
    ])
    |> validate_required([:provider, :uid, :token, :expires_at, :user_id, :email])
  end
end
