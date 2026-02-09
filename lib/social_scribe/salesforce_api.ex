defmodule SocialScribe.SalesforceApi do
  @moduledoc """
  Salesforce CRM API client for contacts operations.
  Implements automatic token refresh on 401/expired token errors.
  """

  @behaviour SocialScribe.SalesforceApiBehaviour

  alias SocialScribe.Accounts.UserCredential
  alias SocialScribe.SalesforceTokenRefresher

  require Logger

  # Standard Salesforce Contact fields
  @contact_fields [
    "Id",
    "Salutation",
    "FirstName",
    "LastName",
    "Email",
    "Phone",
    "HomePhone",
    "MobilePhone",
    "OtherPhone",
    "Fax",
    "Title",
    "Department",
    "Birthdate",
    "AssistantName",
    "AssistantPhone",
    "LeadSource",
    "Description",
    "MailingStreet",
    "MailingCity",
    "MailingState",
    "MailingPostalCode",
    "MailingCountry",
    "OtherStreet",
    "OtherCity",
    "OtherState",
    "OtherPostalCode",
    "OtherCountry"
  ]

  @sosl_special_chars [
    "\\",
    "?",
    "&",
    "|",
    "!",
    "{",
    "}",
    "[",
    "]",
    "(",
    ")",
    "^",
    "~",
    ":",
    "\"",
    "'"
  ]

  defp instance_url(%UserCredential{metadata: metadata}) when is_map(metadata) do
    Map.get(metadata, "instance_url", "https://login.salesforce.com")
  end

  defp instance_url(_), do: "https://login.salesforce.com"

  defp client(access_token, base_url) do
    Tesla.client([
      {Tesla.Middleware.BaseUrl, base_url},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers,
       [
         {"Authorization", "Bearer #{access_token}"},
         {"Content-Type", "application/json"}
       ]}
    ])
  end

  @doc """
  Searches for contacts by query string using SOSL.
  Returns up to 10 matching contacts with basic properties.
  Automatically refreshes token on 401/expired errors and retries once.
  """
  def search_contacts(%UserCredential{} = credential, query) when is_binary(query) do
    with_token_refresh(credential, fn cred ->
      # Use SOSL (Salesforce Object Search Language) for text search
      sosl_query = """
      FIND {#{escape_sosl_query(query)}*} IN NAME FIELDS
      RETURNING Contact(#{Enum.join(@contact_fields, ", ")})
      LIMIT 10
      """

      params = [q: sosl_query]

      case Tesla.get(
             client(cred.token, instance_url(cred)),
             "/services/data/v59.0/search",
             query: params
           ) do
        {:ok, %Tesla.Env{status: 200, body: %{"searchRecords" => results}}} ->
          contacts = Enum.map(results, &format_contact/1)
          {:ok, contacts}

        {:ok, %Tesla.Env{status: 200, body: body}} ->
          # Empty search results
          Logger.debug("Salesforce search returned 200 but no searchRecords: #{inspect(body)}")
          {:ok, []}

        {:ok, %Tesla.Env{status: status, body: body}} ->
          {:error, {:api_error, status, body}}

        {:error, reason} ->
          {:error, {:http_error, reason}}
      end
    end)
  end

  @doc """
  Gets a single contact by ID with all properties.
  Automatically refreshes token on 401/expired errors and retries once.
  """
  def get_contact(%UserCredential{} = credential, contact_id) do
    with_token_refresh(credential, fn cred ->
      soql_query =
        "SELECT #{Enum.join(@contact_fields, ", ")} FROM Contact WHERE Id = '#{contact_id}' LIMIT 1"

      case Tesla.get(client(cred.token, instance_url(cred)), "/services/data/v59.0/query",
             query: [q: soql_query]
           ) do
        {:ok, %Tesla.Env{status: 200, body: %{"records" => [record | _]}}} ->
          {:ok, format_contact(record)}

        {:ok, %Tesla.Env{status: 200, body: %{"records" => []}}} ->
          {:error, :not_found}

        {:ok, %Tesla.Env{status: status, body: body}} ->
          {:error, {:api_error, status, body}}

        {:error, reason} ->
          {:error, {:http_error, reason}}
      end
    end)
  end

  @doc """
  Updates a contact's properties.
  `updates` should be a map of property names to new values.
  Automatically refreshes token on 401/expired errors and retries once.
  """
  def update_contact(%UserCredential{} = credential, contact_id, updates)
      when is_map(updates) do
    with_token_refresh(credential, fn cred ->
      # Convert field names to Salesforce format (e.g., "phone" -> "Phone")
      salesforce_updates = convert_to_salesforce_fields(updates)

      case Tesla.patch(
             client(cred.token, instance_url(cred)),
             "/services/data/v59.0/sobjects/Contact/#{contact_id}",
             salesforce_updates
           ) do
        {:ok, %Tesla.Env{status: 204}} ->
          # Salesforce returns 204 No Content on successful update
          # Fetch the updated contact to return
          get_contact(cred, contact_id)

        {:ok, %Tesla.Env{status: 404, body: _body}} ->
          {:error, :not_found}

        {:ok, %Tesla.Env{status: status, body: body}} ->
          {:error, {:api_error, status, body}}

        {:error, reason} ->
          {:error, {:http_error, reason}}
      end
    end)
  end

  @doc """
  Batch updates multiple properties on a contact.
  This is a convenience wrapper around update_contact/3.
  """
  def apply_updates(%UserCredential{} = credential, contact_id, updates_list)
      when is_list(updates_list) do
    updates_map =
      updates_list
      |> Enum.filter(fn update -> update[:apply] == true end)
      |> Enum.reduce(%{}, fn update, acc ->
        Map.put(acc, update.field, update.new_value)
      end)

    if map_size(updates_map) > 0 do
      update_contact(credential, contact_id, updates_map)
    else
      {:ok, :no_updates}
    end
  end

  # Format a Salesforce contact response into a cleaner structure
  defp format_contact(%{"Id" => id} = contact) do
    %{
      id: id,
      salutation: contact["Salutation"],
      firstname: contact["FirstName"],
      lastname: contact["LastName"],
      email: contact["Email"],
      phone: contact["Phone"],
      homephone: contact["HomePhone"],
      mobilephone: contact["MobilePhone"],
      otherphone: contact["OtherPhone"],
      fax: contact["Fax"],
      jobtitle: contact["Title"],
      department: contact["Department"],
      birthdate: contact["Birthdate"],
      assistant: contact["AssistantName"],
      assistantphone: contact["AssistantPhone"],
      leadsource: contact["LeadSource"],
      description: contact["Description"],
      address: contact["MailingStreet"],
      city: contact["MailingCity"],
      state: contact["MailingState"],
      zip: contact["MailingPostalCode"],
      country: contact["MailingCountry"],
      otherstreet: contact["OtherStreet"],
      othercity: contact["OtherCity"],
      otherstate: contact["OtherState"],
      otherzip: contact["OtherPostalCode"],
      othercountry: contact["OtherCountry"],
      display_name: format_display_name(contact)
    }
  end

  defp format_contact(_), do: nil

  defp format_display_name(contact) do
    firstname = contact["FirstName"] || ""
    lastname = contact["LastName"] || ""
    email = contact["Email"] || ""

    name = String.trim("#{firstname} #{lastname}")

    if name == "" do
      email
    else
      name
    end
  end

  # Convert our internal field names to Salesforce field names
  defp convert_to_salesforce_fields(updates) do
    field_mapping = %{
      "salutation" => "Salutation",
      "firstname" => "FirstName",
      "lastname" => "LastName",
      "email" => "Email",
      "phone" => "Phone",
      "homephone" => "HomePhone",
      "mobilephone" => "MobilePhone",
      "otherphone" => "OtherPhone",
      "fax" => "Fax",
      "jobtitle" => "Title",
      "department" => "Department",
      "birthdate" => "Birthdate",
      "assistant" => "AssistantName",
      "assistantphone" => "AssistantPhone",
      "leadsource" => "LeadSource",
      "description" => "Description",
      "address" => "MailingStreet",
      "city" => "MailingCity",
      "state" => "MailingState",
      "zip" => "MailingPostalCode",
      "country" => "MailingCountry",
      "otherstreet" => "OtherStreet",
      "othercity" => "OtherCity",
      "otherstate" => "OtherState",
      "otherzip" => "OtherPostalCode",
      "othercountry" => "OtherCountry"
    }

    updates
    |> Enum.filter(fn {key, _value} -> Map.has_key?(field_mapping, key) end)
    |> Enum.map(fn {key, value} -> {Map.fetch!(field_mapping, key), value} end)
    |> Enum.into(%{})
  end

  defp escape_sosl_query(query) do
    Enum.reduce(@sosl_special_chars, query, fn char, acc ->
      String.replace(acc, char, "\\#{char}")
    end)
  end

  # Wrapper that handles token refresh on auth errors
  defp with_token_refresh(%UserCredential{} = credential, api_call) do
    case SalesforceTokenRefresher.ensure_valid_token(credential) do
      {:ok, credential} ->
        case api_call.(credential) do
          {:error, {:api_error, status, body}} when status in [401, 403] ->
            if is_token_error?(body) do
              Logger.info("Salesforce token expired, refreshing and retrying...")
              retry_with_fresh_token(credential, api_call)
            else
              Logger.error("Salesforce API error: #{status} - #{inspect(body)}")
              {:error, {:api_error, status, body}}
            end

          other ->
            other
        end

      {:error, reason} ->
        Logger.error("Salesforce token refresh failed in with_token_refresh: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp retry_with_fresh_token(credential, api_call) do
    case SalesforceTokenRefresher.refresh_credential(credential) do
      {:ok, refreshed_credential} ->
        case api_call.(refreshed_credential) do
          {:error, {:api_error, status, body}} ->
            Logger.error("Salesforce API error after refresh: #{status} - #{inspect(body)}")
            {:error, {:api_error, status, body}}

          {:error, {:http_error, reason}} ->
            Logger.error("Salesforce HTTP error after refresh: #{inspect(reason)}")
            {:error, {:http_error, reason}}

          success ->
            success
        end

      {:error, refresh_error} ->
        Logger.error("Failed to refresh Salesforce token: #{inspect(refresh_error)}")
        {:error, {:token_refresh_failed, refresh_error}}
    end
  end

  defp is_token_error?(body) when is_list(body) do
    Enum.any?(body, fn error ->
      case error do
        %{"errorCode" => code} when code in ["INVALID_SESSION_ID", "EXPIRED_ACCESS_TOKEN"] -> true
        _ -> false
      end
    end)
  end

  defp is_token_error?(%{"error" => error}) when error in ["invalid_grant", "expired_token"],
    do: true

  defp is_token_error?(_), do: false
end
