defmodule SocialScribe.SalesforceApiBehaviour do
  @moduledoc """
  Behaviour for Salesforce API operations.
  Allows for mocking in tests.
  """

  alias SocialScribe.Accounts.UserCredential

  @callback search_contacts(UserCredential.t(), String.t()) ::
              {:ok, list(map())} | {:error, any()}

  @callback get_contact(UserCredential.t(), String.t()) ::
              {:ok, map()} | {:error, any()}

  @callback update_contact(UserCredential.t(), String.t(), map()) ::
              {:ok, map()} | {:error, any()}

  @callback apply_updates(UserCredential.t(), String.t(), list(map())) ::
              {:ok, map() | :no_updates} | {:error, any()}
end
