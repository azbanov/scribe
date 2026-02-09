defmodule SocialScribe.Workers.SalesforceTokenRefresher do
  @moduledoc """
  Oban worker that periodically refreshes Salesforce tokens that are about to expire.
  Runs as a cron job to proactively refresh tokens before they expire.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias SocialScribe.Accounts
  alias SocialScribe.SalesforceTokenRefresher

  require Logger

  @refresh_threshold_minutes 10

  @impl Oban.Worker
  def perform(_job) do
    Logger.info("Running Salesforce token refresh check...")

    threshold = DateTime.add(DateTime.utc_now(), @refresh_threshold_minutes, :minute)

    credentials =
      Accounts.list_credentials_by_provider("salesforce")
      |> Enum.filter(fn cred ->
        cred.expires_at != nil and DateTime.compare(cred.expires_at, threshold) != :gt
      end)

    if Enum.empty?(credentials) do
      Logger.debug("No Salesforce tokens need refreshing")
      :ok
    else
      Logger.info("Found #{length(credentials)} Salesforce tokens to refresh")

      results =
        Enum.map(credentials, fn credential ->
          case SalesforceTokenRefresher.refresh_credential(credential) do
            {:ok, _updated} ->
              Logger.info(
                "Successfully refreshed Salesforce token for user #{credential.user_id}"
              )

              :ok

            {:error, reason} ->
              Logger.error(
                "Failed to refresh Salesforce token for user #{credential.user_id}: #{inspect(reason)}"
              )

              :error
          end
        end)

      successful = Enum.count(results, &(&1 == :ok))
      failed = Enum.count(results, &(&1 == :error))

      Logger.info(
        "Salesforce token refresh completed: #{successful} successful, #{failed} failed"
      )

      :ok
    end
  end
end
