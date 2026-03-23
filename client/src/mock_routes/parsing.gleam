import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/uri.{type Uri}
import mock_routes/types.{
  type MockAbandonParams, type MockActiveParams, type MockCreateParams,
  type MockDealingParams, type MockEndParams, type MockHomeParams,
  type MockJoinParams, type MockLobbyParams, type MockPauseParams,
  type MockStrikeParams, type Route, AppRoute, MockAbandonParams,
  MockAbandonRoute, MockActiveParams, MockActiveRoute, MockCreateParams,
  MockCreateRoute, MockDealingParams, MockDealingRoute, MockEndParams,
  MockEndRoute, MockHomeParams, MockHomeRoute, MockJoinParams, MockJoinRoute,
  MockLobbyParams, MockLobbyRoute, MockPauseParams, MockPauseRoute,
  MockStrikeParams, MockStrikeRoute,
}
import protocol/types as protocol

// ROUTE PARSING

pub fn parse_route(uri: Uri) -> Route {
  let path_segments =
    uri.path
    |> string.split("/")
    |> list.filter(fn(s) { s != "" })

  case path_segments {
    ["mock", "home"] -> MockHomeRoute(parse_home_params(uri.query))
    ["mock", "create"] -> MockCreateRoute(parse_create_params(uri.query))
    ["mock", "join"] -> MockJoinRoute(parse_join_params(uri.query))
    ["mock", "lobby"] -> MockLobbyRoute(parse_lobby_params(uri.query))
    ["mock", "dealing"] -> MockDealingRoute(parse_dealing_params(uri.query))
    ["mock", "active"] -> MockActiveRoute(parse_active_params(uri.query))
    ["mock", "pause"] -> MockPauseRoute(parse_pause_params(uri.query))
    ["mock", "strike"] -> MockStrikeRoute(parse_strike_params(uri.query))
    ["mock", "abandon"] -> MockAbandonRoute(parse_abandon_params(uri.query))
    ["mock", "end"] -> MockEndRoute(parse_end_params(uri.query))
    _ -> AppRoute
  }
}

// QUERY PARAM PARSING HELPERS

