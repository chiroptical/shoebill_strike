import client/views/game_log.{
  ConsolidatedMistakeDiscard, SingleEvent, collect_same_player_discards,
  consolidate_mistake_discards, format_event_timestamp, format_event_type,
}
import gleam/time/timestamp
import gleeunit/should
import protocol/types as protocol

// format_event_timestamp tests

pub fn format_event_timestamp_zero_seconds_test() {
  let event_ts = timestamp.from_unix_seconds_and_nanoseconds(1000, 0)
  let start_ms = 1_000_000

  format_event_timestamp(event_ts, start_ms)
  |> should.equal("0.00s")
}

pub fn format_event_timestamp_whole_seconds_test() {
  let event_ts = timestamp.from_unix_seconds_and_nanoseconds(1005, 0)
  let start_ms = 1_000_000

  format_event_timestamp(event_ts, start_ms)
  |> should.equal("5.00s")
}

pub fn format_event_timestamp_with_milliseconds_test() {
  let event_ts = timestamp.from_unix_seconds_and_nanoseconds(1003, 120_000_000)
  let start_ms = 1_000_000

  format_event_timestamp(event_ts, start_ms)
  |> should.equal("3.12s")
}

pub fn format_event_timestamp_single_decimal_digit_test() {
  let event_ts = timestamp.from_unix_seconds_and_nanoseconds(1002, 500_000_000)
  let start_ms = 1_000_000

  format_event_timestamp(event_ts, start_ms)
  |> should.equal("2.50s")
}

// format_event_type tests

pub fn format_event_type_round_started_test() {
  format_event_type(protocol.RoundStarted(1))
  |> should.equal("Round 1 started")

  format_event_type(protocol.RoundStarted(5))
  |> should.equal("Round 5 started")
}

pub fn format_event_type_card_played_test() {
  format_event_type(protocol.CardPlayed("Alice", 42, False))
  |> should.equal("Alice played 42")
}

pub fn format_event_type_card_played_autoplayed_test() {
  format_event_type(protocol.CardPlayed("Bob", 99, True))
  |> should.equal("Bob automatically played 99")
}

pub fn format_event_type_mistake_discard_test() {
  format_event_type(protocol.MistakeDiscard("Charlie", 15))
  |> should.equal("Mistake! Charlie forced to discard 15")
}

pub fn format_event_type_strike_discard_test() {
  format_event_type(protocol.StrikeDiscard("Diana", 7))
  |> should.equal("Diana discarded 7 (strike)")
}

pub fn format_event_type_life_lost_test() {
  format_event_type(protocol.LifeLost(2))
  |> should.equal("Life lost! 2 remaining")

  format_event_type(protocol.LifeLost(0))
  |> should.equal("Life lost! 0 remaining")
}

pub fn format_event_type_strike_used_test() {
  format_event_type(protocol.StrikeUsed(1))
  |> should.equal("Strike used! 1 remaining")
}

pub fn format_event_type_player_disconnected_test() {
  format_event_type(protocol.PlayerDisconnectedEvent("Eve"))
  |> should.equal("Eve disconnected")
}

pub fn format_event_type_player_reconnected_test() {
  format_event_type(protocol.PlayerReconnectedEvent("Frank"))
  |> should.equal("Frank reconnected")
}

// consolidate_mistake_discards tests

pub fn consolidate_mistake_discards_empty_list_test() {
  consolidate_mistake_discards([])
  |> should.equal([])
}

pub fn consolidate_mistake_discards_single_non_mistake_test() {
  let ts = timestamp.from_unix_seconds_and_nanoseconds(1000, 0)
  let events = [protocol.GameEvent(ts, protocol.RoundStarted(1))]

  let result = consolidate_mistake_discards(events)

  case result {
    [SingleEvent(event)] -> {
      case event.event_type {
        protocol.RoundStarted(round) -> round |> should.equal(1)
        _ -> should.fail()
      }
    }
    _ -> should.fail()
  }
}

pub fn consolidate_mistake_discards_single_mistake_test() {
  let ts = timestamp.from_unix_seconds_and_nanoseconds(1000, 0)
  let events = [protocol.GameEvent(ts, protocol.MistakeDiscard("Alice", 10))]

  let result = consolidate_mistake_discards(events)

  case result {
    [ConsolidatedMistakeDiscard(_, nick, cards)] -> {
      nick |> should.equal("Alice")
      cards |> should.equal([10])
    }
    _ -> should.fail()
  }
}

pub fn consolidate_mistake_discards_consecutive_same_player_test() {
  let ts1 = timestamp.from_unix_seconds_and_nanoseconds(1000, 0)
  let ts2 = timestamp.from_unix_seconds_and_nanoseconds(1001, 0)
  let ts3 = timestamp.from_unix_seconds_and_nanoseconds(1002, 0)
  let events = [
    protocol.GameEvent(ts1, protocol.MistakeDiscard("Alice", 5)),
    protocol.GameEvent(ts2, protocol.MistakeDiscard("Alice", 10)),
    protocol.GameEvent(ts3, protocol.MistakeDiscard("Alice", 15)),
  ]

  let result = consolidate_mistake_discards(events)

  case result {
    [ConsolidatedMistakeDiscard(_, nick, cards)] -> {
      nick |> should.equal("Alice")
      cards |> should.equal([5, 10, 15])
    }
    _ -> should.fail()
  }
}

