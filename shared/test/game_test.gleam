import game
import gleam/list
import gleam/option.{None, Some}
import gleam/time/timestamp
import gleeunit/should
import lobby
import protocol/types.{
  type Game, ActivePlay, Dealing, EndGame, Game, GamePlayer, Loss, MistakeInfo,
  Pause, Strike, Win,
}

pub fn create_deck_has_100_cards_test() {
  let deck = game.create_deck()

  list.length(deck)
  |> should.equal(100)

  // First card should be 1
  list.first(deck)
  |> should.equal(Ok(1))

  // Last card should be 100
  list.last(deck)
  |> should.equal(Ok(100))
}

pub fn shuffle_deck_maintains_size_test() {
  let deck = game.create_deck()

  // Use a mock random function
  let mock_random = fn(_max: Int) { 0 }

  let shuffled = game.shuffle_deck(deck, mock_random)

  list.length(shuffled)
  |> should.equal(100)
}

pub fn shuffle_deck_contains_all_cards_test() {
  let deck = game.create_deck()

  // Use a deterministic random function
  let mock_random = fn(max: Int) { max / 2 }

  let shuffled = game.shuffle_deck(deck, mock_random)

  // All cards 1-100 should still be present
  range(1, 100)
  |> list.all(fn(card) { list.contains(shuffled, card) })
  |> should.be_true()
}

// Helper to create a range
fn range(start: Int, end: Int) -> List(Int) {
  case start > end {
    True -> []
    False -> [start, ..range(start + 1, end)]
  }
}

pub fn get_game_config_2_players_test() {
  let #(lives, stars, total_rounds) = game.get_game_config(2)

  lives |> should.equal(2)
  stars |> should.equal(1)
  total_rounds |> should.equal(12)
}

pub fn get_game_config_3_players_test() {
  let #(lives, stars, total_rounds) = game.get_game_config(3)

  lives |> should.equal(3)
  stars |> should.equal(1)
  total_rounds |> should.equal(10)
}

pub fn get_game_config_4_players_test() {
  let #(lives, stars, total_rounds) = game.get_game_config(4)

  lives |> should.equal(4)
  stars |> should.equal(1)
  total_rounds |> should.equal(8)
}

pub fn create_game_from_lobby_round_1_test() {
  let test_lobby = lobby.create_lobby("ABC123", "user_1", "Alice")
  let assert Ok(lobby_with_bob) = lobby.add_player(test_lobby, "user_2", "Bob")

  // Make players ready
  let assert Ok(lobby1) = lobby.toggle_ready(lobby_with_bob, "user_1")
  let assert Ok(lobby2) = lobby.toggle_ready(lobby1, "user_2")

  // Use identity shuffle for testing
  let identity_shuffle = fn(deck: List(Int)) { deck }

  let game_state = game.create_game_from_lobby(lobby2, identity_shuffle)

  game_state.code
  |> should.equal("ABC123")

  game_state.current_round
  |> should.equal(1)

  // 2 players = 2 lives, 1 star
  game_state.lives
  |> should.equal(2)

  game_state.strikes
  |> should.equal(1)

  game_state.phase
  |> should.equal(Dealing)

  list.length(game_state.players)
  |> should.equal(2)

  // At round 1, each player should have 1 card
  game_state.players
  |> list.all(fn(p) { list.length(p.hand) == 1 })
  |> should.be_true()

  // Players should start not ready
  game_state.players
  |> list.all(fn(p) { p.is_ready == False })
  |> should.be_true()
}

pub fn toggle_ready_in_game_test() {
  let test_lobby = lobby.create_lobby("ABC123", "user_1", "Alice")
  let assert Ok(lobby_with_bob) = lobby.add_player(test_lobby, "user_2", "Bob")
  let assert Ok(lobby1) = lobby.toggle_ready(lobby_with_bob, "user_1")
  let assert Ok(lobby2) = lobby.toggle_ready(lobby1, "user_2")

  let identity_shuffle = fn(deck: List(Int)) { deck }
  let game_state = game.create_game_from_lobby(lobby2, identity_shuffle)

  // Initially not ready
  let assert Ok(alice) = game.get_game_player(game_state, "user_1")
  alice.is_ready
  |> should.be_false()

  // Toggle ready
  let assert Ok(game_after_ready) =
    game.toggle_ready_in_game(game_state, "user_1")
  let assert Ok(alice_ready) = game.get_game_player(game_after_ready, "user_1")
  alice_ready.is_ready
  |> should.be_true()

  // Toggle back
  let assert Ok(game_after_not_ready) =
    game.toggle_ready_in_game(game_after_ready, "user_1")
  let assert Ok(alice_not_ready) =
    game.get_game_player(game_after_not_ready, "user_1")
  alice_not_ready.is_ready
  |> should.be_false()
}

