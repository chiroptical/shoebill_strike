import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/option.{None}
import protocol/helpers
import protocol/types.{
  type Card, type ClientMessage, type Game, type GameEvent, type GameEventType,
  type GameOutcome, type GamePlayer, type MistakeInfo, type Phase, AbandonVote,
  Abandoned, ActivePlay, CardPlayed, CastAbandonVote, CastStrikeVote, CreateGame,
  Dealing, EndGame, Game, GameEvent, GamePlayer, InitiateAbandonVote,
  InitiateStrikeVote, JoinGame, LeaveGame, LifeLost, Loss, MistakeDiscard,
  MistakeInfo, Pause, PlayCard, PlayerDisconnectedEvent, PlayerReconnectedEvent,
  RestartGame, RoundStarted, StartGame, Strike, StrikeDiscard, StrikeUsed,
  ToggleReady, ToggleReadyInGame, Win,
}

/// Decode ClientMessage from JSON
pub fn decode_client_message(
  data: Dynamic,
) -> Result(ClientMessage, List(decode.DecodeError)) {
  let type_decoder = {
    use msg_type <- decode.field("type", decode.string)
    decode.success(msg_type)
  }

  case decode.run(data, type_decoder) {
    Ok("create_game") -> {
      let decoder = {
        use user_id <- decode.field("user_id", decode.string)
        use nickname <- decode.field("nickname", decode.string)
        decode.success(CreateGame(user_id, nickname))
      }
      decode.run(data, decoder)
    }
    Ok("join_game") -> {
      let decoder = {
        use code <- decode.field("code", decode.string)
        use user_id <- decode.field("user_id", decode.string)
        use nickname <- decode.field("nickname", decode.string)
        decode.success(JoinGame(code, user_id, nickname))
      }
      decode.run(data, decoder)
    }
    Ok("toggle_ready") -> Ok(ToggleReady)
    Ok("start_game") -> Ok(StartGame)
    Ok("toggle_ready_in_game") -> Ok(ToggleReadyInGame)
    Ok("play_card") -> Ok(PlayCard)
    Ok("initiate_strike_vote") -> Ok(InitiateStrikeVote)
    Ok("cast_strike_vote") -> {
      let decoder = {
        use approve <- decode.field("approve", decode.bool)
        decode.success(CastStrikeVote(approve))
      }
      decode.run(data, decoder)
    }
    Ok("initiate_abandon_vote") -> Ok(InitiateAbandonVote)
    Ok("cast_abandon_vote") -> {
      let decoder = {
        use approve <- decode.field("approve", decode.bool)
        decode.success(CastAbandonVote(approve))
      }
      decode.run(data, decoder)
    }
    Ok("leave_game") -> Ok(LeaveGame)
    Ok("restart_game") -> Ok(RestartGame)
    Ok(msg_type) -> {
      let err =
        decode.DecodeError(
          expected: "valid message type",
          found: msg_type,
          path: ["type"],
        )
      Error([err])
    }
    Error(err) -> Error(err)
  }
}

/// Decode GameOutcome from string
pub fn decode_game_outcome(outcome_str: String) -> Result(GameOutcome, String) {
  case outcome_str {
    "win" -> Ok(Win)
    "loss" -> Ok(Loss)
    "abandoned" -> Ok(Abandoned)
    _ -> Error("Invalid game outcome: " <> outcome_str)
  }
}

/// Decode Phase from string (non-EndGame phases only)
pub fn decode_phase(phase_str: String) -> Result(Phase, String) {
  case phase_str {
    "dealing" -> Ok(Dealing)
    "active_play" -> Ok(ActivePlay)
    "pause" -> Ok(Pause)
    "strike" -> Ok(Strike)
    "abandon_vote" -> Ok(AbandonVote)
    _ -> Error("Invalid phase: " <> phase_str)
  }
}

/// Decode a list of integers
fn decode_int_list() -> decode.Decoder(List(Int)) {
  decode.list(decode.int)
}

/// Decoder for GamePlayer
pub fn game_player_decoder() -> decode.Decoder(GamePlayer) {
  use user_id <- decode.field("user_id", decode.string)
  use nickname <- decode.field("nickname", decode.string)
  use hand <- decode.field("hand", decode_int_list())
  use is_ready <- decode.field("is_ready", decode.bool)
  use is_connected <- decode.field("is_connected", decode.bool)
  use last_card_played <- decode.optional_field(
    "last_card_played",
    None,
    decode.optional(decode.int),
  )
  decode.success(GamePlayer(
    user_id,
    nickname,
    hand,
    is_ready,
    is_connected,
    last_card_played,
  ))
}

