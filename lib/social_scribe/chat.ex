defmodule SocialScribe.Chat do
  @moduledoc """
  Context module for the chat feature.
  Orchestrates CRM data fetching and AI question answering.
  """

  alias SocialScribe.Meetings
  alias SocialScribe.HubspotApiBehaviour, as: HubspotApi
  alias SocialScribe.SalesforceApiBehaviour, as: SalesforceApi
  alias SocialScribe.AIContentGeneratorApi

  @doc """
  Asks a question about a contact using meeting transcript data and CRM information.

  Returns `{:ok, %{answer: String.t(), sources: [%{title: String.t(), timestamp: String.t()}]}}`.
  """
  def ask_question(question, contact, credential, user) do
    with {:ok, contact_data} <- fetch_contact_data(contact, credential),
         meetings <- Meetings.list_user_meetings(user),
         {:ok, prompt} <- build_prompt(question, contact_data, meetings) do
      case AIContentGeneratorApi.generate_chat_response(prompt) do
        {:ok, answer} ->
          sources = extract_sources(meetings, credential.provider)
          {:ok, %{answer: answer, sources: sources}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Searches for contacts in the connected CRM.
  """
  def search_contacts(credential, query) do
    case credential.provider do
      "hubspot" -> HubspotApi.search_contacts(credential, query)
      "salesforce" -> SalesforceApi.search_contacts(credential, query)
      _ -> {:error, :unsupported_provider}
    end
  end

  defp fetch_contact_data(contact, credential) do
    case credential.provider do
      "hubspot" -> HubspotApi.get_contact(credential, contact.id)
      "salesforce" -> SalesforceApi.get_contact(credential, contact.id)
      _ -> {:error, :unsupported_provider}
    end
  end

  defp build_prompt(question, contact_data, meetings) do
    contact_info = format_contact_data(contact_data)
    meeting_context = build_meeting_context(meetings)

    prompt = """
    You are a helpful CRM assistant. Answer the user's question using the contact data and meeting transcripts provided below.

    Be concise, specific, and reference the meeting or transcript where you found the information.
    If you cannot find the answer in the provided data, say so clearly.

    ## Contact Data
    #{contact_info}

    ## Meeting Transcripts
    #{meeting_context}

    ## Question
    #{question}
    """

    {:ok, prompt}
  end

  defp format_contact_data(contact) when is_map(contact) do
    contact
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
    |> Enum.map(fn {k, v} -> "- #{k}: #{v}" end)
    |> Enum.join("\n")
  end

  defp format_contact_data(_), do: "No contact data available."

  defp build_meeting_context(meetings) do
    meetings
    |> Enum.take(5)
    |> Enum.map(fn meeting ->
      case Meetings.generate_prompt_for_meeting(meeting) do
        {:ok, prompt} -> "### #{meeting.title}\n#{prompt}"
        {:error, _} -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n---\n\n")
    |> case do
      "" -> "No meeting transcripts available."
      context -> context
    end
  end

  defp extract_sources(meetings, provider) do
    app_source = %{title: "Scribe", provider: "app", timestamp: ""}

    meeting_sources =
      meetings
      |> Enum.take(5)
      |> Enum.map(fn meeting ->
        %{title: meeting.title, provider: provider, timestamp: format_date(meeting.recorded_at)}
      end)

    [app_source | meeting_sources]
  end

  defp format_date(nil), do: ""

  defp format_date(%DateTime{} = dt) do
    Calendar.strftime(dt, "%b %d, %Y")
  end
end