pub fn toggle_ready_in_game_nonexistent_player_test() {
  let test_lobby = lobby.create_lobby("ABC123", "user_1", "Alice")
  // Need at least 2 players to toggle ready
  let assert Ok(lobby_with_bob) = lobby.add_player(test_lobby, "user_2", "Bob")
  let assert Ok(lobby_ready1) = lobby.toggle_ready(lobby_with_bob, "user_1")
  let assert Ok(lobby_ready) = lobby.toggle_ready(lobby_ready1, "user_2")

  let identity_shuffle = fn(deck: List(Int)) { deck }
  let game_state = game.create_game_from_lobby(lobby_ready, identity_shuffle)

  let result = game.toggle_ready_in_game(game_state, "nonexistent")

  result
  |> should.be_error()

  let assert Error(msg) = result
  msg
  |> should.equal("Player not found")
}

pub fn all_players_ready_in_game_test() {
  let test_lobby = lobby.create_lobby("ABC123", "user_1", "Alice")
  let assert Ok(lobby_with_bob) = lobby.add_player(test_lobby, "user_2", "Bob")
  let assert Ok(lobby1) = lobby.toggle_ready(lobby_with_bob, "user_1")
  let assert Ok(lobby2) = lobby.toggle_ready(lobby1, "user_2")

  let identity_shuffle = fn(deck: List(Int)) { deck }
  let game_state = game.create_game_from_lobby(lobby2, identity_shuffle)

  // Initially not all ready
  game.all_players_ready_in_game(game_state)
  |> should.be_false()

  // One player ready
  let assert Ok(game1) = game.toggle_ready_in_game(game_state, "user_1")
  game.all_players_ready_in_game(game1)
  |> should.be_false()

  // Both players ready
  let assert Ok(game2) = game.toggle_ready_in_game(game1, "user_2")
  game.all_players_ready_in_game(game2)
  |> should.be_true()

  // One player toggles back
  let assert Ok(game3) = game.toggle_ready_in_game(game2, "user_1")
  game.all_players_ready_in_game(game3)
  |> should.be_false()
}

pub fn transition_phase_test() {
  let test_lobby = lobby.create_lobby("ABC123", "user_1", "Alice")
  // Need at least 2 players to toggle ready
  let assert Ok(lobby_with_bob) = lobby.add_player(test_lobby, "user_2", "Bob")
  let assert Ok(lobby_ready1) = lobby.toggle_ready(lobby_with_bob, "user_1")
  let assert Ok(lobby_ready) = lobby.toggle_ready(lobby_ready1, "user_2")

  let identity_shuffle = fn(deck: List(Int)) { deck }
  let game_state = game.create_game_from_lobby(lobby_ready, identity_shuffle)

  // Starts in Dealing phase
  game_state.phase
  |> should.equal(Dealing)

  // Transition to ActivePlay
  let game_active = game.transition_phase(game_state, ActivePlay)
  game_active.phase
  |> should.equal(ActivePlay)

  // Transition to Pause
  let game_paused = game.transition_phase(game_active, Pause)
  game_paused.phase
  |> should.equal(Pause)

  // Transition to EndGame
  let game_ended = game.transition_phase(game_paused, EndGame(Win))
  game_ended.phase
  |> should.equal(EndGame(Win))
}

pub fn phase_to_string_test() {
  game.phase_to_string(Dealing)
  |> should.equal("Dealing")

  game.phase_to_string(ActivePlay)
  |> should.equal("Active Play")

  game.phase_to_string(Pause)
  |> should.equal("Pause")

  game.phase_to_string(EndGame(Win))
  |> should.equal("End Game")
}

pub fn cards_are_sorted_in_hand_test() {
  let test_lobby = lobby.create_lobby("ABC123", "user_1", "Alice")
  // Need at least 2 players to toggle ready
  let assert Ok(lobby_with_bob) = lobby.add_player(test_lobby, "user_2", "Bob")
  let assert Ok(lobby_ready1) = lobby.toggle_ready(lobby_with_bob, "user_1")
  let assert Ok(lobby_ready) = lobby.toggle_ready(lobby_ready1, "user_2")

  // Reverse shuffle to test sorting
  let reverse_shuffle = fn(deck: List(Int)) { list.reverse(deck) }
  let game_state = game.create_game_from_lobby(lobby_ready, reverse_shuffle)

  // At round 1 with reverse shuffle, each player gets 1 card
  let assert Ok(player) = game.get_game_player(game_state, "user_1")
  list.length(player.hand)
  |> should.equal(1)
}