fn get_param(params: List(#(String, String)), key: String) -> Option(String) {
  params
  |> list.find(fn(p) { p.0 == key })
  |> result.map(fn(p) { p.1 })
  |> option.from_result
}

fn get_int_param(
  params: List(#(String, String)),
  key: String,
  default: Int,
) -> Int {
  get_param(params, key)
  |> option.then(fn(s) { int.parse(s) |> option.from_result })
  |> option.unwrap(default)
}

fn get_bool_param(
  params: List(#(String, String)),
  key: String,
  default: Bool,
) -> Bool {
  case get_param(params, key) {
    Some("true") | Some("1") -> True
    Some("false") | Some("0") -> False
    _ -> default
  }
}

fn get_string_param(
  params: List(#(String, String)),
  key: String,
  default: String,
) -> String {
  get_param(params, key)
  |> option.unwrap(default)
}

fn get_int_list_param(
  params: List(#(String, String)),
  key: String,
  default: List(Int),
) -> List(Int) {
  case get_param(params, key) {
    Some(s) ->
      s
      |> string.split(",")
      |> list.filter_map(int.parse)
    None -> default
  }
}

fn parse_query(query: Option(String)) -> List(#(String, String)) {
  case query {
    None -> []
    Some(q) -> uri.parse_query(q) |> result.unwrap([])
  }
}

// PARAM PARSERS

fn parse_home_params(_query: Option(String)) -> MockHomeParams {
  MockHomeParams
}

fn parse_create_params(query: Option(String)) -> MockCreateParams {
  let defaults = types.default_create_params()
  let params = parse_query(query)

  MockCreateParams(nickname: get_string_param(
    params,
    "nickname",
    defaults.nickname,
  ))
}

fn parse_join_params(query: Option(String)) -> MockJoinParams {
  let defaults = types.default_join_params()
  let params = parse_query(query)

  let error = case get_param(params, "error") {
    Some("invalid") -> Some("Invalid game code")
    Some("full") -> Some("Game is full")
    Some("not_found") -> Some("Game not found")
    Some(e) -> Some(e)
    None -> None
  }

  MockJoinParams(
    code: get_string_param(params, "code", defaults.code),
    nickname: get_string_param(params, "nickname", defaults.nickname),
    error: error,
  )
}

fn parse_lobby_params(query: Option(String)) -> MockLobbyParams {
  let defaults = types.default_lobby_params()
  let params = parse_query(query)

  MockLobbyParams(
    code: get_string_param(params, "code", defaults.code),
    players: get_int_param(params, "players", defaults.players),
    ready: get_int_param(params, "ready", defaults.ready),
    disconnected: get_int_param(params, "disconnected", defaults.disconnected),
    host: get_bool_param(params, "host", defaults.host),
  )
}

fn parse_dealing_params(query: Option(String)) -> MockDealingParams {
  let defaults = types.default_dealing_params()
  let params = parse_query(query)

  let countdown_value = get_int_param(params, "countdown", -1)

  MockDealingParams(
    round: get_int_param(params, "round", defaults.round),
    lives: get_int_param(params, "lives", defaults.lives),
    stars: get_int_param(params, "stars", defaults.stars),
    cards: get_int_list_param(params, "cards", defaults.cards),
    players: get_int_param(params, "players", defaults.players),
    countdown: case countdown_value >= 0 {
      True -> Some(countdown_value)
      False -> None
    },
  )
}

fn parse_active_params(query: Option(String)) -> MockActiveParams {
  let defaults = types.default_active_params()
  let params = parse_query(query)

  let pile_value = get_int_param(params, "pile", -1)
  let selected_value = get_int_param(params, "selected", -1)

  MockActiveParams(
    round: get_int_param(params, "round", defaults.round),
    lives: get_int_param(params, "lives", defaults.lives),
    stars: get_int_param(params, "stars", defaults.stars),
    pile: case pile_value >= 0 {
      True -> Some(pile_value)
      False -> defaults.pile
    },
    cards: get_int_list_param(params, "cards", defaults.cards),
    selected: case selected_value >= 0 {
      True -> Some(selected_value)
      False -> None
    },
    players: get_int_param(params, "players", defaults.players),
  )
}

fn parse_pause_params(query: Option(String)) -> MockPauseParams {
  let defaults = types.default_pause_params()
  let params = parse_query(query)

  MockPauseParams(
    player: get_string_param(params, "player", defaults.player),
    played: get_int_param(params, "played", defaults.played),
    expected: get_int_param(params, "expected", defaults.expected),
    expected_player: get_string_param(
      params,
      "expected_player",
      defaults.expected_player,
    ),
    cards: get_int_list_param(params, "cards", defaults.cards),
    round: get_int_param(params, "round", defaults.round),
    lives: get_int_param(params, "lives", defaults.lives),
    stars: get_int_param(params, "stars", defaults.stars),
  )
}

fn parse_strike_params(query: Option(String)) -> MockStrikeParams {
  let defaults = types.default_strike_params()
  let params = parse_query(query)

  MockStrikeParams(
    votes: get_int_param(params, "votes", defaults.votes),
    pending: get_int_param(params, "pending", defaults.pending),
    seconds: get_int_param(params, "seconds", defaults.seconds),
    cards: get_int_list_param(params, "cards", defaults.cards),
    voted: get_bool_param(params, "voted", defaults.voted),
  )
}

fn parse_abandon_params(query: Option(String)) -> MockAbandonParams {
  let defaults = types.default_abandon_params()
  let params = parse_query(query)

  MockAbandonParams(
    votes: get_int_param(params, "votes", defaults.votes),
    pending: get_int_param(params, "pending", defaults.pending),
    seconds: get_int_param(params, "seconds", defaults.seconds),
    cards: get_int_list_param(params, "cards", defaults.cards),
    voted: get_bool_param(params, "voted", defaults.voted),
  )
}

fn parse_end_params(query: Option(String)) -> MockEndParams {
  let defaults = types.default_end_params()
  let params = parse_query(query)

  let outcome = case get_param(params, "outcome") {
    Some("win") -> protocol.Win
    Some("loss") -> protocol.Loss
    Some("abandoned") -> protocol.Abandoned
    _ -> defaults.outcome
  }

  MockEndParams(
    outcome: outcome,
    rounds: get_int_param(params, "rounds", defaults.rounds),
    lives: get_int_param(params, "lives", defaults.lives),
    stars: get_int_param(params, "stars", defaults.stars),
    games: get_int_param(params, "games", defaults.games),
  )
}
