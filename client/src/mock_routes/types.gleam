import gleam/option.{type Option, None}
import protocol/types.{type GameOutcome, Win}

// ROUTE TYPES

pub type Route {
  // Normal app flow (WebSocket connected)
  AppRoute
  // Mock routes (no WebSocket, static state from URL params)
  MockHomeRoute(MockHomeParams)
  MockCreateRoute(MockCreateParams)
  MockJoinRoute(MockJoinParams)
  MockLobbyRoute(MockLobbyParams)
  MockDealingRoute(MockDealingParams)
  MockActiveRoute(MockActiveParams)
  MockPauseRoute(MockPauseParams)
  MockStrikeRoute(MockStrikeParams)
  MockAbandonRoute(MockAbandonParams)
  MockEndRoute(MockEndParams)
}

// PARAMETER TYPES

pub type MockHomeParams {
  MockHomeParams
}

pub type MockCreateParams {
  MockCreateParams(nickname: String)
}

pub type MockJoinParams {
  MockJoinParams(code: String, nickname: String, error: Option(String))
}

pub type MockLobbyParams {
  MockLobbyParams(
    code: String,
    players: Int,
    ready: Int,
    disconnected: Int,
    host: Bool,
  )
}

pub type MockDealingParams {
  MockDealingParams(
    round: Int,
    lives: Int,
    stars: Int,
    cards: List(Int),
    players: Int,
    countdown: Option(Int),
  )
}

pub type MockActiveParams {
  MockActiveParams(
    round: Int,
    lives: Int,
    stars: Int,
    pile: Option(Int),
    cards: List(Int),
    selected: Option(Int),
    players: Int,
  )
}

pub type MockPauseParams {
  MockPauseParams(
    player: String,
    played: Int,
    expected: Int,
    expected_player: String,
    cards: List(Int),
    round: Int,
    lives: Int,
    stars: Int,
  )
}

pub type MockStrikeParams {
  MockStrikeParams(
    votes: Int,
    pending: Int,
    seconds: Int,
    cards: List(Int),
    voted: Bool,
  )
}

pub type MockAbandonParams {
  MockAbandonParams(
    votes: Int,
    pending: Int,
    seconds: Int,
    cards: List(Int),
    voted: Bool,
  )
}

pub type MockEndParams {
  MockEndParams(
    outcome: GameOutcome,
    rounds: Int,
    lives: Int,
    stars: Int,
    games: Int,
  )
}

// DEFAULTS

pub fn default_home_params() -> MockHomeParams {
  MockHomeParams
}

pub fn default_create_params() -> MockCreateParams {
  MockCreateParams(nickname: "")
}

pub fn default_join_params() -> MockJoinParams {
  MockJoinParams(code: "", nickname: "", error: None)
}

pub fn default_lobby_params() -> MockLobbyParams {
  MockLobbyParams(
    code: "MOCK01",
    players: 2,
    ready: 0,
    disconnected: 0,
    host: True,
  )
}

pub fn default_dealing_params() -> MockDealingParams {
  MockDealingParams(
    round: 1,
    lives: 3,
    stars: 1,
    cards: [12, 34, 56],
    players: 2,
    countdown: None,
  )
}

pub fn default_active_params() -> MockActiveParams {
  MockActiveParams(
    round: 1,
    lives: 3,
    stars: 1,
    pile: option.Some(10),
    cards: [23, 45, 67],
    selected: None,
    players: 2,
  )
}

pub fn default_pause_params() -> MockPauseParams {
  MockPauseParams(
    player: "Alice",
    played: 42,
    expected: 38,
    expected_player: "Bob",
    cards: [50, 60],
    round: 1,
    lives: 2,
    stars: 1,
  )
}

pub fn default_strike_params() -> MockStrikeParams {
  MockStrikeParams(
    votes: 1,
    pending: 1,
    seconds: 8,
    cards: [25, 50],
    voted: False,
  )
}

pub fn default_abandon_params() -> MockAbandonParams {
  MockAbandonParams(
    votes: 1,
    pending: 1,
    seconds: 8,
    cards: [25, 50],
    voted: False,
  )
}

pub fn default_end_params() -> MockEndParams {
  MockEndParams(outcome: Win, rounds: 8, lives: 1, stars: 0, games: 1)
}
