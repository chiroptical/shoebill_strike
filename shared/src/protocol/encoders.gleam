import gleam/json
import gleam/option.{None, Some}
import protocol/helpers
import protocol/types.{
  type Game, type GameEvent, type GameEventType, type GameOutcome,
  type GamePlayer, type Lobby, type MistakeInfo, type Phase, type Player,
  type ServerMessage, AbandonVote, AbandonVoteUpdate, Abandoned, ActivePlay,
  CardPlayed, CountdownTick, Dealing, EndGame, GameCreated, GameJoined,
  GameLogEvent, GameStarted, GameStateUpdate, LifeLost, LobbyState, Loss,
  MistakeDiscard, Pause, PhaseTransition, PlayerDisconnected,
  PlayerDisconnectedEvent, PlayerLeft, PlayerReconnected, PlayerReconnectedEvent,
  RoundStarted, ServerError, Strike, StrikeDiscard, StrikeUsed, StrikeVoteUpdate,
  Win, YouLeft,
}

/// Encode Player to JSON
pub fn encode_player(player: Player) -> json.Json {
  json.object([
    #("user_id", json.string(player.user_id)),
    #("nickname", json.string(player.nickname)),
    #("is_ready", json.bool(player.is_ready)),
    #("is_creator", json.bool(player.is_creator)),
    #("is_connected", json.bool(player.is_connected)),
  ])
}

/// Encode Lobby to JSON
pub fn encode_lobby(lobby: Lobby) -> json.Json {
  json.object([
    #("code", json.string(lobby.code)),
    #("players", json.array(lobby.players, encode_player)),
    #("games_played", json.int(lobby.games_played)),
  ])
}

/// Encode GameOutcome to JSON
pub fn encode_game_outcome(outcome: GameOutcome) -> json.Json {
  case outcome {
    Win -> json.string("win")
    Loss -> json.string("loss")
    Abandoned -> json.string("abandoned")
  }
}

/// Encode Phase to JSON
pub fn encode_phase(phase: Phase) -> json.Json {
  case phase {
    Dealing -> json.string("dealing")
    ActivePlay -> json.string("active_play")
    Pause -> json.string("pause")
    Strike -> json.string("strike")
    AbandonVote -> json.string("abandon_vote")
    EndGame(outcome) ->
      json.object([
        #("type", json.string("end_game")),
        #("outcome", encode_game_outcome(outcome)),
      ])
  }
}

/// Encode GamePlayer to JSON
pub fn encode_game_player(player: GamePlayer) -> json.Json {
  json.object([
    #("user_id", json.string(player.user_id)),
    #("nickname", json.string(player.nickname)),
    #("hand", json.array(player.hand, json.int)),
    #("is_ready", json.bool(player.is_ready)),
    #("is_connected", json.bool(player.is_connected)),
    #("last_card_played", case player.last_card_played {
      Some(card) -> json.int(card)
      None -> json.null()
    }),
  ])
}

/// Encode MistakeInfo to JSON
pub fn encode_mistake_info(info: MistakeInfo) -> json.Json {
  json.object([
    #("player_nickname", json.string(info.player_nickname)),
    #("played_card", json.int(info.played_card)),
    #(
      "mistake_cards",
      json.array(info.mistake_cards, fn(pair) {
        json.object([
          #("nickname", json.string(pair.0)),
          #("card", json.int(pair.1)),
        ])
      }),
    ),
  ])
}

/// Encode GameEventType to JSON
pub fn encode_game_event_type(event_type: GameEventType) -> json.Json {
  case event_type {
    RoundStarted(round) ->
      json.object([
        #("event_type", json.string("round_started")),
        #("round", json.int(round)),
      ])
    CardPlayed(player_nickname, card, autoplayed) ->
      json.object([
        #("event_type", json.string("card_played")),
        #("player_nickname", json.string(player_nickname)),
        #("card", json.int(card)),
        #("autoplayed", json.bool(autoplayed)),
      ])
    MistakeDiscard(player_nickname, card) ->
      json.object([
        #("event_type", json.string("mistake_discard")),
        #("player_nickname", json.string(player_nickname)),
        #("card", json.int(card)),
      ])
    StrikeDiscard(player_nickname, card) ->
      json.object([
        #("event_type", json.string("strike_discard")),
        #("player_nickname", json.string(player_nickname)),
        #("card", json.int(card)),
      ])
    LifeLost(lives_remaining) ->
      json.object([
        #("event_type", json.string("life_lost")),
        #("lives_remaining", json.int(lives_remaining)),
      ])
    StrikeUsed(strikes_remaining) ->
      json.object([
        #("event_type", json.string("strike_used")),
        #("strikes_remaining", json.int(strikes_remaining)),
      ])
    PlayerDisconnectedEvent(nickname) ->
      json.object([
        #("event_type", json.string("player_disconnected")),
        #("nickname", json.string(nickname)),
      ])
    PlayerReconnectedEvent(nickname) ->
      json.object([
        #("event_type", json.string("player_reconnected")),
        #("nickname", json.string(nickname)),
      ])
  }
}

/// Encode GameEvent to JSON
pub fn encode_game_event(event: GameEvent) -> json.Json {
  let base = encode_game_event_type(event.event_type)
  // Merge timestamp into the event type object
  case base {
    _ ->
      json.object([
        #("timestamp", json.int(helpers.timestamp_to_unix_ms(event.timestamp))),
        #("event_type", case event.event_type {
          RoundStarted(_) -> json.string("round_started")
          CardPlayed(_, _, _) -> json.string("card_played")
          MistakeDiscard(_, _) -> json.string("mistake_discard")
          StrikeDiscard(_, _) -> json.string("strike_discard")
          LifeLost(_) -> json.string("life_lost")
          StrikeUsed(_) -> json.string("strike_used")
          PlayerDisconnectedEvent(_) -> json.string("player_disconnected")
          PlayerReconnectedEvent(_) -> json.string("player_reconnected")
        }),
        ..encode_game_event_type_fields(event.event_type)
      ])
  }
}

