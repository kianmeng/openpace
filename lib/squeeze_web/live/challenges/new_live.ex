defmodule SqueezeWeb.Challenges.NewLive do
  use SqueezeWeb, :live_view

  alias Squeeze.Accounts
  alias Squeeze.Challenges
  alias Squeeze.Challenges.Challenge
  alias Squeeze.Guardian
  alias Squeeze.Strava.Client

  @strava_segments Application.get_env(:squeeze, :strava_segments)

  @impl true
  def mount(%{"challenge_type" => type}, session, socket) do
    type = String.to_atom(type)
    changeset = Challenges.change_challenge(%Challenge{challenge_type: type, activity_type: :run})

    if connected?(socket) && type == :segment do
      send(self(), :fetch_segments)
    end

    socket = socket
    |> assign_new(:current_user, fn -> get_current_user(session) end)
    |> assign(loading: true, segments: [], segment: nil)
    |> assign(changeset: changeset)
    |> assign(challenge_type: type)

    {:ok, socket}
  end

  @impl true
  def handle_event("reload", _params, socket) do
    send(self(), :fetch_segments)
    {:noreply, assign(socket, loading: true)}
  end

  @impl true
  def handle_event("select_segment", %{"id" => segment_id}, socket) do
    send(self(), {:fetch_segment, segment_id})
    {:noreply, socket}
  end

  @impl true
  def handle_event("save", %{"challenge" => params}, socket) do
    user = socket.assigns.current_user

    with {:ok, challenge} <- Challenges.create_challenge(user, params),
         {:ok, _} <- Challenges.add_user_to_challenge(user, challenge) do

      socket = socket
      |> put_flash(:info, "Challenge Created")

      {:noreply, socket}
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  @impl true
  def handle_info(:fetch_segments, socket) do
    user = socket.assigns.current_user

    with {:ok, credential} <- Accounts.fetch_credential_by_provider(user, "strava"),
         {:ok, segments} <- get_strava_segments(credential) do
      {:noreply, assign(socket, segments: segments, credential: credential, loading: false)}
    else
      _ ->
        {:noreply, assign(socket, segments: [], loading: false)}
    end
  end

  @impl true
  def handle_info({:fetch_segment, id}, socket) do
    credential = socket.assigns.credential

    case get_strava_segment(credential, id) do
      {:ok, segment} ->
        socket = socket
        |> assign(segment: segment)

        {:noreply, socket}
      _ -> {:noreply, socket}
    end
  end

  defp get_current_user(%{"guardian_default_token" => token}) do
    case Guardian.resource_from_token(token) do
      {:ok, user, _claims} -> user
      _ -> nil
    end
  end
  defp get_current_user(_), do: nil

  defp get_strava_segments(credential) do
    opts = [
      per_page: 50,
      page: 1,
    ]
    Client.new(credential)
    |> @strava_segments.get_logged_in_athlete_starred_segments(opts)
  end

  defp get_strava_segment(credential, id) do
    Client.new(credential)
    |> @strava_segments.get_segment_by_id(id)
  end
end
