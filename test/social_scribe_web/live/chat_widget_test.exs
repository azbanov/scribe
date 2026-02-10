defmodule SocialScribeWeb.ChatWidgetTest do
  use SocialScribeWeb.ConnCase

  import Phoenix.LiveViewTest
  import SocialScribe.AccountsFixtures
  import Mox

  setup :verify_on_exit!

  describe "chat widget contact search" do
    setup %{conn: conn} do
      user = user_fixture()
      hubspot_credential = hubspot_credential_fixture(%{user_id: user.id})

      %{
        conn: log_in_user(conn, user),
        user: user,
        hubspot_credential: hubspot_credential
      }
    end

    test "shows 'No contacts found' after search completes with empty results", %{conn: conn} do
      SocialScribe.HubspotApiMock
      |> expect(:search_contacts, fn _cred, _query ->
        {:ok, []}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/settings")

      view
      |> element("button", "Add context")
      |> render_click()

      view
      |> element("input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "NonExistent"})

      :timer.sleep(200)

      html = render(view)
      refute html =~ "Searching..."
      assert html =~ "No contacts found"
    end

    test "hides 'No contacts found' when results are returned", %{conn: conn} do
      mock_contacts = [
        %{
          id: "123",
          firstname: "John",
          lastname: "Doe",
          email: "john@example.com"
        }
      ]

      SocialScribe.HubspotApiMock
      |> expect(:search_contacts, fn _cred, _query ->
        {:ok, mock_contacts}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/settings")

      view
      |> element("button", "Add context")
      |> render_click()

      view
      |> element("input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "John"})

      :timer.sleep(200)

      html = render(view)
      refute html =~ "Searching..."
      refute html =~ "No contacts found"
      assert html =~ "John Doe"
      assert html =~ "john@example.com"
    end

    test "does not show 'No contacts found' when query is too short", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/settings")

      view
      |> element("button", "Add context")
      |> render_click()

      view
      |> element("input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "J"})

      html = render(view)
      refute html =~ "Searching..."
      refute html =~ "No contacts found"
    end

    test "does not show 'No contacts found' when query is empty", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/settings")

      view
      |> element("button", "Add context")
      |> render_click()

      view
      |> element("input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => ""})

      html = render(view)
      refute html =~ "Searching..."
      refute html =~ "No contacts found"
    end
  end
end
