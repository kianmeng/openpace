defmodule SqueezeWeb.Dashboard.OverviewLive do
  use SqueezeWeb, :live_view
  @moduledoc false

  alias Squeeze.Accounts.User
  alias Squeeze.Challenges
  alias Squeeze.Dashboard
  alias Squeeze.Races
  alias Squeeze.Stats
  alias Squeeze.Strava.HistoryLoader
  alias Squeeze.TimeHelper
  alias SqueezeWeb.Endpoint

  import Squeeze.Distances, only: [distance_name: 2]

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    summaries = Dashboard.list_activity_summaries(user)
    activity_map = activity_map(summaries)
    race_goals = Races.list_upcoming_race_goals(user)

    socket = assign(socket,
      page_title: "Dashboard",
      current_user: user,
      activity_map: activity_map,
      activity_summaries: summaries,
      challenges: Challenges.list_current_challenges(user),
      current_streak: Stats.current_activity_streak(user),
      loading: false,
      race_goal: List.first(race_goals),
      race_goals: race_goals,
      todays_activities: Dashboard.todays_activities(user),
      ytd_run_stats: Stats.ytd_run_summary(user)
    )

    {:ok, socket}
  end

  @impl true
  def handle_event("load-week", params, socket) do
    {:noreply, push_patch(socket, to: Routes.overview_path(socket, :index, date: params["date"]), replace: true)}
  end

  @impl true
  def handle_info(:start_history_loader, socket) do
    send(self(), :load_recent_history)
    {:noreply, assign(socket, loading: true)}
  end

  @impl true
  def handle_info(:load_recent_history, socket) do
    user = socket.assigns.current_user
    credential = Enum.find(user.credentials, &(&1.provider == "strava"))
    HistoryLoader.load_recent(user, credential)

    socket = socket
    |> redirect(to: Routes.overview_path(Endpoint, :index))

    {:noreply, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    user = socket.assigns.current_user
    date = parse_date(user, params["date"])
    dates = Date.range(Timex.beginning_of_week(date), Timex.end_of_week(date))
    activities = Dashboard.list_activities(user, dates)

    socket = assign(socket,
      activities: activities,
      date: date
    )
    {:noreply, socket}
  end

  defp personal_records(%{current_user: user}) do
    user.user_prefs.personal_records
    |> Enum.reject(&(is_nil(&1.duration) || &1.duration == 0))
    |> Enum.sort_by(&(&1.distance))
  end

  defp activity_map(summaries) do
    summaries
    |> Enum.reduce(%{}, fn(x, acc) ->
      date = x.start_at_local |> Timex.to_date()
      list = Map.get(acc, date, [])
      Map.put(acc, date, [x | list])
    end)
  end

  defp parse_date(%User{} = user, nil), do: TimeHelper.today(user)
  defp parse_date(%User{} = user, date) do
    case Timex.parse(date, "{YYYY}-{0M}-{0D}") do
      {:ok, date} -> date
      {:error, _} -> parse_date(user, nil)
    end
  end
end