/// Decoder for Phase (string for simple phases, object for EndGame)
pub fn phase_decoder() -> decode.Decoder(Phase) {
  let string_decoder = {
    use phase_str <- decode.then(decode.string)
    case decode_phase(phase_str) {
      Ok(phase) -> decode.success(phase)
      Error(_) -> decode.failure(Dealing, "Phase")
    }
  }
  let end_game_decoder = {
    use outcome_str <- decode.field("outcome", decode.string)
    case decode_game_outcome(outcome_str) {
      Ok(outcome) -> decode.success(EndGame(outcome))
      Error(_) -> decode.failure(EndGame(Loss), "GameOutcome")
    }
  }
  decode.one_of(string_decoder, [end_game_decoder])
}

/// Decoder for a mistake card entry (nickname, card)
fn mistake_card_decoder() -> decode.Decoder(#(String, Card)) {
  use nickname <- decode.field("nickname", decode.string)
  use card <- decode.field("card", decode.int)
  decode.success(#(nickname, card))
}

/// Decoder for MistakeInfo
pub fn mistake_info_decoder() -> decode.Decoder(MistakeInfo) {
  use player_nickname <- decode.field("player_nickname", decode.string)
  use played_card <- decode.field("played_card", decode.int)
  use mistake_cards <- decode.field(
    "mistake_cards",
    decode.list(mistake_card_decoder()),
  )
  decode.success(MistakeInfo(player_nickname, played_card, mistake_cards))
}

/// Decoder for GameEventType
pub fn game_event_type_decoder() -> decode.Decoder(GameEventType) {
  use event_type <- decode.field("event_type", decode.string)
  case event_type {
    "round_started" -> {
      use round <- decode.field("round", decode.int)
      decode.success(RoundStarted(round))
    }
    "card_played" -> {
      use player_nickname <- decode.field("player_nickname", decode.string)
      use card <- decode.field("card", decode.int)
      use autoplayed <- decode.optional_field("autoplayed", False, decode.bool)
      decode.success(CardPlayed(player_nickname, card, autoplayed))
    }
    "mistake_discard" -> {
      use player_nickname <- decode.field("player_nickname", decode.string)
      use card <- decode.field("card", decode.int)
      decode.success(MistakeDiscard(player_nickname, card))
    }
    "strike_discard" -> {
      use player_nickname <- decode.field("player_nickname", decode.string)
      use card <- decode.field("card", decode.int)
      decode.success(StrikeDiscard(player_nickname, card))
    }
    "life_lost" -> {
      use lives_remaining <- decode.field("lives_remaining", decode.int)
      decode.success(LifeLost(lives_remaining))
    }
    "strike_used" -> {
      use strikes_remaining <- decode.field("strikes_remaining", decode.int)
      decode.success(StrikeUsed(strikes_remaining))
    }
    "player_disconnected" -> {
      use nickname <- decode.field("nickname", decode.string)
      decode.success(PlayerDisconnectedEvent(nickname))
    }
    "player_reconnected" -> {
      use nickname <- decode.field("nickname", decode.string)
      decode.success(PlayerReconnectedEvent(nickname))
    }
    _ -> decode.failure(RoundStarted(0), "GameEventType")
  }
}

/// Decoder for GameEvent
pub fn game_event_decoder() -> decode.Decoder(GameEvent) {
  use timestamp_ms <- decode.field("timestamp", decode.int)
  use event_type <- decode.then(game_event_type_decoder())
  decode.success(GameEvent(
    helpers.unix_ms_to_timestamp(timestamp_ms),
    event_type,
  ))
}

/// Decoder for Game
pub fn game_decoder() -> decode.Decoder(Game) {
  use code <- decode.field("code", decode.string)
  use host_user_id <- decode.field("host_user_id", decode.string)
  use games_played <- decode.field("games_played", decode.int)
  use players <- decode.field("players", decode.list(game_player_decoder()))
  use current_round <- decode.field("current_round", decode.int)
  use total_rounds <- decode.field("total_rounds", decode.int)
  use lives <- decode.field("lives", decode.int)
  use strikes <- decode.field("strikes", decode.int)
  use phase <- decode.field("phase", phase_decoder())
  use played_cards <- decode.field("played_cards", decode_int_list())
  use last_mistake <- decode.optional_field(
    "last_mistake",
    None,
    decode.optional(mistake_info_decoder()),
  )
  use abandon_vote_previous_phase <- decode.optional_field(
    "abandon_vote_previous_phase",
    None,
    decode.optional(phase_decoder()),
  )
  use game_start_timestamp_ms <- decode.field(
    "game_start_timestamp",
    decode.int,
  )
  use game_log <- decode.field("game_log", decode.list(game_event_decoder()))
  decode.success(Game(
    code,
    host_user_id,
    games_played,
    players,
    current_round,
    total_rounds,
    lives,
    strikes,
    phase,
    played_cards,
    last_mistake,
    abandon_vote_previous_phase,
    helpers.unix_ms_to_timestamp(game_start_timestamp_ms),
    game_log,
  ))
}
