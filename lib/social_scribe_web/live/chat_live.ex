defmodule SocialScribeWeb.ChatLive do
  use SocialScribeWeb, :live_view

  alias SocialScribe.Accounts
  alias SocialScribe.Chat

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    hubspot_credential = Accounts.get_user_hubspot_credential(user.id)
    salesforce_credential = Accounts.get_user_salesforce_credential(user.id)

    credentials =
      [hubspot_credential, salesforce_credential]
      |> Enum.reject(&is_nil/1)

    welcome_message = %{
      role: :assistant,
      content: "I can answer questions about your meetings and CRM data – just ask!",
      timestamp: DateTime.utc_now(),
      sources: []
    }

    socket =
      socket
      |> assign(:page_title, "Ask Anything")
      |> assign(:messages, [welcome_message])
      |> assign(:input, "")
      |> assign(:loading, false)
      |> assign(:credentials, credentials)
      |> assign(:active_tab, "chat")
      |> assign(:contact_search_open, false)
      |> assign(:contact_query, "")
      |> assign(:contact_results, [])
      |> assign(:selected_contact, nil)

    {:ok, socket}
  end

  @impl true
  def handle_event("send_message", %{"message" => message}, socket) do
    message = String.trim(message)

    case message do
      "" ->
        {:noreply, socket}

      _ ->
        user_msg = %{
          role: :user,
          content: message,
          timestamp: DateTime.utc_now(),
          sources: []
        }

        socket =
          socket
          |> update(:messages, &(&1 ++ [user_msg]))
          |> assign(:input, "")
          |> assign(:loading, true)

        send(self(), {:generate_response, message, socket.assigns.selected_contact})
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_contact_search", _params, socket) do
    {:noreply, assign(socket, contact_search_open: !socket.assigns.contact_search_open)}
  end

  @impl true
  def handle_event("contact_search", %{"value" => query}, socket) do
    query = String.trim(query)

    case {String.length(query) >= 2, Enum.any?(socket.assigns.credentials)} do
      {true, true} ->
        send(self(), {:search_contacts, query})
        {:noreply, assign(socket, contact_query: query)}

      _ ->
        {:noreply, assign(socket, contact_query: query, contact_results: [])}
    end
  end

  @impl true
  def handle_event("select_contact", %{"id" => contact_id, "provider" => provider}, socket) do
    contact =
      Enum.find(socket.assigns.contact_results, &(&1.id == contact_id && &1.provider == provider))

    {:noreply,
     assign(socket,
       selected_contact: contact,
       contact_search_open: false,
       contact_query: "",
       contact_results: []
     )}
  end

  @impl true
  def handle_event("clear_contact", _params, socket) do
    {:noreply, assign(socket, selected_contact: nil)}
  end

  @impl true
  def handle_event("new_chat", _params, socket) do
    welcome_message = %{
      role: :assistant,
      content: "I can answer questions about your meetings and CRM data – just ask!",
      timestamp: DateTime.utc_now(),
      sources: []
    }

    {:noreply,
     assign(socket,
       messages: [welcome_message],
       input: "",
       loading: false,
       selected_contact: nil,
       contact_search_open: false,
       contact_query: "",
       contact_results: []
     )}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, tab)}
  end

  @impl true
  def handle_info({:generate_response, question, contact}, socket) do
    credential = find_credential(socket.assigns.credentials, contact)

    result =
      if contact && credential do
        Chat.ask_question(question, contact, credential, socket.assigns.current_user)
      else
        {:error, :no_contact_selected}
      end

    socket =
      case result do
        {:ok, %{answer: answer, sources: sources}} ->
          ai_msg = %{
            role: :assistant,
            content: answer,
            timestamp: DateTime.utc_now(),
            sources: sources
          }

          socket
          |> update(:messages, &(&1 ++ [ai_msg]))
          |> assign(:loading, false)

        {:error, _reason} ->
          error_msg = %{
            role: :assistant,
            content:
              "I'm sorry, I couldn't process that request. Please make sure you've selected a contact using the @ button and try again.",
            timestamp: DateTime.utc_now(),
            sources: []
          }

          socket
          |> update(:messages, &(&1 ++ [error_msg]))
          |> assign(:loading, false)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:search_contacts, query}, socket) do
    results =
      socket.assigns.credentials
      |> Enum.flat_map(fn credential ->
        case Chat.search_contacts(credential, query) do
          {:ok, contacts} ->
            Enum.map(contacts, &Map.put(&1, :provider, credential.provider))

          {:error, _} ->
            []
        end
      end)

    {:noreply, assign(socket, contact_results: results)}
  end

  defp find_credential(credentials, %{provider: provider}) do
    Enum.find(credentials, &(&1.provider == provider))
  end

  defp find_credential(_, _), do: nil

  defp format_time(%DateTime{} = dt) do
    hour = dt.hour
    minute = dt.minute |> Integer.to_string() |> String.pad_leading(2, "0")
    am_pm = if hour >= 12, do: "pm", else: "am"
    display_hour = if rem(hour, 12) == 0, do: 12, else: rem(hour, 12)
    "#{display_hour}:#{minute}#{am_pm}"
  end

  defp format_date_separator(%DateTime{} = dt) do
    time = format_time(dt)
    date = Calendar.strftime(dt, "%B %d, %Y")
    "#{time} – #{date}"
  end

  defp contact_display_name(%{firstname: first, lastname: last}), do: "#{first} #{last}"
  defp contact_display_name(_), do: ""

  defp provider_label("hubspot"), do: "HubSpot"
  defp provider_label("salesforce"), do: "Salesforce"
  defp provider_label(other), do: String.capitalize(other)
end