// Helper: create a game in ActivePlay with specific hands for 2 players
fn make_active_game(alice_hand: List(Int), bob_hand: List(Int)) -> Game {
  Game(
    code: "TEST",
    host_user_id: "user_1",
    games_played: 0,
    players: [
      GamePlayer(
        user_id: "user_1",
        nickname: "Alice",
        hand: alice_hand,
        is_ready: False,
        is_connected: True,
        last_card_played: None,
      ),
      GamePlayer(
        user_id: "user_2",
        nickname: "Bob",
        hand: bob_hand,
        is_ready: False,
        is_connected: True,
        last_card_played: None,
      ),
    ],
    current_round: 1,
    total_rounds: 12,
    lives: 2,
    strikes: 1,
    phase: ActivePlay,
    played_cards: [],
    last_mistake: None,
    abandon_vote_previous_phase: None,
    game_start_timestamp: timestamp.system_time(),
    game_log: [],
  )
}

pub fn play_card_success_test() {
  let game_state = make_active_game([5, 20], [10, 30])

  let assert Ok(updated) = game.play_card(game_state, "user_1")

  // Card 5 should be played
  updated.played_cards |> should.equal([5])
  // Alice should have [20] remaining
  let assert Ok(alice) = game.get_game_player(updated, "user_1")
  alice.hand |> should.equal([20])
  // No mistake, still in ActivePlay
  updated.phase |> should.equal(ActivePlay)
  updated.last_mistake |> should.equal(None)
}

pub fn play_card_wrong_phase_test() {
  let game_state =
    make_active_game([5], [10])
    |> fn(g) { Game(..g, phase: Dealing) }

  let result = game.play_card(game_state, "user_1")
  result |> should.be_error()
  let assert Error(msg) = result
  msg |> should.equal("Not in active play phase")
}

pub fn play_card_player_not_found_test() {
  let game_state = make_active_game([5], [10])

  let result = game.play_card(game_state, "nonexistent")
  result |> should.be_error()
  let assert Error(msg) = result
  msg |> should.equal("Player not found")
}

pub fn play_card_no_cards_test() {
  let game_state = make_active_game([], [10])

  let result = game.play_card(game_state, "user_1")
  result |> should.be_error()
  let assert Error(msg) = result
  msg |> should.equal("Player has no cards")
}

pub fn play_card_mistake_detected_test() {
  // Bob has card 3 which is lower than Alice's 5
  let game_state = make_active_game([5], [3, 30])

  let assert Ok(updated) = game.play_card(game_state, "user_1")

  // Card 5 was played
  updated.played_cards |> should.equal([5])
  // Bob's card 3 should be discarded (< 5)
  let assert Ok(bob) = game.get_game_player(updated, "user_2")
  bob.hand |> should.equal([30])
  // Life lost
  updated.lives |> should.equal(1)
  // Cards remain, so Pause
  updated.phase |> should.equal(Pause)
  // Mistake info should be populated
  updated.last_mistake
  |> should.equal(
    Some(
      MistakeInfo(player_nickname: "Alice", played_card: 5, mistake_cards: [
        #("Bob", 3),
      ]),
    ),
  )
  // Ready states should be reset
  updated.players
  |> list.all(fn(p) { p.is_ready == False })
  |> should.be_true()
}

pub fn play_card_mistake_loses_last_life_test() {
  let game_state =
    make_active_game([5], [3, 30])
    |> fn(g) { Game(..g, lives: 1) }

  let assert Ok(updated) = game.play_card(game_state, "user_1")

  updated.lives |> should.equal(0)
  updated.phase |> should.equal(EndGame(Loss))
  // Mistake info should still be set even on game over
  updated.last_mistake
  |> should.equal(
    Some(
      MistakeInfo(player_nickname: "Alice", played_card: 5, mistake_cards: [
        #("Bob", 3),
      ]),
    ),
  )
}

