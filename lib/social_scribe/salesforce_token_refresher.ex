defmodule SocialScribe.SalesforceTokenRefresher do
  @moduledoc """
  Handles automatic token refresh for Salesforce credentials.
  Similar to HubspotTokenRefresher but adapted for Salesforce OAuth flow.
  """

  alias SocialScribe.Accounts
  alias SocialScribe.Accounts.UserCredential

  require Logger

  @doc """
  Ensures a credential has a valid (non-expired) token.
  Returns {:ok, credential} if valid, or refreshes if expired.
  """
  def ensure_valid_token(%UserCredential{} = credential) do
    if token_expired?(credential) do
      refresh_credential(credential)
    else
      {:ok, credential}
    end
  end

  @doc """
  Refreshes a Salesforce credential's access token using the refresh token.
  """
  def refresh_credential(%UserCredential{provider: "salesforce"} = credential) do
    config = Application.get_env(:ueberauth, Ueberauth.Strategy.Salesforce.OAuth, [])
    client_id = config[:client_id]
    client_secret = config[:client_secret]

    if is_nil(credential.refresh_token) or credential.refresh_token == "" do
      Logger.error("Cannot refresh Salesforce token: no refresh token available")
      {:error, :no_refresh_token}
    else
      body = %{
        grant_type: "refresh_token",
        refresh_token: credential.refresh_token,
        client_id: client_id,
        client_secret: client_secret
      }

      case Tesla.post(http_client(), "https://login.salesforce.com/services/oauth2/token", body) do
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
  end

  def refresh_credential(%UserCredential{} = _credential) do
    Logger.error("Cannot refresh credential: not a Salesforce credential")
    {:error, :invalid_provider}
  end

  defp update_credential_tokens(credential, response) do
    # Calculate new expiration time
    # Salesforce doesn't return expires_in in refresh response, so we use a default
    # Default 2 hours
    expires_in = Map.get(response, "expires_in", 7200)
    expires_at = DateTime.utc_now() |> DateTime.add(expires_in, :second) |> DateTime.to_unix()

    # Salesforce may or may not return a new refresh token
    # If not provided, keep the existing one
    new_refresh_token = Map.get(response, "refresh_token", credential.refresh_token)

    # Update instance URL if provided
    instance_url = Map.get(response, "instance_url", credential.metadata["instance_url"])

    updated_metadata = Map.put(credential.metadata || %{}, "instance_url", instance_url)

    updates = %{
      token: response["access_token"],
      refresh_token: new_refresh_token,
      expires_at: expires_at,
      metadata: updated_metadata
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

  defp token_expired?(%UserCredential{expires_at: nil}), do: false

  defp token_expired?(%UserCredential{expires_at: expires_at}) do
    now = DateTime.utc_now() |> DateTime.to_unix()
    # Refresh if token expires within the next 5 minutes
    buffer = 300
    now >= expires_at - buffer
  end

  defp http_client do
    Tesla.client([
      Tesla.Middleware.JSON,
      Tesla.Middleware.FormUrlencoded
    ])
  end
end
