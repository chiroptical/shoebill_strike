import gleam/int
import gleam/list
import mock_routes/builders/common.{make_mock_timestamp_at}
import protocol/types.{
  type GameEvent, type GameOutcome, CardPlayed, GameEvent, LifeLost, Loss,
  MistakeDiscard, RoundStarted, StrikeDiscard, StrikeUsed,
}

/// Build a mock game log with events from previous rounds
pub fn build_mock_game_log(
  current_round: Int,
  current_lives: Int,
) -> List(GameEvent) {
  // If we're on round 1, no previous events
  case current_round {
    1 -> [GameEvent(make_mock_timestamp_at(0), RoundStarted(1))]
    _ -> {
      // Build events for completed rounds
      let completed_rounds = current_round - 1
      let had_mistake = current_lives < 3

      // Accumulate events across rounds
      build_round_events(1, completed_rounds, had_mistake, 0, [])
      |> list.append([
        // Current round started
        GameEvent(
          make_mock_timestamp_at(completed_rounds * 15_000),
          RoundStarted(current_round),
        ),
      ])
    }
  }
}

/// Recursively build events for each completed round
fn build_round_events(
  round: Int,
  total_rounds: Int,
  include_mistake: Bool,
  time_offset: Int,
  acc: List(GameEvent),
) -> List(GameEvent) {
  case round > total_rounds {
    True -> acc
    False -> {
      let round_start =
        GameEvent(make_mock_timestamp_at(time_offset), RoundStarted(round))

      // Cards played in this round (simulating 4 players with multiple cards each)
      let card1 =
        GameEvent(
          make_mock_timestamp_at(time_offset + 1500),
          CardPlayed("Alice", round * 10 + 2, False),
        )
      let card2 =
        GameEvent(
          make_mock_timestamp_at(time_offset + 3000),
          CardPlayed("Bob", round * 10 + 5, False),
        )
      let card3 =
        GameEvent(
          make_mock_timestamp_at(time_offset + 4500),
          CardPlayed("Carol", round * 10 + 8, False),
        )
      let card4 =
        GameEvent(
          make_mock_timestamp_at(time_offset + 6000),
          CardPlayed("Dave", round * 10 + 12, False),
        )
      let card5 =
        GameEvent(
          make_mock_timestamp_at(time_offset + 7500),
          CardPlayed("Alice", round * 10 + 15, False),
        )
      let card6 =
        GameEvent(
          make_mock_timestamp_at(time_offset + 9000),
          CardPlayed("Bob", round * 10 + 18, False),
        )

      // Add mistake on round 2 and 4 if we lost lives
      let round_events = case round == 2 && include_mistake {
        True -> [
          round_start,
          card1,
          card2,
          GameEvent(
            make_mock_timestamp_at(time_offset + 3500),
            MistakeDiscard("Carol", round * 10 + 6),
          ),
          GameEvent(make_mock_timestamp_at(time_offset + 3600), LifeLost(2)),
          card3,
          card4,
          card5,
          card6,
        ]
        False ->
          case round == 4 && include_mistake {
            True -> [
              round_start,
              card1,
              card2,
              card3,
              GameEvent(
                make_mock_timestamp_at(time_offset + 5000),
                StrikeUsed(0),
              ),
              GameEvent(
                make_mock_timestamp_at(time_offset + 5100),
                StrikeDiscard("Alice", round * 10 + 9),
              ),
              GameEvent(
                make_mock_timestamp_at(time_offset + 5200),
                StrikeDiscard("Bob", round * 10 + 10),
              ),
              card4,
              card5,
              card6,
            ]
            False -> [round_start, card1, card2, card3, card4, card5, card6]
          }
      }

      build_round_events(
        round + 1,
        total_rounds,
        include_mistake,
        time_offset + 12_000,
        list.append(acc, round_events),
      )
    }
  }
}

/// Build a game log for a completed game
pub fn build_end_game_log(
  rounds_completed: Int,
  outcome: GameOutcome,
  final_lives: Int,
) -> List(GameEvent) {
  // Build events for each round played
  let round_events =
    int.range(from: 1, to: rounds_completed, with: [], run: fn(acc, round) {
      let time_offset = { round - 1 } * 10_000
      list.append(acc, [
        GameEvent(make_mock_timestamp_at(time_offset), RoundStarted(round)),
        GameEvent(
          make_mock_timestamp_at(time_offset + 2000),
          CardPlayed("Alice", round * 7, False),
        ),
        GameEvent(
          make_mock_timestamp_at(time_offset + 5000),
          CardPlayed("Bob", round * 7 + 4, False),
        ),
      ])
    })

  // Add life lost events if we didn't win with full lives
  case outcome, final_lives < 3 {
    Loss, _ ->
      list.append(round_events, [
        GameEvent(
          make_mock_timestamp_at(rounds_completed * 10_000),
          LifeLost(0),
        ),
      ])
    _, True ->
      // Lost some lives during the game
      list.append(round_events, [
        GameEvent(make_mock_timestamp_at(15_000), LifeLost(final_lives)),
      ])
    _, _ -> round_events
  }
}
