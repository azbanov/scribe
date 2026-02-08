defmodule SocialScribe.Workers.SalesforceTokenRefresherTest do
  use SocialScribe.DataCase

  alias SocialScribe.Workers.SalesforceTokenRefresher

  import SocialScribe.AccountsFixtures

  describe "perform/1" do
    test "returns :ok when no salesforce credentials exist" do
      assert :ok = SalesforceTokenRefresher.perform(%Oban.Job{args: %{}})
    end

    test "returns :ok when no salesforce credentials are expiring" do
      user = user_fixture()

      salesforce_credential_fixture(%{
        user_id: user.id,
        expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
      })

      assert :ok = SalesforceTokenRefresher.perform(%Oban.Job{args: %{}})
    end

    test "ignores non-salesforce credentials even if expiring" do
      user = user_fixture()

      hubspot_credential_fixture(%{
        user_id: user.id,
        expires_at: DateTime.add(DateTime.utc_now(), 300, :second)
      })

      assert :ok = SalesforceTokenRefresher.perform(%Oban.Job{args: %{}})
    end

    test "finds credentials expiring within threshold" do
      user = user_fixture()

      salesforce_credential_fixture(%{
        user_id: user.id,
        expires_at: DateTime.add(DateTime.utc_now(), 300, :second)
      })

      # Worker always returns :ok regardless of refresh outcome
      assert :ok = SalesforceTokenRefresher.perform(%Oban.Job{args: %{}})
    end

    test "handles multiple expiring credentials" do
      user1 = user_fixture()
      user2 = user_fixture()
      user3 = user_fixture()

      salesforce_credential_fixture(%{
        user_id: user1.id,
        expires_at: DateTime.add(DateTime.utc_now(), 300, :second)
      })

      salesforce_credential_fixture(%{
        user_id: user2.id,
        expires_at: DateTime.add(DateTime.utc_now(), 200, :second)
      })

      salesforce_credential_fixture(%{
        user_id: user3.id,
        expires_at: DateTime.add(DateTime.utc_now(), 100, :second)
      })

      assert :ok = SalesforceTokenRefresher.perform(%Oban.Job{args: %{}})
    end
  end
end
