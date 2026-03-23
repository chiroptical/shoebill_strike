import gleam/int
import gleam/list
import gleam/option.{None, Some}
import mock_routes/builders/common.{
  MockGameParams, build_mock_game, get_mock_user_id, make_mock_timestamp_at,
}
import mock_routes/builders/game_log.{build_end_game_log, build_mock_game_log}
import mock_routes/types.{
  type MockAbandonParams, type MockActiveParams, type MockDealingParams,
  type MockEndParams, type MockPauseParams, type MockStrikeParams,
}
import protocol/types.{
  type Game, AbandonVote, ActivePlay, CardPlayed, Dealing, EndGame, Game,
  GameEvent, LifeLost, MistakeInfo, Pause, RoundStarted, Strike,
} as _protocol

// DEALING PHASE

pub fn build_mock_game_dealing(params: MockDealingParams) -> Game {
  // Generate sample game log entries based on round
  let game_log = build_mock_game_log(params.round, params.lives)

  build_mock_game(
    Dealing,
    MockGameParams(
      round: params.round,
      lives: params.lives,
      stars: params.stars,
      my_cards: params.cards,
      player_count: params.players,
      played_cards: [],
      last_mistake: None,
      game_log: game_log,
    ),
  )
}

// ACTIVE PLAY PHASE

pub fn build_mock_game_active(params: MockActiveParams) -> Game {
  let played_cards = case params.pile {
    Some(card) -> [card]
    None -> []
  }

  // Build full game log with history from previous rounds
  let base_log = build_mock_game_log(params.round, params.lives)
  let game_log = case params.pile {
    Some(card) ->
      list.append(base_log, [
        GameEvent(
          make_mock_timestamp_at({ params.round - 1 } * 15_000 + 2500),
          CardPlayed("Bob", card, False),
        ),
      ])
    None -> base_log
  }

  build_mock_game(
    ActivePlay,
    MockGameParams(
      round: params.round,
      lives: params.lives,
      stars: params.stars,
      my_cards: params.cards,
      player_count: params.players,
      played_cards: played_cards,
      last_mistake: None,
      game_log: game_log,
    ),
  )
}

// PAUSE PHASE

pub fn build_mock_game_pause(params: MockPauseParams) -> Game {
  let mistake_info =
    MistakeInfo(
      player_nickname: params.player,
      played_card: params.played,
      mistake_cards: [#(params.expected_player, params.expected)],
    )

  // Game log showing the mistake that caused the pause
  let game_log = [
    GameEvent(make_mock_timestamp_at(0), RoundStarted(params.round)),
    GameEvent(
      make_mock_timestamp_at(3000),
      CardPlayed(params.player, params.played, False),
    ),
    GameEvent(make_mock_timestamp_at(3000), LifeLost(params.lives)),
  ]

  build_mock_game(
    Pause,
    MockGameParams(
      round: params.round,
      lives: params.lives,
      stars: params.stars,
      my_cards: params.cards,
      player_count: 2,
      played_cards: [params.played],
      last_mistake: Some(mistake_info),
      game_log: game_log,
    ),
  )
}

// STRIKE PHASE

pub fn build_mock_game_strike(params: MockStrikeParams) -> Game {
  // Game log showing some activity before strike vote
  let game_log = [
    GameEvent(make_mock_timestamp_at(0), RoundStarted(1)),
    GameEvent(make_mock_timestamp_at(2000), CardPlayed("Alice", 15, False)),
    GameEvent(make_mock_timestamp_at(4500), CardPlayed("Bob", 22, False)),
  ]

  build_mock_game(
    Strike,
    MockGameParams(
      round: 1,
      lives: 3,
      stars: 1,
      my_cards: params.cards,
      player_count: params.votes + params.pending,
      played_cards: [15, 22],
      last_mistake: None,
      game_log: game_log,
    ),
  )
}

// ABANDON VOTE PHASE

pub fn build_mock_game_abandon(params: MockAbandonParams) -> Game {
  // Game log showing some activity before abandon vote
  let game_log = [
    GameEvent(make_mock_timestamp_at(0), RoundStarted(1)),
    GameEvent(make_mock_timestamp_at(3000), CardPlayed("Alice", 8, False)),
  ]

  build_mock_game(
    AbandonVote,
    MockGameParams(
      round: 1,
      lives: 3,
      stars: 1,
      my_cards: params.cards,
      player_count: params.votes + params.pending,
      played_cards: [8],
      last_mistake: None,
      game_log: game_log,
    ),
  )
}

// END GAME PHASE

pub fn build_mock_game_end(params: MockEndParams) -> Game {
  // Build a game log representing the completed game
  let game_log = build_end_game_log(params.rounds, params.outcome, params.lives)

  let game =
    build_mock_game(
      EndGame(params.outcome),
      MockGameParams(
        round: params.rounds,
        lives: params.lives,
        stars: params.stars,
        my_cards: [],
        player_count: 2,
        played_cards: [],
        last_mistake: None,
        game_log: game_log,
      ),
    )

  Game(..game, games_played: params.games, total_rounds: params.rounds)
}

// VOTE STATUS

/// Build mock vote status for strike/abandon phases
pub fn build_mock_vote_status(
  total_votes: Int,
  pending_count: Int,
  seconds: Int,
  user_voted: Bool,
) -> #(List(#(String, Bool)), List(String), Int) {
  let mock_user_id = get_mock_user_id()

  // If user voted, they're first in the votes list; otherwise other players voted
  let voted_player_ids = case user_voted {
    True ->
      [#(mock_user_id, True)]
      |> list.append(
        int.range(from: 1, to: total_votes - 1, with: [], run: fn(acc, i) {
          [#("player-" <> int.to_string(i), True), ..acc]
        })
        |> list.reverse,
      )
    False ->
      int.range(from: 0, to: total_votes - 1, with: [], run: fn(acc, i) {
        [#("player-" <> int.to_string(i), True), ..acc]
      })
      |> list.reverse
  }

  // If user hasn't voted, they're first in the pending list; otherwise other players are pending
  let pending_player_ids = case user_voted {
    False ->
      [mock_user_id]
      |> list.append(
        int.range(
          from: total_votes,
          to: total_votes + pending_count - 2,
          with: [],
          run: fn(acc, i) { ["player-" <> int.to_string(i), ..acc] },
        )
        |> list.reverse,
      )
    True ->
      int.range(
        from: total_votes,
        to: total_votes + pending_count - 1,
        with: [],
        run: fn(acc, i) { ["player-" <> int.to_string(i), ..acc] },
      )
      |> list.reverse
  }

  #(voted_player_ids, pending_player_ids, seconds)
}
