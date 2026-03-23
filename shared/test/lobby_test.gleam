import gleam/list
import gleam/option.{Some}
import gleam/string
import gleeunit/should
import lobby

pub fn reconnection_preserves_creator_status_test() {
  let initial_lobby = lobby.create_lobby("ABC123", "user_1", "Alice")

  lobby.is_creator(initial_lobby, "user_1")
  |> should.be_true()

  // Reconnecting same user (user_1) - should preserve creator status
  let assert Ok(updated_lobby) =
    lobby.add_player(initial_lobby, "user_1", "Alice")

  lobby.is_creator(updated_lobby, "user_1")
  |> should.be_true()

  list.length(updated_lobby.players)
  |> should.equal(1)
}

pub fn reconnection_preserves_non_creator_status_test() {
  let lobby_with_alice = lobby.create_lobby("ABC123", "user_1", "Alice")

  let assert Ok(lobby_with_bob) =
    lobby.add_player(lobby_with_alice, "user_2", "Bob")

  lobby.is_creator(lobby_with_bob, "user_2")
  |> should.be_false()

  lobby.is_creator(lobby_with_bob, "user_1")
  |> should.be_true()

  // Reconnecting user_2 - should preserve non-creator status
  let assert Ok(updated_lobby) =
    lobby.add_player(lobby_with_bob, "user_2", "Bob")

  lobby.is_creator(updated_lobby, "user_2")
  |> should.be_false()

  lobby.is_creator(updated_lobby, "user_1")
  |> should.be_true()

  list.length(updated_lobby.players)
  |> should.equal(2)
}

pub fn create_lobby_sets_creator_correctly_test() {
  let new_lobby = lobby.create_lobby("XYZ789", "user_1", "Alice")

  new_lobby.code
  |> should.equal("XYZ789")

  list.length(new_lobby.players)
  |> should.equal(1)

  lobby.is_creator(new_lobby, "user_1")
  |> should.be_true()

  lobby.all_players_ready(new_lobby)
  |> should.be_false()

  let assert Some(player) = lobby.get_player(new_lobby, "user_1")
  player.nickname
  |> should.equal("Alice")
  player.is_creator
  |> should.be_true()
  player.is_ready
  |> should.be_false()
}

pub fn add_new_player_to_lobby_test() {
  let initial_lobby = lobby.create_lobby("ABC123", "user_1", "Alice")

  let assert Ok(updated_lobby) =
    lobby.add_player(initial_lobby, "user_2", "Bob")

  list.length(updated_lobby.players)
  |> should.equal(2)

  lobby.is_creator(updated_lobby, "user_2")
  |> should.be_false()

  lobby.is_creator(updated_lobby, "user_1")
  |> should.be_true()

  let assert Some(bob) = lobby.get_player(updated_lobby, "user_2")
  bob.nickname
  |> should.equal("Bob")
  bob.is_creator
  |> should.be_false()
  bob.is_ready
  |> should.be_false()

  lobby.all_players_ready(updated_lobby)
  |> should.be_false()
}

pub fn toggle_ready_changes_status_test() {
  let initial_lobby = lobby.create_lobby("ABC123", "user_1", "Alice")
  // Need at least 2 players to toggle ready
  let assert Ok(lobby_with_bob) =
    lobby.add_player(initial_lobby, "user_2", "Bob")

  let assert Some(alice) = lobby.get_player(lobby_with_bob, "user_1")
  alice.is_ready
  |> should.be_false()

  let assert Ok(lobby_after_ready) =
    lobby.toggle_ready(lobby_with_bob, "user_1")
  let assert Some(alice_ready) = lobby.get_player(lobby_after_ready, "user_1")
  alice_ready.is_ready
  |> should.be_true()

  let assert Ok(lobby_after_not_ready) =
    lobby.toggle_ready(lobby_after_ready, "user_1")
  let assert Some(alice_not_ready) =
    lobby.get_player(lobby_after_not_ready, "user_1")
  alice_not_ready.is_ready
  |> should.be_false()
}

pub fn toggle_ready_nonexistent_player_returns_error_test() {
  let initial_lobby = lobby.create_lobby("ABC123", "user_1", "Alice")
  // Need at least 2 players to toggle ready
  let assert Ok(lobby_with_bob) =
    lobby.add_player(initial_lobby, "user_2", "Bob")

  let result = lobby.toggle_ready(lobby_with_bob, "nonexistent_user")

  result
  |> should.be_error()

  let assert Error(msg) = result
  msg
  |> should.equal("Player not found")
}

pub fn remove_player_from_lobby_test() {
  let lobby_with_alice = lobby.create_lobby("ABC123", "user_1", "Alice")

  let assert Ok(lobby_with_both) =
    lobby.add_player(lobby_with_alice, "user_2", "Bob")

  list.length(lobby_with_both.players)
  |> should.equal(2)

  let lobby_after_remove = lobby.remove_player(lobby_with_both, "user_2")

  list.length(lobby_after_remove.players)
  |> should.equal(1)

  lobby.get_player(lobby_after_remove, "user_2")
  |> should.be_none()

  let assert Some(alice) = lobby.get_player(lobby_after_remove, "user_1")
  alice.nickname
  |> should.equal("Alice")
}

