import gleam/list
import gleam/time/timestamp.{type Timestamp}
import protocol/types.{type Card, type Game}

/// Convert Timestamp to Unix milliseconds for JSON serialization
pub fn timestamp_to_unix_ms(ts: Timestamp) -> Int {
  let #(seconds, nanos) = timestamp.to_unix_seconds_and_nanoseconds(ts)
  seconds * 1000 + nanos / 1_000_000
}

/// Convert Unix milliseconds to Timestamp
pub fn unix_ms_to_timestamp(ms: Int) -> Timestamp {
  let seconds = ms / 1000
  let nanos = { ms % 1000 } * 1_000_000
  timestamp.from_unix_seconds_and_nanoseconds(seconds, nanos)
}

/// Get player's hand from game by user_id
pub fn get_player_hand(game: Game, user_id: String) -> List(Card) {
  game.players
  |> list.find(fn(p) { p.user_id == user_id })
  |> fn(result) {
    case result {
      Ok(player) -> player.hand
      Error(_) -> []
    }
  }
}

/// Get player's ready status from game by user_id
pub fn is_player_ready_in_game(game: Game, user_id: String) -> Bool {
  game.players
  |> list.find(fn(p) { p.user_id == user_id })
  |> fn(result) {
    case result {
      Ok(player) -> player.is_ready
      Error(_) -> False
    }
  }
}
