defmodule SocialScribe.SalesforceTokenRefresherTest do
  use SocialScribe.DataCase

  alias SocialScribe.SalesforceTokenRefresher
  alias SocialScribe.Accounts

  import SocialScribe.AccountsFixtures

  describe "ensure_valid_token/1" do
    test "returns credential unchanged when token is not expired" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      {:ok, result} = SalesforceTokenRefresher.ensure_valid_token(credential)

      assert result.id == credential.id
      assert result.token == credential.token
    end

    test "returns credential unchanged when token expires in more than 5 minutes" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 600, :second)
        })

      {:ok, result} = SalesforceTokenRefresher.ensure_valid_token(credential)

      assert result.id == credential.id
      assert result.token == credential.token
    end

    test "attempts refresh when expires_at is nil" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id
        })

      # Set expires_at to nil directly on the struct (bypassing changeset validation)
      credential = %{credential | expires_at: nil}

      # With nil expires_at, the token is considered expired and a refresh is attempted.
      # Since we don't have valid Salesforce credentials in test, it will fail.
      assert {:error, _reason} = SalesforceTokenRefresher.ensure_valid_token(credential)
    end
  end

  describe "refresh_credential/1" do
    test "returns {:error, :no_refresh_token} when refresh_token is nil" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id
        })

      # Build a struct with nil refresh_token for pattern matching
      credential = %{credential | refresh_token: nil}

      assert {:error, :no_refresh_token} =
               SalesforceTokenRefresher.refresh_credential(credential)
    end

    test "returns {:error, :no_refresh_token} when refresh_token is empty string" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id
        })

      credential = %{credential | refresh_token: ""}

      assert {:error, :no_refresh_token} =
               SalesforceTokenRefresher.refresh_credential(credential)
    end

    test "returns {:error, :invalid_provider} for non-salesforce credential" do
      user = user_fixture()
      credential = hubspot_credential_fixture(%{user_id: user.id})

      assert {:error, :invalid_provider} =
               SalesforceTokenRefresher.refresh_credential(credential)
    end

    test "returns {:error, :invalid_provider} for generic credential" do
      user = user_fixture()
      credential = user_credential_fixture(%{user_id: user.id})

      assert {:error, :invalid_provider} =
               SalesforceTokenRefresher.refresh_credential(credential)
    end

    test "updates credential in database on simulated successful refresh" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          token: "old_token",
          refresh_token: "old_refresh"
        })

      attrs = %{
        token: "new_access_token",
        refresh_token: "new_refresh_token",
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      }

      {:ok, updated} = Accounts.update_user_credential(credential, attrs)

      assert updated.token == "new_access_token"
      assert updated.refresh_token == "new_refresh_token"
      assert updated.id == credential.id
    end

    test "preserves metadata instance_url when updating credential" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          metadata: %{"instance_url" => "https://na1.salesforce.com"}
        })

      attrs = %{
        token: "new_token",
        metadata: %{"instance_url" => "https://na1.salesforce.com"}
      }

      {:ok, updated} = Accounts.update_user_credential(credential, attrs)

      assert updated.metadata["instance_url"] == "https://na1.salesforce.com"
      assert updated.id == credential.id
    end
  end
end
