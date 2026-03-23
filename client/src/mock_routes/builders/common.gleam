import gleam/int
import gleam/list
import gleam/option.{type Option, None}
import gleam/time/timestamp.{type Timestamp}
import mock_routes/types as mock_types
import protocol/helpers
import protocol/types.{
  type Game, type GameEvent, type Lobby, type MistakeInfo, type Phase, Game,
  GamePlayer, Lobby, Player,
}

// CONSTANTS

const mock_user_id = "mock-user-001"

const mock_timestamp = 0

pub fn get_mock_user_id() -> String {
  mock_user_id
}

pub fn make_mock_timestamp() -> Timestamp {
  helpers.unix_ms_to_timestamp(mock_timestamp)
}

/// Create a mock timestamp at offset milliseconds from game start
pub fn make_mock_timestamp_at(offset_ms: Int) -> Timestamp {
  helpers.unix_ms_to_timestamp(mock_timestamp + offset_ms)
}

// HELPERS

pub fn generate_player_names(count: Int) -> List(String) {
  let names = ["Alice", "Bob", "Charlie", "Diana"]
  names |> list.take(count)
}

// MOCK GAME PARAMS

pub type MockGameParams {
  MockGameParams(
    round: Int,
    lives: Int,
    stars: Int,
    my_cards: List(Int),
    player_count: Int,
    played_cards: List(Int),
    last_mistake: Option(MistakeInfo),
    game_log: List(GameEvent),
  )
}

// LOBBY BUILDER

pub fn build_mock_lobby(params: mock_types.MockLobbyParams) -> Lobby {
  let player_names = generate_player_names(params.players)

  let players =
    player_names
    |> list.index_map(fn(name, idx) {
      let is_first = idx == 0
      let is_ready = idx < params.ready
      let is_disconnected = idx >= params.players - params.disconnected

      Player(
        user_id: case is_first && params.host {
          True -> mock_user_id
          False -> "player-" <> int.to_string(idx)
        },
        nickname: name,
        is_ready: is_ready,
        is_creator: is_first,
        is_connected: !is_disconnected,
      )
    })

  Lobby(code: params.code, players: players, games_played: 0)
}

// GAME BUILDER

pub fn build_mock_game(phase: Phase, params: MockGameParams) -> Game {
  let player_names = generate_player_names(params.player_count)

  let players =
    player_names
    |> list.index_map(fn(name, idx) {
      let is_first = idx == 0
      let hand = case is_first {
        True -> params.my_cards
        False ->
          // Other players have some cards
          int.range(from: 1, to: params.round, with: [], run: fn(acc, i) {
            [i * 10 + idx, ..acc]
          })
          |> list.reverse
      }

      GamePlayer(
        user_id: case is_first {
          True -> mock_user_id
          False -> "player-" <> int.to_string(idx)
        },
        nickname: name,
        hand: hand,
        is_ready: False,
        is_connected: True,
        last_card_played: None,
      )
    })

  Game(
    code: "MOCK01",
    host_user_id: mock_user_id,
    games_played: 0,
    players: players,
    current_round: params.round,
    total_rounds: 8,
    lives: params.lives,
    strikes: params.stars,
    phase: phase,
    played_cards: params.played_cards,
    last_mistake: params.last_mistake,
    abandon_vote_previous_phase: None,
    game_start_timestamp: make_mock_timestamp(),
    game_log: params.game_log,
  )
}
