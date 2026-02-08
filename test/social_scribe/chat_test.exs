defmodule SocialScribe.ChatTest do
  use SocialScribe.DataCase

  alias SocialScribe.Chat

  import SocialScribe.AccountsFixtures
  import SocialScribe.MeetingsFixtures
  import Mox

  setup :verify_on_exit!

  describe "search_contacts/2" do
    test "delegates to HubSpot API for hubspot provider" do
      user = user_fixture()
      credential = hubspot_credential_fixture(%{user_id: user.id})

      expected = [
        %{id: "123", firstname: "John", lastname: "Doe", email: "john@example.com"}
      ]

      SocialScribe.HubspotApiMock
      |> expect(:search_contacts, fn _cred, query ->
        assert query == "John"
        {:ok, expected}
      end)

      assert {:ok, ^expected} = Chat.search_contacts(credential, "John")
    end

    test "delegates to Salesforce API for salesforce provider" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      expected = [
        %{id: "456", firstname: "Jane", lastname: "Smith", email: "jane@example.com"}
      ]

      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _cred, query ->
        assert query == "Jane"
        {:ok, expected}
      end)

      assert {:ok, ^expected} = Chat.search_contacts(credential, "Jane")
    end

    test "returns error for unsupported provider" do
      user = user_fixture()
      credential = user_credential_fixture(%{user_id: user.id, provider: "unknown"})

      assert {:error, :unsupported_provider} = Chat.search_contacts(credential, "test")
    end

    test "propagates API errors" do
      user = user_fixture()
      credential = hubspot_credential_fixture(%{user_id: user.id})

      SocialScribe.HubspotApiMock
      |> expect(:search_contacts, fn _cred, _query ->
        {:error, :api_error}
      end)

      assert {:error, :api_error} = Chat.search_contacts(credential, "test")
    end
  end

  describe "ask_question/4" do
    setup do
      user = user_fixture()
      credential = hubspot_credential_fixture(%{user_id: user.id})

      contact = %{
        id: "123",
        firstname: "John",
        lastname: "Doe",
        provider: "hubspot"
      }

      %{user: user, credential: credential, contact: contact}
    end

    test "returns answer and sources on success", %{
      user: user,
      credential: credential,
      contact: contact
    } do
      meeting = meeting_fixture_with_transcript(user)

      SocialScribe.HubspotApiMock
      |> expect(:get_contact, fn _cred, contact_id ->
        assert contact_id == "123"
        {:ok, %{"firstname" => "John", "lastname" => "Doe", "email" => "john@example.com"}}
      end)

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_chat_response, fn prompt ->
        assert prompt =~ "John"
        assert prompt =~ "CRM assistant"
        {:ok, "John Doe is a key contact from Acme Corp."}
      end)

      assert {:ok, %{answer: answer, sources: sources}} =
               Chat.ask_question("Tell me about John", contact, credential, user)

      assert answer == "John Doe is a key contact from Acme Corp."
      assert [%{title: "Scribe"} | _] = sources
      assert Enum.any?(sources, fn s -> s.title == meeting.title end)
    end

    test "returns error when contact data fetch fails", %{
      user: user,
      credential: credential,
      contact: contact
    } do
      SocialScribe.HubspotApiMock
      |> expect(:get_contact, fn _cred, _id ->
        {:error, :api_error}
      end)

      assert {:error, :api_error} =
               Chat.ask_question("Tell me about John", contact, credential, user)
    end

    test "returns error when AI generation fails", %{
      user: user,
      credential: credential,
      contact: contact
    } do
      _meeting = meeting_fixture_with_transcript(user)

      SocialScribe.HubspotApiMock
      |> expect(:get_contact, fn _cred, _id ->
        {:ok, %{"firstname" => "John"}}
      end)

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_chat_response, fn _prompt ->
        {:error, :ai_unavailable}
      end)

      assert {:error, :ai_unavailable} =
               Chat.ask_question("Tell me about John", contact, credential, user)
    end

    test "works with salesforce provider" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})
      contact = %{id: "sf-1", firstname: "Jane", lastname: "Smith", provider: "salesforce"}

      _meeting = meeting_fixture_with_transcript(user)

      SocialScribe.SalesforceApiMock
      |> expect(:get_contact, fn _cred, contact_id ->
        assert contact_id == "sf-1"
        {:ok, %{"Name" => "Jane Smith", "Email" => "jane@example.com"}}
      end)

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_chat_response, fn _prompt ->
        {:ok, "Jane Smith works at Tech Inc."}
      end)

      assert {:ok, %{answer: "Jane Smith works at Tech Inc.", sources: sources}} =
               Chat.ask_question("Tell me about Jane", contact, credential, user)

      assert Enum.any?(sources, fn s -> s.provider == "salesforce" end)
    end

    test "includes meeting context in prompt", %{
      user: user,
      credential: credential,
      contact: contact
    } do
      _meeting = meeting_fixture_with_transcript(user)

      SocialScribe.HubspotApiMock
      |> expect(:get_contact, fn _cred, _id ->
        {:ok, %{"firstname" => "John"}}
      end)

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_chat_response, fn prompt ->
        assert prompt =~ "Meeting Transcripts"
        assert prompt =~ "Hello,"
        {:ok, "Answer based on meetings."}
      end)

      assert {:ok, _} =
               Chat.ask_question("What was discussed?", contact, credential, user)
    end

    test "handles user with no meetings", %{
      user: user,
      credential: credential,
      contact: contact
    } do
      SocialScribe.HubspotApiMock
      |> expect(:get_contact, fn _cred, _id ->
        {:ok, %{"firstname" => "John"}}
      end)

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_chat_response, fn prompt ->
        assert prompt =~ "No meeting transcripts available"
        {:ok, "No meeting data found for this contact."}
      end)

      assert {:ok, %{answer: answer}} =
               Chat.ask_question("What was discussed?", contact, credential, user)

      assert answer =~ "No meeting data"
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