/// Helper to get the fields for a game event type (without the event_type field)
fn encode_game_event_type_fields(
  event_type: GameEventType,
) -> List(#(String, json.Json)) {
  case event_type {
    RoundStarted(round) -> [#("round", json.int(round))]
    CardPlayed(player_nickname, card, autoplayed) -> [
      #("player_nickname", json.string(player_nickname)),
      #("card", json.int(card)),
      #("autoplayed", json.bool(autoplayed)),
    ]
    MistakeDiscard(player_nickname, card) -> [
      #("player_nickname", json.string(player_nickname)),
      #("card", json.int(card)),
    ]
    StrikeDiscard(player_nickname, card) -> [
      #("player_nickname", json.string(player_nickname)),
      #("card", json.int(card)),
    ]
    LifeLost(lives_remaining) -> [
      #("lives_remaining", json.int(lives_remaining)),
    ]
    StrikeUsed(strikes_remaining) -> [
      #("strikes_remaining", json.int(strikes_remaining)),
    ]
    PlayerDisconnectedEvent(nickname) -> [
      #("nickname", json.string(nickname)),
    ]
    PlayerReconnectedEvent(nickname) -> [
      #("nickname", json.string(nickname)),
    ]
  }
}

/// Encode Game to JSON
pub fn encode_game(game: Game) -> json.Json {
  json.object([
    #("code", json.string(game.code)),
    #("host_user_id", json.string(game.host_user_id)),
    #("games_played", json.int(game.games_played)),
    #("players", json.array(game.players, encode_game_player)),
    #("current_round", json.int(game.current_round)),
    #("total_rounds", json.int(game.total_rounds)),
    #("lives", json.int(game.lives)),
    #("strikes", json.int(game.strikes)),
    #("phase", encode_phase(game.phase)),
    #("played_cards", json.array(game.played_cards, json.int)),
    #("last_mistake", case game.last_mistake {
      None -> json.null()
      Some(info) -> encode_mistake_info(info)
    }),
    #("abandon_vote_previous_phase", case game.abandon_vote_previous_phase {
      None -> json.null()
      Some(phase) -> encode_phase(phase)
    }),
    #(
      "game_start_timestamp",
      json.int(helpers.timestamp_to_unix_ms(game.game_start_timestamp)),
    ),
    #("game_log", json.array(game.game_log, encode_game_event)),
  ])
}

/// Encode ServerMessage to JSON
pub fn encode_server_message(msg: ServerMessage) -> json.Json {
  case msg {
    GameCreated(code) ->
      json.object([
        #("type", json.string("game_created")),
        #("code", json.string(code)),
      ])
    GameJoined -> json.object([#("type", json.string("game_joined"))])
    LobbyState(lobby) ->
      json.object([
        #("type", json.string("lobby_state")),
        #("lobby", encode_lobby(lobby)),
      ])
    GameStarted -> json.object([#("type", json.string("game_started"))])
    ServerError(message) ->
      json.object([
        #("type", json.string("error")),
        #("message", json.string(message)),
      ])
    GameStateUpdate(game) ->
      json.object([
        #("type", json.string("game_state_update")),
        #("game", encode_game(game)),
      ])
    CountdownTick(seconds) ->
      json.object([
        #("type", json.string("countdown_tick")),
        #("seconds", json.int(seconds)),
      ])
    PhaseTransition(phase) ->
      json.object([
        #("type", json.string("phase_transition")),
        #("phase", encode_phase(phase)),
      ])
    StrikeVoteUpdate(votes, pending, seconds_remaining) ->
      json.object([
        #("type", json.string("strike_vote_update")),
        #(
          "votes",
          json.array(votes, fn(vote) {
            json.object([
              #("user_id", json.string(vote.0)),
              #("approve", json.bool(vote.1)),
            ])
          }),
        ),
        #("pending", json.array(pending, json.string)),
        #("seconds_remaining", json.int(seconds_remaining)),
      ])
    AbandonVoteUpdate(votes, pending, seconds_remaining) ->
      json.object([
        #("type", json.string("abandon_vote_update")),
        #(
          "votes",
          json.array(votes, fn(vote) {
            json.object([
              #("user_id", json.string(vote.0)),
              #("approve", json.bool(vote.1)),
            ])
          }),
        ),
        #("pending", json.array(pending, json.string)),
        #("seconds_remaining", json.int(seconds_remaining)),
      ])
    PlayerLeft(user_id, new_host_user_id) ->
      json.object([
        #("type", json.string("player_left")),
        #("user_id", json.string(user_id)),
        #("new_host_user_id", case new_host_user_id {
          Some(id) -> json.string(id)
          None -> json.null()
        }),
      ])
    YouLeft -> json.object([#("type", json.string("you_left"))])
    GameLogEvent(event) ->
      json.object([
        #("type", json.string("game_log_event")),
        #("event", encode_game_event(event)),
      ])
    PlayerDisconnected(user_id) ->
      json.object([
        #("type", json.string("player_disconnected")),
        #("user_id", json.string(user_id)),
      ])
    PlayerReconnected(user_id) ->
      json.object([
        #("type", json.string("player_reconnected")),
        #("user_id", json.string(user_id)),
      ])
  }
}