pub fn consolidate_mistake_discards_different_players_not_consolidated_test() {
  let ts1 = timestamp.from_unix_seconds_and_nanoseconds(1000, 0)
  let ts2 = timestamp.from_unix_seconds_and_nanoseconds(1001, 0)
  let events = [
    protocol.GameEvent(ts1, protocol.MistakeDiscard("Alice", 5)),
    protocol.GameEvent(ts2, protocol.MistakeDiscard("Bob", 10)),
  ]

  let result = consolidate_mistake_discards(events)

  case result {
    [
      ConsolidatedMistakeDiscard(_, nick1, cards1),
      ConsolidatedMistakeDiscard(_, nick2, cards2),
    ] -> {
      nick1 |> should.equal("Alice")
      cards1 |> should.equal([5])
      nick2 |> should.equal("Bob")
      cards2 |> should.equal([10])
    }
    _ -> should.fail()
  }
}

pub fn consolidate_mistake_discards_mixed_events_test() {
  let ts1 = timestamp.from_unix_seconds_and_nanoseconds(1000, 0)
  let ts2 = timestamp.from_unix_seconds_and_nanoseconds(1001, 0)
  let ts3 = timestamp.from_unix_seconds_and_nanoseconds(1002, 0)
  let events = [
    protocol.GameEvent(ts1, protocol.CardPlayed("Alice", 42, False)),
    protocol.GameEvent(ts2, protocol.MistakeDiscard("Bob", 5)),
    protocol.GameEvent(ts3, protocol.LifeLost(2)),
  ]

  let result = consolidate_mistake_discards(events)

  case result {
    [
      SingleEvent(e1),
      ConsolidatedMistakeDiscard(_, nick, cards),
      SingleEvent(e3),
    ] -> {
      case e1.event_type {
        protocol.CardPlayed(_, card, _) -> card |> should.equal(42)
        _ -> should.fail()
      }
      nick |> should.equal("Bob")
      cards |> should.equal([5])
      case e3.event_type {
        protocol.LifeLost(remaining) -> remaining |> should.equal(2)
        _ -> should.fail()
      }
    }
    _ -> should.fail()
  }
}

// collect_same_player_discards tests

pub fn collect_same_player_discards_empty_list_test() {
  let #(cards, remaining) = collect_same_player_discards("Alice", [], [10])

  cards |> should.equal([10])
  remaining |> should.equal([])
}

pub fn collect_same_player_discards_collects_consecutive_test() {
  let ts1 = timestamp.from_unix_seconds_and_nanoseconds(1000, 0)
  let ts2 = timestamp.from_unix_seconds_and_nanoseconds(1001, 0)
  let events = [
    protocol.GameEvent(ts1, protocol.MistakeDiscard("Alice", 20)),
    protocol.GameEvent(ts2, protocol.MistakeDiscard("Alice", 30)),
  ]

  let #(cards, remaining) = collect_same_player_discards("Alice", events, [10])

  cards |> should.equal([10, 20, 30])
  remaining |> should.equal([])
}

pub fn collect_same_player_discards_stops_at_different_player_test() {
  let ts1 = timestamp.from_unix_seconds_and_nanoseconds(1000, 0)
  let ts2 = timestamp.from_unix_seconds_and_nanoseconds(1001, 0)
  let events = [
    protocol.GameEvent(ts1, protocol.MistakeDiscard("Alice", 20)),
    protocol.GameEvent(ts2, protocol.MistakeDiscard("Bob", 30)),
  ]

  let #(cards, remaining) = collect_same_player_discards("Alice", events, [10])

  cards |> should.equal([10, 20])
  case remaining {
    [event] -> {
      case event.event_type {
        protocol.MistakeDiscard(nick, card) -> {
          nick |> should.equal("Bob")
          card |> should.equal(30)
        }
        _ -> should.fail()
      }
    }
    _ -> should.fail()
  }
}

pub fn collect_same_player_discards_stops_at_different_event_type_test() {
  let ts1 = timestamp.from_unix_seconds_and_nanoseconds(1000, 0)
  let ts2 = timestamp.from_unix_seconds_and_nanoseconds(1001, 0)
  let events = [
    protocol.GameEvent(ts1, protocol.MistakeDiscard("Alice", 20)),
    protocol.GameEvent(ts2, protocol.LifeLost(2)),
  ]

  let #(cards, remaining) = collect_same_player_discards("Alice", events, [10])

  cards |> should.equal([10, 20])
  case remaining {
    [event] -> {
      case event.event_type {
        protocol.LifeLost(lives) -> lives |> should.equal(2)
        _ -> should.fail()
      }
    }
    _ -> should.fail()
  }
}
