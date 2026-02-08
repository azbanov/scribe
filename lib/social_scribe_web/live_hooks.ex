defmodule SocialScribeWeb.LiveHooks do
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4]

  alias SocialScribe.Chat
  require Logger

  def on_mount(:assign_current_path, _params, _session, socket) do
    socket =
      socket
      |> attach_hook(:assign_current_path, :handle_params, &assign_current_path/3)
      |> attach_hook(:chat_widget, :handle_info, &handle_chat_widget_info/2)

    {:cont, socket}
  end

  defp assign_current_path(_params, uri, socket) do
    uri = URI.parse(uri)

    {:cont, assign(socket, :current_path, uri.path)}
  end

  defp handle_chat_widget_info(
         {:chat_widget_generate_response, question, contact, credentials, user},
         socket
       ) do
    credential = find_credential(credentials, contact)

    result =
      case {contact, credential} do
        {nil, _} -> {:error, :no_contact_selected}
        {_, nil} -> {:error, :no_contact_selected}
        {contact, credential} -> Chat.ask_question(question, contact, credential, user)
      end

    case result do
      {:ok, %{answer: answer, sources: sources}} ->
        ai_msg = %{
          role: :assistant,
          content: answer,
          timestamp: DateTime.utc_now(),
          sources: sources
        }

        Phoenix.LiveView.send_update(SocialScribeWeb.ChatWidgetComponent,
          id: "chat-widget",
          new_message: ai_msg
        )

      {:error, reason} ->
        error_message =
          case reason do
            :no_contact_selected ->
              "Please select a contact using the @ button before asking questions."

            :unsupported_provider ->
              "This CRM provider is not supported."

            :api_error ->
              "There was an error connecting to your CRM. Please check your connection."

            _ ->
              "I'm sorry, I encountered an error: #{inspect(reason)}. Please try again."
          end

        error_msg = %{
          role: :assistant,
          content: error_message,
          timestamp: DateTime.utc_now(),
          sources: []
        }

        Phoenix.LiveView.send_update(SocialScribeWeb.ChatWidgetComponent,
          id: "chat-widget",
          new_message: error_msg
        )
    end

    {:halt, socket}
  end

  defp handle_chat_widget_info({:chat_widget_search_contacts, query, credentials}, socket) do
    results =
      credentials
      |> Enum.flat_map(fn credential ->
        case Chat.search_contacts(credential, query) do
          {:ok, contacts} ->
            Enum.map(contacts, &Map.put(&1, :provider, credential.provider))

          {:error, _reason} ->
            []
        end
      end)

    Phoenix.LiveView.send_update(SocialScribeWeb.ChatWidgetComponent,
      id: "chat-widget",
      search_results: results
    )

    {:halt, socket}
  end

  defp handle_chat_widget_info(_msg, socket) do
    {:cont, socket}
  end

  defp find_credential(credentials, %{provider: provider}) do
    Enum.find(credentials, &(&1.provider == provider))
  end

  defp find_credential(_, _), do: nil
end