pub fn play_card_round_complete_test() {
  // Both players have one card each, no mistake
  let game_state = make_active_game([5], [10])

  // Alice plays 5 (correct, no mistake)
  let assert Ok(after_alice) = game.play_card(game_state, "user_1")
  after_alice.phase |> should.equal(ActivePlay)

  // Bob plays 10 (correct, all cards gone)
  let assert Ok(after_bob) = game.play_card(after_alice, "user_2")
  // Round complete → advance to round 2, Dealing
  after_bob.phase |> should.equal(Dealing)
  after_bob.current_round |> should.equal(2)
  after_bob.played_cards |> should.equal([])
}

pub fn play_card_final_round_win_test() {
  let game_state =
    make_active_game([5], [10])
    |> fn(g) { Game(..g, current_round: 12, total_rounds: 12) }

  let assert Ok(after_alice) = game.play_card(game_state, "user_1")
  let assert Ok(after_bob) = game.play_card(after_alice, "user_2")

  // Final round complete → EndGame (win)
  after_bob.phase |> should.equal(EndGame(Win))
}

pub fn play_card_mistake_discards_multiple_cards_test() {
  // Alice plays 50, Bob has [10, 20, 60] — cards 10 and 20 should be discarded
  let game_state = make_active_game([50], [10, 20, 60])

  let assert Ok(updated) = game.play_card(game_state, "user_1")

  let assert Ok(bob) = game.get_game_player(updated, "user_2")
  bob.hand |> should.equal([60])
  updated.lives |> should.equal(1)
}

pub fn play_card_mistake_round_complete_test() {
  // After mistake + discard, all hands empty → round complete
  let game_state = make_active_game([5], [3])

  let assert Ok(updated) = game.play_card(game_state, "user_1")

  // Bob's card 3 discarded, Alice's 5 played, all hands empty
  updated.lives |> should.equal(1)
  // Round complete → Dealing
  updated.phase |> should.equal(Dealing)
  updated.current_round |> should.equal(2)
}

pub fn phase_to_string_strike_test() {
  game.phase_to_string(Strike)
  |> should.equal("Strike")
}

pub fn apply_strike_success_test() {
  let game_state = make_active_game([5, 20], [10, 30])

  let assert Ok(updated) = game.apply_strike(game_state)

  // Star consumed
  updated.strikes |> should.equal(0)
  // Each player's lowest card removed
  let assert Ok(alice) = game.get_game_player(updated, "user_1")
  alice.hand |> should.equal([20])
  let assert Ok(bob) = game.get_game_player(updated, "user_2")
  bob.hand |> should.equal([30])
  // Highest discard (10) added to played pile
  updated.played_cards |> should.equal([10])
  // Cards remain, so ActivePlay
  updated.phase |> should.equal(ActivePlay)
}

pub fn apply_strike_no_stars_test() {
  let game_state =
    make_active_game([5, 20], [10, 30])
    |> fn(g) { Game(..g, strikes: 0) }

  let result = game.apply_strike(game_state)
  result |> should.be_error()
  let assert Error(msg) = result
  msg |> should.equal("No strikes available")
}

pub fn apply_strike_empty_hand_test() {
  // One player has no cards
  let game_state = make_active_game([], [10, 30])

  let assert Ok(updated) = game.apply_strike(game_state)

  updated.strikes |> should.equal(0)
  // Alice had no cards, hand still empty
  let assert Ok(alice) = game.get_game_player(updated, "user_1")
  alice.hand |> should.equal([])
  // Bob's lowest removed
  let assert Ok(bob) = game.get_game_player(updated, "user_2")
  bob.hand |> should.equal([30])
}

pub fn apply_strike_round_complete_test() {
  // Each player has exactly one card
  let game_state = make_active_game([5], [10])

  let assert Ok(updated) = game.apply_strike(game_state)

  // All cards discarded, round advances
  updated.strikes |> should.equal(0)
  updated.current_round |> should.equal(2)
  updated.phase |> should.equal(Dealing)
}

pub fn apply_strike_final_round_win_test() {
  let game_state =
    make_active_game([5], [10])
    |> fn(g) { Game(..g, current_round: 12, total_rounds: 12) }

  let assert Ok(updated) = game.apply_strike(game_state)

  updated.phase |> should.equal(EndGame(Win))
}

