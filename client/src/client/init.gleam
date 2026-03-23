import client/effects
import client/model.{
  type Model, type Screen, CreateScreen, GameScreen, HomeScreen, JoinScreen,
  LobbyScreen, Model, ToastHidden,
}
import client/msg.{type Msg, OnRouteChange}
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/uri
import lustre/effect
import mock_routes/builders/common as builders_common
import mock_routes/builders/phases as builders_phases
import mock_routes/parsing
import mock_routes/types.{
  type Route, AppRoute, MockAbandonRoute, MockActiveRoute, MockCreateRoute,
  MockDealingRoute, MockEndRoute, MockHomeRoute, MockJoinRoute, MockLobbyRoute,
  MockPauseRoute, MockStrikeRoute,
}
import modem
import protocol/types as protocol

pub fn init(_flags) -> #(Model, effect.Effect(Msg)) {
  let initial_uri = modem.initial_uri()

  let initial_route =
    initial_uri
    |> result.map(parsing.parse_route)
    |> result.unwrap(AppRoute)

  // Use mock user ID for mock routes, real user ID for app route
  let user_id = case initial_route {
    AppRoute -> effects.get_or_create_user_id()
    _ -> builders_common.get_mock_user_id()
  }

  io.println("[Client] User ID: " <> user_id)
  io.println(
    "[Client] Initial route: "
    <> case initial_route {
      AppRoute -> "AppRoute"
      _ -> "MockRoute"
    },
  )

  // Build initial state from mock route if applicable
  let #(
    initial_lobby,
    initial_game,
    initial_screen,
    initial_countdown,
    initial_vote_status,
    initial_abandon_vote_status,
  ) = build_initial_state_from_route(initial_route)

  // Extract form field values from mock routes or query params
  let #(create_nickname, join_code, join_nickname, error, screen_override) = case
    initial_route
  {
    MockCreateRoute(params) -> #(params.nickname, "", "", None, None)
    MockJoinRoute(params) -> #(
      "",
      params.code,
      params.nickname,
      params.error,
      None,
    )
    AppRoute -> {
      // Check for ?code= query parameter to pre-fill join screen
      let code_from_url = case initial_uri {
        Ok(u) ->
          case u.query {
            Some(query_string) ->
              case uri.parse_query(query_string) {
                Ok(params) ->
                  list.find(params, fn(p) { p.0 == "code" })
                  |> result.map(fn(p) { p.1 })
                  |> option.from_result
                Error(_) -> None
              }
            None -> None
          }
        Error(_) -> None
      }

      case code_from_url {
        Some(code) -> #("", code, "", None, Some(JoinScreen))
        None -> #("", "", "", None, None)
      }
    }
    _ -> #("", "", "", None, None)
  }

  let final_screen = option.unwrap(screen_override, initial_screen)

  let model =
    Model(
      route: initial_route,
      screen: final_screen,
      user_id: user_id,
      current_lobby: initial_lobby,
      current_game: initial_game,
      countdown: initial_countdown,
      create_nickname: create_nickname,
      join_code: join_code,
      join_nickname: join_nickname,
      error: error,
      vote_status: initial_vote_status,
      abandon_vote_status: initial_abandon_vote_status,
      toast: ToastHidden,
      is_reward_guide_open: False,
    )

  // Only connect WebSocket for AppRoute
  let effects = case initial_route {
    AppRoute ->
      effect.batch([
        modem.init(OnRouteChange),
        effect.from(fn(dispatch) {
          effects.connect_websocket(dispatch)
          effects.check_saved_game(dispatch)
        }),
      ])
    _ -> modem.init(OnRouteChange)
  }

  #(model, effects)
}

pub fn build_initial_state_from_route(
  route: Route,
) -> #(
  Option(protocol.Lobby),
  Option(protocol.Game),
  Screen,
  Option(Int),
  Option(#(List(#(String, Bool)), List(String), Int)),
  Option(#(List(#(String, Bool)), List(String), Int)),
) {
  case route {
    AppRoute -> #(None, None, HomeScreen, None, None, None)

    MockHomeRoute(_params) -> #(None, None, HomeScreen, None, None, None)

    MockCreateRoute(_params) -> #(None, None, CreateScreen, None, None, None)

    MockJoinRoute(_params) -> #(None, None, JoinScreen, None, None, None)

    MockLobbyRoute(params) -> {
      let lobby = builders_common.build_mock_lobby(params)
      #(Some(lobby), None, LobbyScreen, None, None, None)
    }

    MockDealingRoute(params) -> {
      let game = builders_phases.build_mock_game_dealing(params)
      #(None, Some(game), GameScreen, params.countdown, None, None)
    }

    MockActiveRoute(params) -> {
      let game = builders_phases.build_mock_game_active(params)
      #(None, Some(game), GameScreen, None, None, None)
    }

    MockPauseRoute(params) -> {
      let game = builders_phases.build_mock_game_pause(params)
      #(None, Some(game), GameScreen, None, None, None)
    }

    MockStrikeRoute(params) -> {
      let game = builders_phases.build_mock_game_strike(params)
      let vote_status =
        builders_phases.build_mock_vote_status(
          params.votes,
          params.pending,
          params.seconds,
          params.voted,
        )
      #(None, Some(game), GameScreen, None, Some(vote_status), None)
    }

    MockAbandonRoute(params) -> {
      let game = builders_phases.build_mock_game_abandon(params)
      let abandon_vote_status =
        builders_phases.build_mock_vote_status(
          params.votes,
          params.pending,
          params.seconds,
          params.voted,
        )
      #(None, Some(game), GameScreen, None, None, Some(abandon_vote_status))
    }

    MockEndRoute(params) -> {
      let game = builders_phases.build_mock_game_end(params)
      #(None, Some(game), GameScreen, None, None, None)
    }
  }
}
