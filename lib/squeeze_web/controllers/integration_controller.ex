defmodule SqueezeWeb.IntegrationController do
  use SqueezeWeb, :controller

  alias Squeeze.Accounts
  alias Squeeze.OAuth2.{Fitbit}

  @strava_auth Application.get_env(:squeeze, :strava_auth)

  def request(conn, %{"provider" => provider}) do
    redirect(conn, external: authorize_url!(provider))
  end

  def callback(conn, %{"provider" => provider, "code" => code}) do
    client = get_token!(provider, code)
    credential_params = get_credential!(provider, client)
    case Accounts.create_credential(conn.assigns.current_user, credential_params) do
      {:ok, _} -> redirect_current_user(conn, provider)
      {:error, _} ->
        conn
        |> put_flash(:error, "Authentication failed for #{provider}")
        |> redirect(to: dashboard_path(conn, :index))
    end
  end

  defp redirect_current_user(conn, provider) do
    conn
    |> put_flash(:info, "Connected to #{provider}")
    |> redirect(to: dashboard_path(conn, :index))
  end

  defp authorize_url!("strava") do
    @strava_auth.authorize_url!(scope: "read,activity:read_all")
  end

  defp authorize_url!("fitbit") do
    Fitbit.authorize_url!(scope: "activity profile")
  end

  defp get_token!("strava", code) do
    @strava_auth.get_token!(code: code, grant_type: "authorization_code")
  end

  defp get_token!("fitbit", code), do: Fitbit.get_token!(code: code)

  defp get_credential!("strava", %{token: token} = client) do
    user = @strava_auth.get_athlete!(client)
    token
    |> Map.take([:access_token, :refresh_token])
    |> Map.merge(%{provider: "strava", uid: "#{user.id}"})
  end

  defp get_credential!("fitbit", client), do: Fitbit.get_credential!(client)
end