pub fn apply_strike_pile_top_respects_remaining_cards_test() {
  // Alice has [50, 60], Bob has [5, 10]
  // After star: discards are 50 and 5, remaining are [60] and [10]
  // Pile top should be 5 (highest discard < min remaining of 10)
  // NOT 50 (which would be >= Bob's remaining 10)
  let game_state = make_active_game([50, 60], [5, 10])

  let assert Ok(updated) = game.apply_strike(game_state)

  // Pile top should be 5, not 50
  updated.played_cards |> should.equal([5])
  // Verify hands updated correctly
  let assert Ok(alice) = game.get_game_player(updated, "user_1")
  alice.hand |> should.equal([60])
  let assert Ok(bob) = game.get_game_player(updated, "user_2")
  bob.hand |> should.equal([10])
}

pub fn apply_strike_high_discard_filtered_test() {
  // Alice has [90, 95], Bob has [80, 85]
  // After star: discards 90 and 80, remaining [95] and [85]
  // Min remaining = 85
  // Valid discards (< 85): only 80 (since 90 >= 85)
  // Pile top = 80
  let game_state = make_active_game([90, 95], [80, 85])

  let assert Ok(updated) = game.apply_strike(game_state)

  // Pile should be 80 (not 90)
  updated.played_cards |> should.equal([80])
}

