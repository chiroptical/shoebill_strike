import game_server/state.{type ServerState, ConnectionInfo, ServerState}
import gleam/dict
import gleam/int
import gleam/option.{Some}
import lobby
import protocol/types.{type Lobby}

/// Update a user's lobby code in their connection info
pub fn update_player_lobby(
  state: ServerState,
  user_id: String,
  lobby_code: String,
) -> ServerState {
  case dict.get(state.connections, user_id) {
    Ok(conn_info) -> {
      let updated_info =
        ConnectionInfo(..conn_info, lobby_code: Some(lobby_code))
      let new_connections =
        dict.insert(state.connections, user_id, updated_info)
      ServerState(..state, connections: new_connections)
    }
    Error(_) -> state
  }
}

/// Update a user's game code in their connection info
pub fn update_player_game(
  state: ServerState,
  user_id: String,
  game_code: String,
) -> ServerState {
  case dict.get(state.connections, user_id) {
    Ok(conn_info) -> {
      let updated_info = ConnectionInfo(..conn_info, game_code: Some(game_code))
      let new_connections =
        dict.insert(state.connections, user_id, updated_info)
      ServerState(..state, connections: new_connections)
    }
    Error(_) -> state
  }
}

/// Generate a unique lobby code
pub fn generate_unique_code(lobbies: dict.Dict(String, Lobby)) -> String {
  let code = lobby.generate_code(fn() { int.random(1000) })
  case dict.has_key(lobbies, code) {
    True -> generate_unique_code(lobbies)
    False -> code
  }
}
