import client/msg.{type Msg}
import gleam/float
import gleam/int
import gleam/list
import gleam/string
import gleam/time/timestamp.{type Timestamp}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import protocol/helpers
import protocol/types as protocol

/// Represents either a single event or consolidated MistakeDiscards
pub type ConsolidatedEvent {
  SingleEvent(protocol.GameEvent)
  ConsolidatedMistakeDiscard(
    timestamp: Timestamp,
    nickname: String,
    cards: List(Int),
  )
}

/// View the game log - mobile-first responsive component
/// Mobile: fixed overlay at bottom of viewport
/// Desktop (lg+): absolute sidebar next to main content
pub fn view_game_log(game: protocol.Game) -> Element(Msg) {
  let start_ms = helpers.timestamp_to_unix_ms(game.game_start_timestamp)
  // game_log is stored newest-first, reverse to display oldest-first
  let events_oldest_first = list.reverse(game.game_log)
  // Consolidate consecutive MistakeDiscard events by player
  let consolidated = consolidate_mistake_discards(events_oldest_first)

  html.div([attribute.id("game-log"), attribute.class("game-log")], [
    html.h3([attribute.class("text-sm font-semibold text-gray-400 mb-2")], [
      element.text("Game Log"),
    ]),
    html.ul(
      [attribute.class("game-log-list")],
      list.map(consolidated, fn(entry) {
        view_consolidated_event(entry, start_ms)
      }),
    ),
  ])
}

/// View the game log inline (no fixed/absolute positioning)
/// For use in flex columns where normal document flow is needed
pub fn view_game_log_inline(game: protocol.Game) -> Element(Msg) {
  let start_ms = helpers.timestamp_to_unix_ms(game.game_start_timestamp)
  let events_oldest_first = list.reverse(game.game_log)
  let consolidated = consolidate_mistake_discards(events_oldest_first)

  html.div(
    [
      attribute.class(
        "bg-gray-800 border border-gray-700 rounded-lg p-3 overflow-y-auto max-h-64",
      ),
    ],
    [
      html.h3([attribute.class("text-sm font-semibold text-gray-400 mb-2")], [
        element.text("Game Log"),
      ]),
      html.ul(
        [attribute.class("game-log-list")],
        list.map(consolidated, fn(entry) {
          view_consolidated_event(entry, start_ms)
        }),
      ),
    ],
  )
}

/// Consolidate consecutive MistakeDiscard events by the same player
pub fn consolidate_mistake_discards(
  events: List(protocol.GameEvent),
) -> List(ConsolidatedEvent) {
  case events {
    [] -> []
    [first, ..rest] -> {
      case first.event_type {
        protocol.MistakeDiscard(nick, card) -> {
          // Collect all consecutive MistakeDiscards for the same player
          let #(same_player_cards, remaining) =
            collect_same_player_discards(nick, rest, [card])
          let consolidated =
            ConsolidatedMistakeDiscard(first.timestamp, nick, same_player_cards)
          [consolidated, ..consolidate_mistake_discards(remaining)]
        }
        _ -> [SingleEvent(first), ..consolidate_mistake_discards(rest)]
      }
    }
  }
}

/// Collect consecutive MistakeDiscard events for the same player
pub fn collect_same_player_discards(
  nickname: String,
  events: List(protocol.GameEvent),
  cards: List(Int),
) -> #(List(Int), List(protocol.GameEvent)) {
  case events {
    [] -> #(list.reverse(cards), [])
    [first, ..rest] -> {
      case first.event_type {
        protocol.MistakeDiscard(nick, card) if nick == nickname -> {
          collect_same_player_discards(nickname, rest, [card, ..cards])
        }
        _ -> #(list.reverse(cards), events)
      }
    }
  }
}

/// View a consolidated event entry
pub fn view_consolidated_event(
  entry: ConsolidatedEvent,
  start_ms: Int,
) -> Element(Msg) {
  case entry {
    SingleEvent(event) -> view_game_event(event, start_ms)
    ConsolidatedMistakeDiscard(ts, nickname, cards) -> {
      let card_strings =
        cards
        |> list.sort(int.compare)
        |> list.map(int.to_string)
      let text =
        "Mistake! "
        <> nickname
        <> " forced to discard "
        <> string.join(card_strings, ", ")
      html.li([attribute.class("game-log-entry")], [
        html.span([attribute.class("timestamp")], [
          element.text(format_event_timestamp(ts, start_ms)),
        ]),
        html.span([attribute.class("event")], [element.text(" " <> text)]),
      ])
    }
  }
}

/// View a single game event
pub fn view_game_event(event: protocol.GameEvent, start_ms: Int) -> Element(Msg) {
  html.li([attribute.class("game-log-entry")], [
    html.span([attribute.class("timestamp")], [
      element.text(format_event_timestamp(event.timestamp, start_ms)),
    ]),
    html.span([attribute.class("event")], [
      element.text(" " <> format_event_type(event.event_type)),
    ]),
  ])
}

/// Formats timestamp as seconds since game start (e.g., "3.12s")
pub fn format_event_timestamp(ts: Timestamp, start_ms: Int) -> String {
  let event_ms = helpers.timestamp_to_unix_ms(ts)
  let diff_ms = event_ms - start_ms
  let seconds = int.to_float(diff_ms) /. 1000.0
  // Format to 2 decimal places
  let seconds_str = float.to_string(seconds)
  // Truncate to 2 decimal places
  let formatted = case string.split(seconds_str, ".") {
    [whole, decimal] -> {
      let truncated_decimal = string.slice(decimal, 0, 2)
      // Pad with zeros if needed
      let padded = case string.length(truncated_decimal) {
        0 -> "00"
        1 -> truncated_decimal <> "0"
        _ -> truncated_decimal
      }
      whole <> "." <> padded
    }
    [whole] -> whole <> ".00"
    _ -> seconds_str
  }
  formatted <> "s"
}

/// Format event type as human-readable string
pub fn format_event_type(event_type: protocol.GameEventType) -> String {
  case event_type {
    protocol.RoundStarted(round) ->
      "Round " <> int.to_string(round) <> " started"
    protocol.CardPlayed(nick, card, autoplayed) ->
      case autoplayed {
        True -> nick <> " automatically played " <> int.to_string(card)
        False -> nick <> " played " <> int.to_string(card)
      }
    protocol.MistakeDiscard(nick, card) ->
      "Mistake! " <> nick <> " forced to discard " <> int.to_string(card)
    protocol.StrikeDiscard(nick, card) ->
      nick <> " discarded " <> int.to_string(card) <> " (strike)"
    protocol.LifeLost(remaining) ->
      "Life lost! " <> int.to_string(remaining) <> " remaining"
    protocol.StrikeUsed(remaining) ->
      "Strike used! " <> int.to_string(remaining) <> " remaining"
    protocol.PlayerDisconnectedEvent(nickname) -> nickname <> " disconnected"
    protocol.PlayerReconnectedEvent(nickname) -> nickname <> " reconnected"
  }
}
