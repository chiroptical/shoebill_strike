import game_server/handlers/connection
import game_server/handlers/end_game
import game_server/handlers/game_play
import game_server/handlers/lobby as lobby_handlers
import game_server/handlers/ticks
import game_server/handlers/vote_initiation
import game_server/state.{
  type ServerMsg, type ServerState, AbandonVoteTickMsg, ClientConnected,
  ClientDisconnected, ClientMsg, ConnectionInfo, CountdownTickMsg, ServerState,
  SetSelfSubject, VoteTickMsg,
}
import gleam/dict
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/io
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/result
import protocol/types as protocol

/// Start the server actor
pub fn start() -> Result(Subject(ServerMsg), actor.StartError) {
  let initial_state =
    ServerState(
      lobbies: dict.new(),
      games: dict.new(),
      connections: dict.new(),
      countdown_timers: dict.new(),
      vote_states: dict.new(),
      vote_timers: dict.new(),
      self_subject: None,
    )

  actor.new(initial_state)
  |> actor.on_message(handle_message)
  |> actor.start
  |> result.map(fn(started) {
    // Store the subject in the state by sending a message
    let subject = started.data
    process.send(subject, SetSelfSubject(subject))
    subject
  })
}

/// Handle messages sent to the server actor
fn handle_message(
  state: ServerState,
  msg: ServerMsg,
) -> actor.Next(ServerState, ServerMsg) {
  case msg {
    ClientConnected(subject, user_id) -> {
      io.println(
        "[Server] Client connected: "
        <> user_id
        <> " (total: "
        <> int.to_string(dict.size(state.connections) + 1)
        <> ")",
      )
      // Check if this user_id already has a connection (reconnection)
      // Simply update the Subject, keeping all other connection info
      let conn_info = case dict.get(state.connections, user_id) {
        Ok(existing) -> ConnectionInfo(..existing, subject: subject)
        Error(_) ->
          ConnectionInfo(
            subject: subject,
            user_id: user_id,
            lobby_code: None,
            game_code: None,
          )
      }
      let new_connections = dict.insert(state.connections, user_id, conn_info)
      actor.continue(ServerState(..state, connections: new_connections))
    }

    ClientDisconnected(user_id) -> {
      io.println("[Server] Client disconnected: " <> user_id)
      io.println("[Server] Keeping player in lobby/game for reconnection")

      // Get connection info before deleting to know which lobby/game they're in
      let conn_info = dict.get(state.connections, user_id)

      // Mark player as disconnected in lobby and broadcast
      let state = case conn_info {
        Ok(ConnectionInfo(lobby_code: Some(code), ..)) ->
          connection.mark_player_disconnected_in_lobby(state, code, user_id)
        _ -> state
      }

      // Mark player as disconnected in game and broadcast
      let state = case conn_info {
        Ok(ConnectionInfo(game_code: Some(code), ..)) ->
          connection.mark_player_disconnected_in_game(state, code, user_id)
        _ -> state
      }

      // Remove the connection entry
      let new_connections = dict.delete(state.connections, user_id)
      actor.continue(ServerState(..state, connections: new_connections))
    }

    ClientMsg(user_id, client_msg) -> {
      let state = handle_client_message(state, user_id, client_msg)
      actor.continue(state)
    }

    CountdownTickMsg(game_code, seconds) ->
      ticks.handle_countdown_tick(state, game_code, seconds)

    VoteTickMsg(game_code, seconds) ->
      ticks.handle_vote_tick(state, game_code, seconds)

    AbandonVoteTickMsg(game_code, seconds) ->
      ticks.handle_abandon_vote_tick(state, game_code, seconds)

    SetSelfSubject(subject) -> {
      io.println("[Server] Self subject stored")
      actor.continue(ServerState(..state, self_subject: Some(subject)))
    }
  }
}

/// Handle a client message
fn handle_client_message(
  state: ServerState,
  user_id: String,
  msg: protocol.ClientMessage,
) -> ServerState {
  case msg {
    protocol.CreateGame(_msg_user_id, nickname) ->
      lobby_handlers.handle_create_game(state, user_id, nickname)

    protocol.JoinGame(code, _msg_user_id, nickname) ->
      lobby_handlers.handle_join_game(state, user_id, code, nickname)

    protocol.ToggleReady -> lobby_handlers.handle_toggle_ready(state, user_id)

    protocol.StartGame -> lobby_handlers.handle_start_game(state, user_id)

    protocol.ToggleReadyInGame ->
      game_play.handle_toggle_ready_in_game(state, user_id)

    protocol.PlayCard -> game_play.handle_play_card(state, user_id)

    protocol.InitiateStrikeVote ->
      vote_initiation.handle_initiate_strike_vote(state, user_id)

    protocol.CastStrikeVote(approve) ->
      vote_initiation.handle_cast_strike_vote(state, user_id, approve)

    protocol.InitiateAbandonVote ->
      vote_initiation.handle_initiate_abandon_vote(state, user_id)

    protocol.CastAbandonVote(approve) ->
      vote_initiation.handle_cast_abandon_vote(state, user_id, approve)

    protocol.LeaveGame -> end_game.handle_leave_game(state, user_id)

    protocol.RestartGame -> end_game.handle_restart_game(state, user_id)
  }
}
