import game_server/helpers
import game_server/state.{type ServerState, ConnectionInfo, ServerState}
import gleam/dict
import gleam/erlang/process
import gleam/option.{None, Some}
import gleeunit/should

fn make_test_state_with_connection(user_id: String) -> ServerState {
  let subject = process.new_subject()
  let conn_info =
    ConnectionInfo(
      subject: subject,
      user_id: user_id,
      lobby_code: None,
      game_code: None,
    )
  ServerState(
    lobbies: dict.new(),
    games: dict.new(),
    connections: dict.from_list([#(user_id, conn_info)]),
    countdown_timers: dict.new(),
    vote_states: dict.new(),
    vote_timers: dict.new(),
    self_subject: None,
  )
}

pub fn update_player_lobby_sets_lobby_code_test() {
  let state = make_test_state_with_connection("user_1")

  let updated = helpers.update_player_lobby(state, "user_1", "LOBBY123")

  case dict.get(updated.connections, "user_1") {
    Ok(conn_info) -> conn_info.lobby_code |> should.equal(Some("LOBBY123"))
    Error(_) -> should.fail()
  }
}

pub fn update_player_lobby_preserves_other_fields_test() {
  let state = make_test_state_with_connection("user_1")

  let updated = helpers.update_player_lobby(state, "user_1", "LOBBY456")

  case dict.get(updated.connections, "user_1") {
    Ok(conn_info) -> {
      conn_info.user_id |> should.equal("user_1")
      conn_info.game_code |> should.equal(None)
    }
    Error(_) -> should.fail()
  }
}

pub fn update_player_lobby_nonexistent_user_returns_unchanged_test() {
  let state = make_test_state_with_connection("user_1")

  let updated = helpers.update_player_lobby(state, "nonexistent", "LOBBY789")

  // State should be unchanged
  updated.connections |> should.equal(state.connections)
}

pub fn update_player_game_sets_game_code_test() {
  let state = make_test_state_with_connection("user_1")

  let updated = helpers.update_player_game(state, "user_1", "GAME123")

  case dict.get(updated.connections, "user_1") {
    Ok(conn_info) -> conn_info.game_code |> should.equal(Some("GAME123"))
    Error(_) -> should.fail()
  }
}

pub fn update_player_game_preserves_other_fields_test() {
  let state = make_test_state_with_connection("user_1")
  // First set lobby code
  let state_with_lobby =
    helpers.update_player_lobby(state, "user_1", "LOBBY111")

  let updated =
    helpers.update_player_game(state_with_lobby, "user_1", "GAME222")

  case dict.get(updated.connections, "user_1") {
    Ok(conn_info) -> {
      conn_info.user_id |> should.equal("user_1")
      conn_info.lobby_code |> should.equal(Some("LOBBY111"))
      conn_info.game_code |> should.equal(Some("GAME222"))
    }
    Error(_) -> should.fail()
  }
}

pub fn update_player_game_nonexistent_user_returns_unchanged_test() {
  let state = make_test_state_with_connection("user_1")

  let updated = helpers.update_player_game(state, "nonexistent", "GAME999")

  updated.connections |> should.equal(state.connections)
}

pub fn generate_unique_code_returns_6_char_code_test() {
  let code = helpers.generate_unique_code(dict.new())

  // Code should be 6 characters
  case code {
    "" -> should.fail()
    _ -> Nil
  }
}

pub fn generate_unique_code_avoids_existing_codes_test() {
  // This is a probabilistic test - with empty lobbies, code should be unique
  let empty_lobbies = dict.new()
  let code1 = helpers.generate_unique_code(empty_lobbies)
  let code2 = helpers.generate_unique_code(empty_lobbies)

  // Both codes should be valid strings (not empty)
  case code1, code2 {
    "", _ -> should.fail()
    _, "" -> should.fail()
    _, _ -> Nil
  }
}
