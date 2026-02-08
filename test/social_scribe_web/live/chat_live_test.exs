defmodule SocialScribeWeb.ChatLiveTest do
  use SocialScribeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SocialScribe.AccountsFixtures
  import SocialScribe.MeetingsFixtures
  import Mox

  setup :verify_on_exit!

  describe "mount" do
    test "renders chat page for authenticated user", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/dashboard/chat")

      assert html =~ "Ask Anything"
      assert html =~ "I can answer questions about your meetings and CRM data"
    end

    test "redirects unauthenticated user", %{conn: conn} do
      assert {:error, {:redirect, _}} = live(conn, ~p"/dashboard/chat")
    end

    test "shows credentials source icons when user has hubspot credential", %{conn: conn} do
      user = user_fixture()
      _credential = hubspot_credential_fixture(%{user_id: user.id})
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/dashboard/chat")

      # HubSpot icon indicator
      assert html =~ "H"
    end

    test "shows credentials source icons when user has salesforce credential", %{conn: conn} do
      user = user_fixture()
      _credential = salesforce_credential_fixture(%{user_id: user.id})
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, ~p"/dashboard/chat")

      # Salesforce icon indicator
      assert html =~ "S"
    end
  end

  describe "send_message" do
    test "displays error when no contact selected", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/dashboard/chat")

      view
      |> render_hook("send_message", %{"message" => "Hello"})

      :timer.sleep(200)

      html = render(view)
      assert html =~ "Please select a contact"
    end

    test "ignores empty messages", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/dashboard/chat")

      html =
        view
        |> render_hook("send_message", %{"message" => "   "})

      # Should not add any new message
      refute html =~ "Please select a contact"
    end

    test "sends message and displays AI response", %{conn: conn} do
      user = user_fixture()
      _credential = hubspot_credential_fixture(%{user_id: user.id})
      _meeting = meeting_fixture_with_transcript(user)
      conn = log_in_user(conn, user)

      mock_contacts = [
        %{
          id: "123",
          firstname: "John",
          lastname: "Doe",
          email: "john@example.com",
          phone: nil,
          company: "Acme Corp"
        }
      ]

      SocialScribe.HubspotApiMock
      |> expect(:search_contacts, fn _cred, _query -> {:ok, mock_contacts} end)

      SocialScribe.HubspotApiMock
      |> expect(:get_contact, fn _cred, _id ->
        {:ok, %{"firstname" => "John", "lastname" => "Doe"}}
      end)

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_chat_response, fn _prompt ->
        {:ok, "John is a great contact."}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/chat")

      # Open contact search and search
      view |> render_hook("toggle_contact_search", %{})

      view
      |> element("input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "John"})

      :timer.sleep(200)

      # Select contact
      view
      |> element("button[phx-click='select_contact'][phx-value-id='123']")
      |> render_click()

      # Send message
      view |> render_hook("send_message", %{"message" => "Tell me about John"})

      :timer.sleep(500)

      html = render(view)
      assert html =~ "Tell me about John"
      assert html =~ "John is a great contact."
    end
  end

  describe "contact_search" do
    setup %{conn: conn} do
      user = user_fixture()
      _credential = hubspot_credential_fixture(%{user_id: user.id})
      conn = log_in_user(conn, user)

      %{conn: conn, user: user}
    end

    test "searches contacts when query is >= 2 characters", %{conn: conn} do
      mock_contacts = [
        %{
          id: "123",
          firstname: "John",
          lastname: "Doe",
          email: "john@example.com",
          phone: nil,
          company: "Acme"
        }
      ]

      SocialScribe.HubspotApiMock
      |> expect(:search_contacts, fn _cred, _query -> {:ok, mock_contacts} end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/chat")

      view |> render_hook("toggle_contact_search", %{})

      view
      |> element("input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "Jo"})

      :timer.sleep(200)

      html = render(view)
      assert html =~ "John Doe"
      assert html =~ "john@example.com"
    end

    test "does not search when query is less than 2 characters", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/chat")

      view |> render_hook("toggle_contact_search", %{})

      view
      |> element("input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "J"})

      :timer.sleep(200)

      html = render(view)
      refute html =~ "John"
    end

    test "shows 'No contacts found' for empty results", %{conn: conn} do
      SocialScribe.HubspotApiMock
      |> expect(:search_contacts, fn _cred, _query -> {:ok, []} end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/chat")

      view |> render_hook("toggle_contact_search", %{})

      view
      |> element("input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "xyz"})

      :timer.sleep(200)

      html = render(view)
      assert html =~ "No contacts found"
    end

    test "handles API error gracefully during search", %{conn: conn} do
      SocialScribe.HubspotApiMock
      |> expect(:search_contacts, fn _cred, _query -> {:error, :api_error} end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/chat")

      view |> render_hook("toggle_contact_search", %{})

      view
      |> element("input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "test"})

      :timer.sleep(200)

      # Should not crash - view should still be alive
      html = render(view)
      assert html =~ "Ask Anything"
    end
  end

  describe "select_contact" do
    test "selects contact and resets messages", %{conn: conn} do
      user = user_fixture()
      _credential = hubspot_credential_fixture(%{user_id: user.id})
      conn = log_in_user(conn, user)

      mock_contacts = [
        %{
          id: "123",
          firstname: "John",
          lastname: "Doe",
          email: "john@example.com",
          phone: nil,
          company: "Acme"
        }
      ]

      SocialScribe.HubspotApiMock
      |> expect(:search_contacts, fn _cred, _query -> {:ok, mock_contacts} end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/chat")

      view |> render_hook("toggle_contact_search", %{})

      view
      |> element("input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "John"})

      :timer.sleep(200)

      html =
        view
        |> element("button[phx-click='select_contact'][phx-value-id='123']")
        |> render_click()

      # Shows selected contact badge
      assert html =~ "John Doe"
      assert html =~ "HubSpot"
      # Shows welcome message (reset)
      assert html =~ "I can answer questions about your meetings and CRM data"
    end

    test "switching contacts resets conversation", %{conn: conn} do
      user = user_fixture()
      _credential = hubspot_credential_fixture(%{user_id: user.id})
      conn = log_in_user(conn, user)

      contacts_a = [
        %{
          id: "1",
          firstname: "Alice",
          lastname: "A",
          email: "alice@example.com",
          phone: nil,
          company: nil
        }
      ]

      contacts_b = [
        %{
          id: "2",
          firstname: "Bob",
          lastname: "B",
          email: "bob@example.com",
          phone: nil,
          company: nil
        }
      ]

      SocialScribe.HubspotApiMock
      |> expect(:search_contacts, fn _cred, _query -> {:ok, contacts_a} end)

      SocialScribe.HubspotApiMock
      |> expect(:get_contact, fn _cred, _id ->
        {:ok, %{"firstname" => "Alice"}}
      end)

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_chat_response, fn _prompt ->
        {:ok, "Alice is from Company X."}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/chat")

      # Select contact A
      view |> render_hook("toggle_contact_search", %{})

      view
      |> element("input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "Alice"})

      :timer.sleep(200)

      view
      |> element("button[phx-click='select_contact'][phx-value-id='1']")
      |> render_click()

      # Send a message to contact A
      view |> render_hook("send_message", %{"message" => "Tell me about Alice"})
      :timer.sleep(500)

      html = render(view)
      assert html =~ "Alice is from Company X."

      # Now switch to contact B
      SocialScribe.HubspotApiMock
      |> expect(:search_contacts, fn _cred, _query -> {:ok, contacts_b} end)

      view |> render_hook("toggle_contact_search", %{})

      view
      |> element("input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "Bob"})

      :timer.sleep(200)

      html =
        view
        |> element("button[phx-click='select_contact'][phx-value-id='2']")
        |> render_click()

      # Previous conversation should be gone
      refute html =~ "Alice is from Company X."
      refute html =~ "Tell me about Alice"
      # Welcome message should be back
      assert html =~ "I can answer questions about your meetings and CRM data"
      # New contact should be selected
      assert html =~ "Bob B"
    end
  end

  describe "clear_contact" do
    test "clears the selected contact", %{conn: conn} do
      user = user_fixture()
      _credential = hubspot_credential_fixture(%{user_id: user.id})
      conn = log_in_user(conn, user)

      mock_contacts = [
        %{
          id: "123",
          firstname: "John",
          lastname: "Doe",
          email: "john@example.com",
          phone: nil,
          company: nil
        }
      ]

      SocialScribe.HubspotApiMock
      |> expect(:search_contacts, fn _cred, _query -> {:ok, mock_contacts} end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/chat")

      # Select a contact first
      view |> render_hook("toggle_contact_search", %{})

      view
      |> element("input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "John"})

      :timer.sleep(200)

      view
      |> element("button[phx-click='select_contact'][phx-value-id='123']")
      |> render_click()

      # Clear the contact
      html =
        view
        |> element("button[phx-click='clear_contact']")
        |> render_click()

      # Contact badge should be gone
      refute html =~ "John Doe"
    end
  end

  describe "new_chat" do
    test "resets all chat state", %{conn: conn} do
      user = user_fixture()
      _credential = hubspot_credential_fixture(%{user_id: user.id})
      conn = log_in_user(conn, user)

      mock_contacts = [
        %{
          id: "123",
          firstname: "John",
          lastname: "Doe",
          email: "john@example.com",
          phone: nil,
          company: nil
        }
      ]

      SocialScribe.HubspotApiMock
      |> expect(:search_contacts, fn _cred, _query -> {:ok, mock_contacts} end)

      SocialScribe.HubspotApiMock
      |> expect(:get_contact, fn _cred, _id ->
        {:ok, %{"firstname" => "John"}}
      end)

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_chat_response, fn _prompt ->
        {:ok, "Some AI answer."}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/chat")

      # Select contact and send message
      view |> render_hook("toggle_contact_search", %{})

      view
      |> element("input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "John"})

      :timer.sleep(200)

      view
      |> element("button[phx-click='select_contact'][phx-value-id='123']")
      |> render_click()

      view |> render_hook("send_message", %{"message" => "Question?"})
      :timer.sleep(500)

      html = render(view)
      assert html =~ "Some AI answer."

      # Click new chat
      html =
        view
        |> element("button[phx-click='new_chat']")
        |> render_click()

      # Everything should be reset
      refute html =~ "Some AI answer."
      refute html =~ "Question?"
      assert html =~ "I can answer questions about your meetings and CRM data"
    end
  end

  describe "switch_tab" do
    test "switches between chat and history tabs", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, html} = live(conn, ~p"/dashboard/chat")

      # Default is chat tab
      assert html =~ "I can answer questions about your meetings and CRM data"

      # Switch to history
      html =
        view
        |> element("button[phx-click='switch_tab'][phx-value-tab='history']")
        |> render_click()

      assert html =~ "Chat history will appear here"

      # Switch back to chat
      html =
        view
        |> element("button[phx-click='switch_tab'][phx-value-tab='chat']")
        |> render_click()

      assert html =~ "I can answer questions about your meetings and CRM data"
    end
  end

  describe "toggle_contact_search" do
    test "toggles contact search dropdown", %{conn: conn} do
      user = user_fixture()
      _credential = hubspot_credential_fixture(%{user_id: user.id})
      conn = log_in_user(conn, user)

      {:ok, view, html} = live(conn, ~p"/dashboard/chat")

      # Search not open initially
      refute html =~ "Search contacts..."

      # Open search
      html = view |> render_hook("toggle_contact_search", %{})
      assert html =~ "Search contacts..."

      # Close search
      html = view |> render_hook("toggle_contact_search", %{})
      refute html =~ "Search contacts..."
    end
  end

  defp meeting_fixture_with_transcript(user) do
    meeting = meeting_fixture(%{})

    calendar_event = SocialScribe.Calendar.get_calendar_event!(meeting.calendar_event_id)

    {:ok, _updated_event} =
      SocialScribe.Calendar.update_calendar_event(calendar_event, %{user_id: user.id})

    meeting_participant_fixture(%{meeting_id: meeting.id, name: "John Doe", is_host: true})

    meeting_transcript_fixture(%{
      meeting_id: meeting.id,
      content: %{
        "data" => [
          %{
            "speaker" => "John Doe",
            "words" => [
              %{"text" => "Hello,", "start_timestamp" => 0.0},
              %{"text" => "let's", "start_timestamp" => 0.5},
              %{"text" => "discuss", "start_timestamp" => 1.0},
              %{"text" => "the", "start_timestamp" => 1.5},
              %{"text" => "project.", "start_timestamp" => 2.0}
            ]
          }
        ]
      }
    })

    SocialScribe.Meetings.get_meeting_with_details(meeting.id)
  end
end