pub fn all_players_ready_with_multiple_players_test() {
  let lobby_with_alice = lobby.create_lobby("ABC123", "user_1", "Alice")

  let assert Ok(lobby_with_bob) =
    lobby.add_player(lobby_with_alice, "user_2", "Bob")
  let assert Ok(lobby_with_all) =
    lobby.add_player(lobby_with_bob, "user_3", "Charlie")

  lobby.all_players_ready(lobby_with_all)
  |> should.be_false()

  let assert Ok(lobby1) = lobby.toggle_ready(lobby_with_all, "user_1")
  lobby.all_players_ready(lobby1)
  |> should.be_false()

  let assert Ok(lobby2) = lobby.toggle_ready(lobby1, "user_2")
  lobby.all_players_ready(lobby2)
  |> should.be_false()

  let assert Ok(lobby3) = lobby.toggle_ready(lobby2, "user_3")
  lobby.all_players_ready(lobby3)
  |> should.be_true()

  let assert Ok(lobby4) = lobby.toggle_ready(lobby3, "user_3")
  lobby.all_players_ready(lobby4)
  |> should.be_false()
}

pub fn all_players_ready_with_empty_lobby_test() {
  let initial_lobby = lobby.create_lobby("ABC123", "user_1", "Alice")
  let empty_lobby = lobby.remove_player(initial_lobby, "user_1")

  lobby.all_players_ready(empty_lobby)
  |> should.be_false()
}

pub fn can_start_game_requires_creator_and_all_ready_test() {
  let lobby_with_alice = lobby.create_lobby("ABC123", "user_1", "Alice")

  let assert Ok(lobby_with_both) =
    lobby.add_player(lobby_with_alice, "user_2", "Bob")

  lobby.can_start_game(lobby_with_both, "user_1")
  |> should.be_false()

  let assert Ok(lobby1) = lobby.toggle_ready(lobby_with_both, "user_1")
  let assert Ok(lobby2) = lobby.toggle_ready(lobby1, "user_2")

  lobby.can_start_game(lobby2, "user_1")
  |> should.be_true()

  lobby.can_start_game(lobby2, "user_2")
  |> should.be_false()
}

pub fn can_start_game_fails_when_not_creator_test() {
  let initial_lobby = lobby.create_lobby("ABC123", "user_1", "Alice")
  // Need at least 2 players to toggle ready
  let assert Ok(lobby_with_bob) =
    lobby.add_player(initial_lobby, "user_2", "Bob")
  let assert Ok(lobby_ready1) = lobby.toggle_ready(lobby_with_bob, "user_1")
  let assert Ok(lobby_ready) = lobby.toggle_ready(lobby_ready1, "user_2")

  lobby.can_start_game(lobby_ready, "user_1")
  |> should.be_true()

  lobby.can_start_game(lobby_ready, "nonexistent")
  |> should.be_false()
}

pub fn can_start_game_fails_when_not_all_ready_test() {
  let lobby_with_alice = lobby.create_lobby("ABC123", "user_1", "Alice")

  let assert Ok(lobby_with_bob) =
    lobby.add_player(lobby_with_alice, "user_2", "Bob")
  let assert Ok(lobby_with_all) =
    lobby.add_player(lobby_with_bob, "user_3", "Charlie")

  lobby.can_start_game(lobby_with_all, "user_1")
  |> should.be_false()

  let assert Ok(lobby1) = lobby.toggle_ready(lobby_with_all, "user_1")
  lobby.can_start_game(lobby1, "user_1")
  |> should.be_false()

  let assert Ok(lobby2) = lobby.toggle_ready(lobby1, "user_2")
  lobby.can_start_game(lobby2, "user_1")
  |> should.be_false()

  let assert Ok(lobby3) = lobby.toggle_ready(lobby2, "user_3")
  lobby.can_start_game(lobby3, "user_1")
  |> should.be_true()
}

pub fn generate_code_format_test() {
  let mock_random = fn() { 5 }

  let code = lobby.generate_code(mock_random)

  string.length(code)
  |> should.equal(6)

  code
  |> should.equal("FFFFFF")
}

pub fn generate_code_uses_valid_charset_test() {
  let valid_chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

  let code1 = lobby.generate_code(fn() { 0 })
  let code2 = lobby.generate_code(fn() { 10 })
  let code3 = lobby.generate_code(fn() { 31 })

  let all_chars_valid = fn(code: String) -> Bool {
    code
    |> string.to_graphemes()
    |> list.all(fn(char) { string.contains(valid_chars, char) })
  }

  all_chars_valid(code1)
  |> should.be_true()

  all_chars_valid(code2)
  |> should.be_true()

  all_chars_valid(code3)
  |> should.be_true()
}

pub fn nickname_collision_rejected_test() {
  let lobby_with_alice = lobby.create_lobby("ABC123", "user_1", "Alice")

  // Try to join with same nickname but different user_id
  let result = lobby.add_player(lobby_with_alice, "user_2", "Alice")

  result
  |> should.be_error()

  let assert Error(msg) = result
  msg
  |> should.equal("Nickname already in use")
}

pub fn uuid_based_reconnection_test() {
  let initial_lobby = lobby.create_lobby("ABC123", "user_1", "Alice")

  // Same user_id reconnecting (with different nickname attempt - should be ignored)
  let assert Ok(updated_lobby) =
    lobby.add_player(initial_lobby, "user_1", "Bob")

  // Should preserve nickname from original player
  let assert Some(player) = lobby.get_player(updated_lobby, "user_1")
  player.nickname
  |> should.equal("Alice")

  // Should only have 1 player (reconnection, not new player)
  list.length(updated_lobby.players)
  |> should.equal(1)
}