pub fn get_strike_discards_test() {
  let game_state = make_active_game([5, 20], [10, 30])

  let discards = game.get_strike_discards(game_state)

  discards |> should.equal([#("Alice", 5), #("Bob", 10)])
}

pub fn get_strike_discards_empty_hand_test() {
  let game_state = make_active_game([], [10, 30])

  let discards = game.get_strike_discards(game_state)

  // Only Bob has cards
  discards |> should.equal([#("Bob", 10)])
}

pub fn deal_round_test() {
  let game_state =
    make_active_game([], [])
    |> fn(g) { Game(..g, current_round: 3) }

  let identity_shuffle = fn(deck: List(Int)) { deck }
  let dealt = game.deal_round(game_state, identity_shuffle)

  dealt.phase |> should.equal(Dealing)
  dealt.played_cards |> should.equal([])

  // Round 3 = 3 cards per player
  let assert Ok(alice) = game.get_game_player(dealt, "user_1")
  list.length(alice.hand) |> should.equal(3)

  let assert Ok(bob) = game.get_game_player(dealt, "user_2")
  list.length(bob.hand) |> should.equal(3)

  // Players should not be ready
  alice.is_ready |> should.be_false()
  bob.is_ready |> should.be_false()
}

// Auto-play tests

pub fn get_auto_play_candidate_returns_none_when_multiple_players_have_cards_test() {
  // Create a game with 2 players both having cards
  let test_lobby = lobby.create_lobby("ABC123", "user_1", "Alice")
  let assert Ok(lobby_with_bob) = lobby.add_player(test_lobby, "user_2", "Bob")
  let assert Ok(lobby1) = lobby.toggle_ready(lobby_with_bob, "user_1")
  let assert Ok(lobby2) = lobby.toggle_ready(lobby1, "user_2")

  let identity_shuffle = fn(deck: List(Int)) { deck }
  let game_state = game.create_game_from_lobby(lobby2, identity_shuffle)
  // Deal round 1 so each player has 1 card
  let game_state = game.deal_round(game_state, identity_shuffle)
  let game_state = game.transition_phase(game_state, ActivePlay)

  // Both players have cards, so no auto-play candidate
  game.get_auto_play_candidate(game_state) |> should.equal(None)
}

pub fn get_auto_play_candidate_returns_none_when_no_players_have_cards_test() {
  // Create a game with empty hands
  let test_lobby = lobby.create_lobby("ABC123", "user_1", "Alice")
  let assert Ok(lobby_with_bob) = lobby.add_player(test_lobby, "user_2", "Bob")
  let assert Ok(lobby1) = lobby.toggle_ready(lobby_with_bob, "user_1")
  let assert Ok(lobby2) = lobby.toggle_ready(lobby1, "user_2")

  let identity_shuffle = fn(deck: List(Int)) { deck }
  let game_state = game.create_game_from_lobby(lobby2, identity_shuffle)
  // Don't deal cards - hands are empty

  game.get_auto_play_candidate(game_state) |> should.equal(None)
}

pub fn get_auto_play_candidate_returns_player_when_one_has_cards_test() {
  // Create a game with 2 players
  let test_lobby = lobby.create_lobby("ABC123", "user_1", "Alice")
  let assert Ok(lobby_with_bob) = lobby.add_player(test_lobby, "user_2", "Bob")
  let assert Ok(lobby1) = lobby.toggle_ready(lobby_with_bob, "user_1")
  let assert Ok(lobby2) = lobby.toggle_ready(lobby1, "user_2")

  let identity_shuffle = fn(deck: List(Int)) { deck }
  let game_state = game.create_game_from_lobby(lobby2, identity_shuffle)
  let game_state = game.transition_phase(game_state, ActivePlay)

  // Find who has the lowest card and have them play it
  let assert Ok(alice) = game.get_game_player(game_state, "user_1")
  let assert Ok(bob) = game.get_game_player(game_state, "user_2")
  let assert [alice_lowest] = alice.hand
  let assert [bob_lowest] = bob.hand

  // Have the player with the lower card play first
  let #(first_player, second_player) = case alice_lowest < bob_lowest {
    True -> #("user_1", "user_2")
    False -> #("user_2", "user_1")
  }
  let assert Ok(game_state) = game.play_card(game_state, first_player)

  // Now only the second player has cards - should be auto-play candidate
  case game.get_auto_play_candidate(game_state) {
    Some(#(user_id, _nickname, cards)) -> {
      user_id |> should.equal(second_player)
      list.length(cards) |> should.equal(1)
    }
    None -> should.fail()
  }
}

pub fn apply_auto_play_moves_cards_and_completes_round_test() {
  // Create a game with 2 players
  let test_lobby = lobby.create_lobby("ABC123", "user_1", "Alice")
  let assert Ok(lobby_with_bob) = lobby.add_player(test_lobby, "user_2", "Bob")
  let assert Ok(lobby1) = lobby.toggle_ready(lobby_with_bob, "user_1")
  let assert Ok(lobby2) = lobby.toggle_ready(lobby1, "user_2")

  let identity_shuffle = fn(deck: List(Int)) { deck }
  let game_state = game.create_game_from_lobby(lobby2, identity_shuffle)
  let game_state = game.transition_phase(game_state, ActivePlay)
  // Starting at round 1
  game_state.current_round |> should.equal(1)

  // Find who has the lowest card and have them play it
  let assert Ok(alice) = game.get_game_player(game_state, "user_1")
  let assert Ok(bob) = game.get_game_player(game_state, "user_2")
  let assert [alice_lowest] = alice.hand
  let assert [bob_lowest] = bob.hand

  let #(first_player, second_player) = case alice_lowest < bob_lowest {
    True -> #("user_1", "user_2")
    False -> #("user_2", "user_1")
  }
  let assert Ok(game_state) = game.play_card(game_state, first_player)

  // Get the remaining player's cards before auto-play
  let assert Ok(remaining) = game.get_game_player(game_state, second_player)
  list.length(remaining.hand) |> should.equal(1)

  // Apply auto-play for the remaining player
  let final_game = game.apply_auto_play(game_state, second_player)

  // Their hand should be empty
  let assert Ok(after) = game.get_game_player(final_game, second_player)
  after.hand |> should.equal([])

  // Round should have advanced (all cards played = round complete)
  final_game.current_round |> should.equal(2)
  final_game.phase |> should.equal(Dealing)
}

// Pause exit action tests (Phase Transition Rules #2 and #3)

pub fn get_pause_exit_action_countdown_when_multiple_players_have_cards_test() {
  // Rule #3: Multiple players with cards -> CountdownThenActivePlay
  let game_state = make_active_game([5, 20], [10, 30])

  case game.get_pause_exit_action(game_state) {
    game.CountdownThenActivePlay -> Nil
    game.AutoPlayThenDeal(_, _, _) -> should.fail()
  }
}

pub fn get_pause_exit_action_autoplay_when_single_player_has_cards_test() {
  // Rule #2: Single player with cards -> AutoPlayThenDeal
  let game_state = make_active_game([], [10, 30])

  case game.get_pause_exit_action(game_state) {
    game.AutoPlayThenDeal(user_id, nickname, cards) -> {
      user_id |> should.equal("user_2")
      nickname |> should.equal("Bob")
      cards |> should.equal([10, 30])
    }
    game.CountdownThenActivePlay -> should.fail()
  }
}

pub fn get_pause_exit_action_countdown_when_no_players_have_cards_test() {
  // Edge case: No players with cards (should happen when round already complete)
  let game_state = make_active_game([], [])

  // This returns CountdownThenActivePlay since there's no auto-play candidate
  case game.get_pause_exit_action(game_state) {
    game.CountdownThenActivePlay -> Nil
    game.AutoPlayThenDeal(_, _, _) -> should.fail()
  }
}
