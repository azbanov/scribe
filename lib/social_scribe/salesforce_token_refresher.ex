defmodule SocialScribe.SalesforceTokenRefresher do
  @moduledoc """
  Handles automatic token refresh for Salesforce credentials.
  Similar to HubspotTokenRefresher but adapted for Salesforce OAuth flow.
  """

  alias SocialScribe.Accounts
  alias SocialScribe.Accounts.UserCredential

  require Logger

  @token_expiry_buffer_seconds 300
  @default_expires_in 7200
  @token_url "https://login.salesforce.com/services/oauth2/token"

  def ensure_valid_token(%UserCredential{} = credential) do
    if token_expired?(credential) do
      # Reload from DB to get the latest refresh token
      # (it may have been rotated by a background worker or prior refresh)
      fresh_credential = SocialScribe.Accounts.get_user_credential!(credential.id)
      refresh_credential(fresh_credential)
    else
      {:ok, credential}
    end
  end

  def refresh_credential(%UserCredential{provider: "salesforce", refresh_token: nil}) do
    Logger.error("Cannot refresh Salesforce token: no refresh token available")
    {:error, :no_refresh_token}
  end

  def refresh_credential(%UserCredential{provider: "salesforce", refresh_token: ""}) do
    Logger.error("Cannot refresh Salesforce token: no refresh token available")
    {:error, :no_refresh_token}
  end

  def refresh_credential(%UserCredential{provider: "salesforce"} = credential) do
    config = Application.get_env(:ueberauth, Ueberauth.Strategy.Salesforce.OAuth, [])

    body = %{
      grant_type: "refresh_token",
      refresh_token: credential.refresh_token,
      client_id: config[:client_id],
      client_secret: config[:client_secret]
    }

    case Tesla.post(http_client(), @token_url, body) do
      {:ok, %Tesla.Env{status: 200, body: response}} ->
        update_credential_tokens(credential, response)

      {:ok, %Tesla.Env{status: status, body: error_body}} ->
        Logger.error("Salesforce token refresh failed: #{status} - #{inspect(error_body)}")
        {:error, {:refresh_failed, status, error_body}}

      {:error, reason} ->
        Logger.error("Salesforce token refresh HTTP error: #{inspect(reason)}")
        {:error, {:http_error, reason}}
    end
  end

  def refresh_credential(%UserCredential{}) do
    Logger.error("Cannot refresh credential: not a Salesforce credential")
    {:error, :invalid_provider}
  end

  defp update_credential_tokens(credential, response) do
    expires_in = Map.get(response, "expires_in", @default_expires_in)
    current_metadata = credential.metadata || %{}

    updates = %{
      token: response["access_token"],
      refresh_token: Map.get(response, "refresh_token", credential.refresh_token),
      expires_at: DateTime.utc_now() |> DateTime.add(expires_in, :second),
      metadata:
        Map.put(
          current_metadata,
          "instance_url",
          Map.get(response, "instance_url", current_metadata["instance_url"])
        )
    }

    case Accounts.update_user_credential(credential, updates) do
      {:ok, updated_credential} ->
        Logger.info("Successfully refreshed Salesforce token for user #{credential.user_id}")
        {:ok, updated_credential}

      {:error, changeset} ->
        Logger.error("Failed to update credential after refresh: #{inspect(changeset.errors)}")
        {:error, {:update_failed, changeset}}
    end
  end

  defp token_expired?(%UserCredential{expires_at: nil}), do: true

  defp token_expired?(%UserCredential{expires_at: expires_at}) do
    threshold = DateTime.utc_now() |> DateTime.add(@token_expiry_buffer_seconds, :second)
    DateTime.compare(expires_at, threshold) == :lt
  end

  defp http_client do
    Tesla.client([
      Tesla.Middleware.FormUrlencoded,
      Tesla.Middleware.DecodeJson
    ])
  end
end
