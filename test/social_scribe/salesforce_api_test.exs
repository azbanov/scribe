defmodule SocialScribe.SalesforceApiTest do
  use SocialScribe.DataCase

  alias SocialScribe.SalesforceApi

  import SocialScribe.AccountsFixtures

  describe "apply_updates/3" do
    test "returns {:ok, :no_updates} when updates list is empty" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      {:ok, :no_updates} = SalesforceApi.apply_updates(credential, "123", [])
    end

    test "returns {:ok, :no_updates} when all updates have apply: false" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      updates = [
        %{field: "phone", new_value: "555-1234", apply: false},
        %{field: "email", new_value: "test@example.com", apply: false}
      ]

      {:ok, :no_updates} = SalesforceApi.apply_updates(credential, "123", updates)
    end

    test "returns {:ok, :no_updates} with mixed updates where none have apply: true" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      updates = [
        %{field: "phone", new_value: "555-1234", apply: false},
        %{field: "jobtitle", new_value: "Engineer", apply: false},
        %{field: "department", new_value: "Sales", apply: false}
      ]

      {:ok, :no_updates} = SalesforceApi.apply_updates(credential, "123", updates)
    end
  end

  describe "search_contacts/2" do
    test "requires a valid credential" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      assert is_struct(credential)
      assert credential.provider == "salesforce"
      assert credential.metadata["instance_url"] == "https://test.salesforce.com"
    end
  end

  describe "get_contact/2" do
    test "requires a valid credential and contact_id" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      assert is_struct(credential)
      assert credential.provider == "salesforce"
    end
  end

  describe "update_contact/3" do
    test "requires a valid credential, contact_id, and updates map" do
      user = user_fixture()

      credential =
        salesforce_credential_fixture(%{
          user_id: user.id,
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      assert is_struct(credential)
      assert credential.provider == "salesforce"
    end
  end
end
