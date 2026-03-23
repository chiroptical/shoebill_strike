import gleam/list
import gleam/option.{type Option}
import gleam/string
import protocol/types.{type Lobby, type Player, Lobby, Player}

/// Generate a unique 6-character game code
pub fn generate_code(random_fn: fn() -> Int) -> String {
  let chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
  let char_list = string.to_graphemes(chars)
  let char_count = list.length(char_list)

  list.repeat(0, 6)
  |> list.map(fn(_) {
    let index = random_fn() % char_count
    case list.first(list.drop(char_list, index)) {
      Ok(char) -> char
      Error(_) -> "A"
    }
  })
  |> string.join("")
}

/// Create a new lobby with the first player as creator
pub fn create_lobby(code: String, user_id: String, nickname: String) -> Lobby {
  let creator =
    Player(
      user_id: user_id,
      nickname: nickname,
      is_ready: False,
      is_creator: True,
      is_connected: True,
    )
  Lobby(code: code, players: [creator], games_played: 0)
}

/// Add a player to an existing lobby (or reconnect if user_id exists)
pub fn add_player(
  lobby: Lobby,
  user_id: String,
  nickname: String,
) -> Result(Lobby, String) {
  // First, check if this user_id already exists (reconnection scenario)
  let existing_user =
    lobby.players
    |> list.find(fn(p) { p.user_id == user_id })

  case existing_user {
    Ok(old_player) -> {
      // Reconnection: reset ready status, mark as connected
      let reconnected_player =
        Player(
          user_id: user_id,
          nickname: old_player.nickname,
          is_ready: False,
          is_creator: old_player.is_creator,
          is_connected: True,
        )
      let updated_players =
        lobby.players
        |> list.filter(fn(p) { p.user_id != user_id })
        |> list.prepend(reconnected_player)
      Ok(Lobby(..lobby, players: updated_players))
    }
    Error(_) -> {
      // New player - check if lobby is full (max 4 players)
      let player_count = list.length(lobby.players)
      case player_count >= 4 {
        True -> Error("Lobby is full")
        False -> {
          // Check if nickname is already taken
          let nickname_taken =
            lobby.players
            |> list.any(fn(p) { p.nickname == nickname })

          case nickname_taken {
            True -> Error("Nickname already in use")
            False -> {
              let new_player =
                Player(
                  user_id: user_id,
                  nickname: nickname,
                  is_ready: False,
                  is_creator: False,
                  is_connected: True,
                )
              Ok(Lobby(..lobby, players: [new_player, ..lobby.players]))
            }
          }
        }
      }
    }
  }
}

/// Remove a player from a lobby
pub fn remove_player(lobby: Lobby, user_id: String) -> Lobby {
  Lobby(
    ..lobby,
    players: list.filter(lobby.players, fn(p) { p.user_id != user_id }),
  )
}

/// Toggle a player's ready status
pub fn toggle_ready(lobby: Lobby, user_id: String) -> Result(Lobby, String) {
  // Require at least 2 players to ready up
  case list.length(lobby.players) < 2 {
    True -> Error("Need at least 2 players")
    False -> {
      let updated_players =
        lobby.players
        |> list.map(fn(player) {
          case player.user_id == user_id {
            True -> Player(..player, is_ready: !player.is_ready)
            False -> player
          }
        })

      // Check if player exists
      let player_exists =
        list.any(updated_players, fn(p) { p.user_id == user_id })

      case player_exists {
        True -> Ok(Lobby(..lobby, players: updated_players))
        False -> Error("Player not found")
      }
    }
  }
}

/// Check if all players are ready
pub fn all_players_ready(lobby: Lobby) -> Bool {
  case lobby.players {
    [] -> False
    _ -> list.all(lobby.players, fn(p) { p.is_ready })
  }
}

/// Check if a player is the creator
pub fn is_creator(lobby: Lobby, user_id: String) -> Bool {
  lobby.players
  |> list.any(fn(p) { p.user_id == user_id && p.is_creator })
}

/// Check if the game can be started
pub fn can_start_game(lobby: Lobby, user_id: String) -> Bool {
  is_creator(lobby, user_id) && all_players_ready(lobby)
}

/// Get a player by user_id
pub fn get_player(lobby: Lobby, user_id: String) -> Option(Player) {
  lobby.players
  |> list.find(fn(p) { p.user_id == user_id })
  |> option.from_result
}
