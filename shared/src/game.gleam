import gleam/list
import gleam/option.{None, Some}
import gleam/order
import gleam/result
import gleam/time/timestamp
import protocol/types.{
  type Card, type Game, type GamePlayer, type Lobby, type Phase, AbandonVote,
  ActivePlay, Dealing, EndGame, Game, GamePlayer, Lobby, Loss, MistakeInfo,
  Pause, Player, Strike, Win,
}

/// Represents the action to take when exiting Pause phase (all players ready)
pub type PauseExitAction {
  /// Single player has cards - apply auto-play and transition to Dealing
  AutoPlayThenDeal(user_id: String, nickname: String, cards: List(Card))
  /// Multiple players have cards - start countdown then transition to ActivePlay
  CountdownThenActivePlay
}

/// Generate a range of integers from start to end (inclusive)
fn range_list(start: Int, end: Int) -> List(Int) {
  case start > end {
    True -> []
    False -> [start, ..range_list(start + 1, end)]
  }
}

/// Create a deck of cards from 1 to 100
pub fn create_deck() -> List(Card) {
  range_list(1, 100)
}

/// Shuffle a deck using Fisher-Yates algorithm with injectable random function
/// random_fn takes an upper bound and returns a random int from 0 to upper_bound-1
pub fn shuffle_deck(deck: List(Card), random_fn: fn(Int) -> Int) -> List(Card) {
  let array = list.index_map(deck, fn(card, idx) { #(idx, card) })
  let size = list.length(deck)

  // Fisher-Yates shuffle
  range_list(0, size - 2)
  |> list.fold(array, fn(arr, i) {
    let j = i + random_fn(size - i)
    swap(arr, i, j)
  })
  |> list.map(fn(pair) { pair.1 })
}

/// Swap two elements in an indexed list
fn swap(arr: List(#(Int, Card)), i: Int, j: Int) -> List(#(Int, Card)) {
  let get = fn(idx: Int) -> Card {
    arr
    |> list.find(fn(pair) { pair.0 == idx })
    |> result.map(fn(pair) { pair.1 })
    |> result.unwrap(0)
  }

  let val_i = get(i)
  let val_j = get(j)

  arr
  |> list.map(fn(pair) {
    case pair.0 {
      idx if idx == i -> #(idx, val_j)
      idx if idx == j -> #(idx, val_i)
      _ -> pair
    }
  })
}

/// Get lives, strikes, and total rounds based on player count
/// Returns #(lives, strikes, total_rounds)
pub fn get_game_config(player_count: Int) -> #(Int, Int, Int) {
  case player_count {
    2 -> #(2, 1, 12)
    3 -> #(3, 1, 10)
    4 -> #(4, 1, 8)
    _ -> #(2, 1, 12)
  }
}

/// Deal cards to players for a given round
/// Returns a list of hands (one per player)
fn deal_cards(
  deck: List(Card),
  player_count: Int,
  round: Int,
) -> List(List(Card)) {
  let cards_per_player = round

  range_list(0, player_count - 1)
  |> list.map(fn(player_idx) {
    let start = player_idx * cards_per_player
    deck
    |> list.drop(start)
    |> list.take(cards_per_player)
    |> list.sort(by: fn(a, b) { int_compare(a, b) })
  })
}

/// Compare two integers for sorting
fn int_compare(a: Int, b: Int) -> order.Order {
  case a < b {
    True -> order.Lt
    False ->
      case a > b {
        True -> order.Gt
        False -> order.Eq
      }
  }
}

/// Create a game from a lobby
/// shuffle_fn is injectable for testing
pub fn create_game_from_lobby(
  lobby: Lobby,
  shuffle_fn: fn(List(Card)) -> List(Card),
) -> Game {
  let player_count = list.length(lobby.players)
  let #(lives, stars, total_rounds) = get_game_config(player_count)

  let deck = create_deck()
  let shuffled_deck = shuffle_fn(deck)
  let hands = deal_cards(shuffled_deck, player_count, 1)

  let game_players =
    list.index_map(lobby.players, fn(player, idx) {
      let hand =
        hands
        |> list.drop(idx)
        |> list.first
        |> result.unwrap([])

      GamePlayer(
        user_id: player.user_id,
        nickname: player.nickname,
        hand: hand,
        is_ready: False,
        is_connected: player.is_connected,
        last_card_played: None,
      )
    })

  let host_user_id =
    lobby.players
    |> list.find(fn(p) { p.is_creator })
    |> result.map(fn(p) { p.user_id })
    |> result.unwrap("")

  Game(
    code: lobby.code,
    host_user_id: host_user_id,
    games_played: lobby.games_played,
    players: game_players,
    current_round: 1,
    total_rounds: total_rounds,
    lives: lives,
    strikes: stars,
    phase: Dealing,
    played_cards: [],
    last_mistake: None,
    abandon_vote_previous_phase: None,
    game_start_timestamp: timestamp.system_time(),
    game_log: [],
  )
}

/// Toggle ready status for a player in a game
pub fn toggle_ready_in_game(game: Game, user_id: String) -> Result(Game, String) {
  let player_exists =
    game.players
    |> list.any(fn(p) { p.user_id == user_id })

  case player_exists {
    False -> Error("Player not found")
    True -> {
      let updated_players =
        game.players
        |> list.map(fn(player) {
          case player.user_id == user_id {
            True -> GamePlayer(..player, is_ready: !player.is_ready)
            False -> player
          }
        })

      Ok(Game(..game, players: updated_players))
    }
  }
}

/// Check if all players are ready in a game
pub fn all_players_ready_in_game(game: Game) -> Bool {
  case game.players {
    [] -> False
    _ -> list.all(game.players, fn(p) { p.is_ready })
  }
}

/// Transition the game to a new phase
/// When entering Pause phase, automatically readies players with empty hands
/// (they have nothing to contribute in ActivePlay) and resets others to not ready
pub fn transition_phase(game: Game, new_phase: Phase) -> Game {
  case new_phase {
    Pause -> {
      // Auto-ready players with empty hands, reset others to not ready
      let updated_players =
        list.map(game.players, fn(p) {
          case p.hand {
            [] -> GamePlayer(..p, is_ready: True)
            _ -> GamePlayer(..p, is_ready: False)
          }
        })
      Game(..game, phase: Pause, players: updated_players)
    }
    _ -> Game(..game, phase: new_phase)
  }
}

/// Get a game player by user_id
pub fn get_game_player(game: Game, user_id: String) -> Result(GamePlayer, Nil) {
  game.players
  |> list.find(fn(p) { p.user_id == user_id })
}

/// Phase to string for display
pub fn phase_to_string(phase: Phase) -> String {
  case phase {
    Dealing -> "Dealing"
    ActivePlay -> "Active Play"
    Pause -> "Pause"
    Strike -> "Strike"
    AbandonVote -> "Abandon Vote"
    EndGame(_) -> "End Game"
  }
}

/// Deal cards for a new round (used for round 2+)
/// Shuffles a fresh deck, deals current_round cards per player,
/// resets ready states, clears played_cards
pub fn deal_round(game: Game, shuffle_fn: fn(List(Card)) -> List(Card)) -> Game {
  let player_count = list.length(game.players)
  let deck = create_deck()
  let shuffled_deck = shuffle_fn(deck)
  let hands = deal_cards(shuffled_deck, player_count, game.current_round)

  let updated_players =
    list.index_map(game.players, fn(player, idx) {
      let hand =
        hands
        |> list.drop(idx)
        |> list.first
        |> result.unwrap([])

      GamePlayer(..player, hand: hand, is_ready: False, last_card_played: None)
    })

  Game(
    ..game,
    players: updated_players,
    played_cards: [],
    phase: Dealing,
    last_mistake: None,
  )
}

/// Play the lowest card from a player's hand
pub fn play_card(game: Game, user_id: String) -> Result(Game, String) {
  case game.phase {
    ActivePlay -> do_play_card(game, user_id)
    _ -> Error("Not in active play phase")
  }
}

fn do_play_card(game: Game, user_id: String) -> Result(Game, String) {
  case get_game_player(game, user_id) {
    Error(_) -> Error("Player not found")
    Ok(player) ->
      case player.hand {
        [] -> Error("Player has no cards")
        [lowest, ..rest] -> {
          // Remove the card from the player's hand and record as last played
          let game =
            update_player_hand(game, user_id, rest)
            |> add_played_card(lowest)
            |> set_last_card_played(user_id, lowest)

          // Check for mistakes: any other player's lowest card < played card?
          let mistake_cards = find_mistake_cards(game, user_id, lowest)
          case mistake_cards {
            [] -> {
              // No mistake — check if round is complete
              let game = Game(..game, last_mistake: None)
              case all_hands_empty(game) {
                True -> Ok(handle_round_complete(game))
                False -> Ok(game)
              }
            }
            _ -> {
              // Mistake! Build mistake info before discarding
              let playing_nickname = case get_game_player(game, user_id) {
                Ok(p) -> p.nickname
                Error(_) -> user_id
              }
              let mistake_info =
                MistakeInfo(
                  player_nickname: playing_nickname,
                  played_card: lowest,
                  mistake_cards: resolve_nicknames(game, mistake_cards),
                )
              // Discard all cards lower than played card from all players
              let game = discard_cards_below(game, lowest)
              let game =
                Game(
                  ..game,
                  lives: game.lives - 1,
                  last_mistake: Some(mistake_info),
                )
              case game.lives <= 0 {
                True ->
                  game
                  |> reset_ready_states
                  |> fn(g) { Game(..g, phase: EndGame(Loss)) }
                  |> Ok
                False ->
                  case all_hands_empty(game) {
                    True -> Ok(handle_round_complete(game))
                    False ->
                      game
                      |> transition_phase(Pause)
                      |> Ok
                  }
              }
            }
          }
        }
      }
  }
}

/// Resolve user_ids to nicknames in mistake card pairs
fn resolve_nicknames(
  game: Game,
  user_id_card_pairs: List(#(String, Card)),
) -> List(#(String, Card)) {
  list.map(user_id_card_pairs, fn(pair) {
    let nickname = case list.find(game.players, fn(p) { p.user_id == pair.0 }) {
      Ok(p) -> p.nickname
      Error(_) -> pair.0
    }
    #(nickname, pair.1)
  })
}

/// Reset all players' ready status to False
pub fn reset_ready_states(game: Game) -> Game {
  let updated_players =
    list.map(game.players, fn(p) { GamePlayer(..p, is_ready: False) })
  Game(..game, players: updated_players)
}

/// Find all cards from other players that are less than the played card
fn find_mistake_cards(
  game: Game,
  playing_user_id: String,
  played_card: Card,
) -> List(#(String, Card)) {
  game.players
  |> list.filter(fn(p) { p.user_id != playing_user_id })
  |> list.flat_map(fn(p) {
    p.hand
    |> list.filter(fn(c) { c < played_card })
    |> list.map(fn(c) { #(p.user_id, c) })
  })
}

/// Discard all cards strictly less than the given card from all players
fn discard_cards_below(game: Game, played_card: Card) -> Game {
  let updated_players =
    game.players
    |> list.map(fn(player) {
      let new_hand = list.filter(player.hand, fn(c) { c >= played_card })
      GamePlayer(..player, hand: new_hand)
    })
  Game(..game, players: updated_players)
}

/// Check if all players have empty hands
fn all_hands_empty(game: Game) -> Bool {
  list.all(game.players, fn(p) { p.hand == [] })
}

/// Check if auto-play is possible: exactly one player has cards, all others have 0
/// Returns Some((user_id, nickname, cards)) if auto-play should occur, None otherwise
pub fn get_auto_play_candidate(
  game: Game,
) -> option.Option(#(String, String, List(Card))) {
  let players_with_cards = list.filter(game.players, fn(p) { p.hand != [] })
  case players_with_cards {
    [player] -> Some(#(player.user_id, player.nickname, player.hand))
    _ -> None
  }
}

/// Determine the action to take when exiting Pause phase (all players ready)
/// Used by Phase Transition Rules #2 and #3 in architecture.md
pub fn get_pause_exit_action(game: Game) -> PauseExitAction {
  case get_auto_play_candidate(game) {
    Some(#(user_id, nickname, cards)) ->
      AutoPlayThenDeal(user_id, nickname, cards)
    None -> CountdownThenActivePlay
  }
}

/// Apply auto-play: move all cards from player's hand to played pile
/// Assumes caller has verified only one player has cards (via get_auto_play_candidate)
pub fn apply_auto_play(game: Game, user_id: String) -> Game {
  case get_game_player(game, user_id) {
    Error(_) -> game
    Ok(player) -> {
      // Move all cards to played pile (cards are already sorted ascending)
      let new_played = list.append(game.played_cards, player.hand)
      // The last card played is the highest card (last in sorted hand)
      let last_card = list.last(player.hand)
      let updated_game =
        game
        |> update_player_hand(user_id, [])
        |> fn(g) { Game(..g, played_cards: new_played) }
        |> fn(g) {
          case last_card {
            Ok(card) -> set_last_card_played(g, user_id, card)
            Error(_) -> g
          }
        }

      // Check for round completion
      case all_hands_empty(updated_game) {
        True -> handle_round_complete(updated_game)
        False -> updated_game
      }
    }
  }
}

/// Reward granted upon completing a level
type RoundReward {
  RoundReward(lives: Int, strikes: Int)
}

/// Get level completion reward
fn get_level_reward(completed_level: Int) -> RoundReward {
  case completed_level {
    2 -> RoundReward(lives: 0, strikes: 1)
    3 -> RoundReward(lives: 1, strikes: 0)
    5 -> RoundReward(lives: 0, strikes: 1)
    6 -> RoundReward(lives: 1, strikes: 0)
    8 -> RoundReward(lives: 0, strikes: 1)
    9 -> RoundReward(lives: 1, strikes: 0)
    _ -> RoundReward(lives: 0, strikes: 0)
  }
}

/// Handle round completion: apply rewards, advance to next round or end game
fn handle_round_complete(game: Game) -> Game {
  let reward = get_level_reward(game.current_round)
  let game =
    Game(
      ..game,
      lives: game.lives + reward.lives,
      strikes: game.strikes + reward.strikes,
    )

  case game.current_round >= game.total_rounds {
    True ->
      game
      |> reset_ready_states
      |> fn(g) { Game(..g, phase: EndGame(Win)) }
    False ->
      Game(
        ..game,
        current_round: game.current_round + 1,
        phase: Dealing,
        played_cards: [],
      )
  }
}

/// Update a specific player's hand
fn update_player_hand(game: Game, user_id: String, new_hand: List(Card)) -> Game {
  let updated_players =
    game.players
    |> list.map(fn(player) {
      case player.user_id == user_id {
        True -> GamePlayer(..player, hand: new_hand)
        False -> player
      }
    })
  Game(..game, players: updated_players)
}

/// Add a card to the played cards pile
fn add_played_card(game: Game, card: Card) -> Game {
  Game(..game, played_cards: list.append(game.played_cards, [card]))
}

/// Update a player's last_card_played field
fn set_last_card_played(game: Game, user_id: String, card: Card) -> Game {
  let updated_players =
    game.players
    |> list.map(fn(player) {
      case player.user_id == user_id {
        True -> GamePlayer(..player, last_card_played: Some(card))
        False -> player
      }
    })
  Game(..game, players: updated_players)
}

/// Get the cards that would be discarded by a strike
/// Returns a list of (nickname, lowest_card) for each player with cards
pub fn get_strike_discards(game: Game) -> List(#(String, Card)) {
  game.players
  |> list.filter_map(fn(player) {
    case player.hand {
      [lowest, ..] -> Ok(#(player.nickname, lowest))
      [] -> Error(Nil)
    }
  })
}

/// Apply a strike: consume one strike and discard each player's lowest card
/// Returns the updated game with phase transition handled
pub fn apply_strike(game: Game) -> Result(Game, String) {
  case game.strikes > 0 {
    False -> Error("No strikes available")
    True -> {
      // Collect discarded cards (each player's lowest)
      let discarded_cards =
        game.players
        |> list.filter_map(fn(player) {
          case player.hand {
            [lowest, ..] -> Ok(lowest)
            [] -> Error(Nil)
          }
        })

      // Update players (remove lowest card from each hand, record as last played)
      let updated_players =
        game.players
        |> list.map(fn(player) {
          case player.hand {
            [lowest, ..rest] ->
              GamePlayer(..player, hand: rest, last_card_played: Some(lowest))
            [] -> player
          }
        })

      // Find minimum remaining card across all players (101 if no cards remain)
      let min_remaining =
        updated_players
        |> list.flat_map(fn(p) { p.hand })
        |> list.fold(101, fn(acc, card) {
          case card < acc {
            True -> card
            False -> acc
          }
        })

      // Find highest valid discard (must be < min_remaining to avoid invalid pile)
      let valid_pile_top =
        discarded_cards
        |> list.filter(fn(card) { card < min_remaining })
        |> list.fold(0, fn(acc, card) {
          case card > acc {
            True -> card
            False -> acc
          }
        })

      let game =
        Game(
          ..game,
          players: updated_players,
          strikes: game.strikes - 1,
          played_cards: case valid_pile_top > 0 {
            True -> list.append(game.played_cards, [valid_pile_top])
            False -> game.played_cards
          },
        )
      case all_hands_empty(game) {
        True -> Ok(handle_round_complete(game))
        False -> Ok(Game(..game, phase: ActivePlay))
      }
    }
  }
}

/// Convert a game back to a lobby for restart
pub fn game_to_lobby(game: Game) -> Lobby {
  let lobby_players =
    list.map(game.players, fn(p) {
      Player(
        user_id: p.user_id,
        nickname: p.nickname,
        is_ready: False,
        is_creator: p.user_id == game.host_user_id,
        is_connected: p.is_connected,
      )
    })
  Lobby(
    code: game.code,
    players: lobby_players,
    games_played: game.games_played + 1,
  )
}
