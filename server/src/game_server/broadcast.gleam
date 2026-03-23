import game_server/state.{type ServerState}
import gleam/dict
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{Some}
import protocol/types as protocol

/// Send a message to a specific user
pub fn send_message(
  state: ServerState,
  user_id: String,
  msg: protocol.ServerMessage,
) -> Nil {
  case dict.get(state.connections, user_id) {
    Ok(conn_info) -> {
      process.send(conn_info.subject, msg)
    }
    Error(_) -> Nil
  }
}

/// Broadcast a message to all users in a lobby
pub fn broadcast_message(
  state: ServerState,
  lobby_code: String,
  msg: protocol.ServerMessage,
) -> Nil {
  let recipients =
    state.connections
    |> dict.values
    |> list.filter(fn(conn_info) { conn_info.lobby_code == Some(lobby_code) })

  let recipient_count = list.length(recipients)
  io.println(
    "[Server] Broadcasting to "
    <> int.to_string(recipient_count)
    <> " users in lobby "
    <> lobby_code,
  )

  recipients
  |> list.each(fn(conn_info) {
    io.println("  -> Sending to user: " <> conn_info.user_id)
    send_message(state, conn_info.user_id, msg)
  })
}

/// Broadcast the current lobby state to all players in that lobby
pub fn broadcast_lobby_state(state: ServerState, lobby_code: String) -> Nil {
  case dict.get(state.lobbies, lobby_code) {
    Ok(lobby_state) -> {
      broadcast_message(state, lobby_code, protocol.LobbyState(lobby_state))
    }
    Error(_) -> Nil
  }
}

/// Broadcast a message to all users in a game
pub fn broadcast_game_message(
  state: ServerState,
  game_code: String,
  msg: protocol.ServerMessage,
) -> Nil {
  let recipients =
    state.connections
    |> dict.values
    |> list.filter(fn(conn_info) { conn_info.game_code == Some(game_code) })

  let recipient_count = list.length(recipients)
  io.println(
    "[Server] Broadcasting game message to "
    <> int.to_string(recipient_count)
    <> " users in game "
    <> game_code,
  )

  recipients
  |> list.each(fn(conn_info) {
    io.println("  -> Sending game message to user: " <> conn_info.user_id)
    send_message(state, conn_info.user_id, msg)
  })
}
