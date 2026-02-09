defmodule SocialScribeWeb.ChatWidgetComponent do
  use SocialScribeWeb, :live_component

  alias SocialScribe.Accounts

  @impl true
  def update(%{new_message: msg}, socket) do
    socket =
      socket
      |> update(:messages, &(&1 ++ [msg]))
      |> assign(:loading, false)

    {:ok, socket}
  end

  def update(%{search_results: results}, socket) do
    {:ok, assign(socket, contact_results: results)}
  end

  def update(assigns, socket) do
    socket =
      case socket.assigns[:initialized] do
        true ->
          socket

        _ ->
          user = assigns.current_user
          credentials = Accounts.get_user_crm_credentials(user.id)

          welcome_message = %{
            role: :assistant,
            content: "I can answer questions about your meetings and CRM data – just ask!",
            timestamp: DateTime.utc_now(),
            sources: []
          }

          socket
          |> assign(:initialized, true)
          |> assign(:messages, [welcome_message])
          |> assign(:input, "")
          |> assign(:loading, false)
          |> assign(:credentials, credentials)
          |> assign(:active_tab, "chat")
          |> assign(:contact_search_open, false)
          |> assign(:contact_query, "")
          |> assign(:contact_results, [])
          |> assign(:selected_contact, nil)
      end

    {:ok, assign(socket, :current_user, assigns.current_user)}
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

        send(self(), {
          :chat_widget_generate_response,
          message,
          socket.assigns.selected_contact,
          socket.assigns.credentials,
          socket.assigns.current_user
        })

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
        send(self(), {:chat_widget_search_contacts, query, socket.assigns.credentials})
        {:noreply, assign(socket, contact_query: query)}

      _ ->
        {:noreply, assign(socket, contact_query: query, contact_results: [])}
    end
  end

  @impl true
  def handle_event("select_contact", %{"id" => contact_id, "provider" => provider}, socket) do
    contact =
      Enum.find(socket.assigns.contact_results, &(&1.id == contact_id && &1.provider == provider))

    welcome_message = %{
      role: :assistant,
      content: "I can answer questions about your meetings and CRM data – just ask!",
      timestamp: DateTime.utc_now(),
      sources: []
    }

    {:noreply,
     assign(socket,
       selected_contact: contact,
       messages: [welcome_message],
       loading: false,
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
