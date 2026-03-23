import gleam/dynamic
import gleam/dynamic/decode
import gleam/json
import gleam/string
import gleam/time/timestamp
import gleeunit/should
import protocol/decoders
import protocol/encoders
import protocol/helpers
import protocol/types.{
  CardPlayed, CastStrikeVote, CreateGame, GameCreated, GameEvent, GameJoined,
  GameLogEvent, GameStarted, InitiateStrikeVote, JoinGame, LifeLost, Lobby,
  LobbyState, MistakeDiscard, Player, RoundStarted, ServerError, StartGame,
  Strike, StrikeDiscard, StrikeUsed, StrikeVoteUpdate, ToggleReady,
}

pub fn encode_game_created_message_test() {
  let msg = GameCreated(code: "ABC123")

  let encoded = encoders.encode_server_message(msg)
  let json_string = json.to_string(encoded)

  string.contains(json_string, "\"type\":\"game_created\"")
  |> should.be_true()

  string.contains(json_string, "\"code\":\"ABC123\"")
  |> should.be_true()
}

pub fn encode_game_joined_message_test() {
  let msg = GameJoined

  let encoded = encoders.encode_server_message(msg)
  let json_string = json.to_string(encoded)

  string.contains(json_string, "\"type\":\"game_joined\"")
  |> should.be_true()
}

pub fn encode_lobby_state_message_test() {
  let player =
    Player(
      user_id: "user_1",
      nickname: "Alice",
      is_ready: True,
      is_creator: True,
      is_connected: True,
    )
  let lobby = Lobby(code: "XYZ789", players: [player], games_played: 0)
  let msg = LobbyState(lobby: lobby)

  let encoded = encoders.encode_server_message(msg)
  let json_string = json.to_string(encoded)

  string.contains(json_string, "\"type\":\"lobby_state\"")
  |> should.be_true()

  string.contains(json_string, "\"code\":\"XYZ789\"")
  |> should.be_true()

  string.contains(json_string, "\"user_id\":\"user_1\"")
  |> should.be_true()

  string.contains(json_string, "\"nickname\":\"Alice\"")
  |> should.be_true()

  string.contains(json_string, "\"is_ready\":true")
  |> should.be_true()

  string.contains(json_string, "\"is_creator\":true")
  |> should.be_true()
}

pub fn encode_game_started_message_test() {
  let msg = GameStarted

  let encoded = encoders.encode_server_message(msg)
  let json_string = json.to_string(encoded)

  string.contains(json_string, "\"type\":\"game_started\"")
  |> should.be_true()
}

pub fn encode_server_error_message_test() {
  let msg = ServerError(message: "Lobby not found")

  let encoded = encoders.encode_server_message(msg)
  let json_string = json.to_string(encoded)

  string.contains(json_string, "\"type\":\"error\"")
  |> should.be_true()

  string.contains(json_string, "\"message\":\"Lobby not found\"")
  |> should.be_true()
}

pub fn decode_create_game_message_test() {
  let data =
    dynamic.properties([
      #(dynamic.string("type"), dynamic.string("create_game")),
      #(dynamic.string("user_id"), dynamic.string("user_1")),
      #(dynamic.string("nickname"), dynamic.string("Alice")),
    ])

  let assert Ok(msg) = decoders.decode_client_message(data)

  let assert CreateGame(user_id, nickname) = msg
  user_id
  |> should.equal("user_1")
  nickname
  |> should.equal("Alice")
}

pub fn decode_join_game_message_test() {
  let data =
    dynamic.properties([
      #(dynamic.string("type"), dynamic.string("join_game")),
      #(dynamic.string("code"), dynamic.string("ABC123")),
      #(dynamic.string("user_id"), dynamic.string("user_2")),
      #(dynamic.string("nickname"), dynamic.string("Bob")),
    ])

  let assert Ok(msg) = decoders.decode_client_message(data)

  let assert JoinGame(code, user_id, nickname) = msg
  code
  |> should.equal("ABC123")
  user_id
  |> should.equal("user_2")
  nickname
  |> should.equal("Bob")
}

pub fn decode_toggle_ready_message_test() {
  let data =
    dynamic.properties([
      #(dynamic.string("type"), dynamic.string("toggle_ready")),
    ])

  let assert Ok(msg) = decoders.decode_client_message(data)

  let assert ToggleReady = msg
}

pub fn decode_start_game_message_test() {
  let data =
    dynamic.properties([#(dynamic.string("type"), dynamic.string("start_game"))])

  let assert Ok(msg) = decoders.decode_client_message(data)

  let assert StartGame = msg
}

pub fn decode_unknown_message_type_returns_error_test() {
  let data =
    dynamic.properties([
      #(dynamic.string("type"), dynamic.string("unknown_message")),
    ])

  let result = decoders.decode_client_message(data)

  result
  |> should.be_error()
}

pub fn decode_message_missing_fields_returns_error_test() {
  let data =
    dynamic.properties([
      #(dynamic.string("type"), dynamic.string("create_game")),
    ])

  let result = decoders.decode_client_message(data)

  result
  |> should.be_error()
}

pub fn decode_message_missing_type_field_returns_error_test() {
  let data =
    dynamic.properties([#(dynamic.string("nickname"), dynamic.string("Alice"))])

  let result = decoders.decode_client_message(data)

  result
  |> should.be_error()
}

pub fn encode_phase_strike_test() {
  let encoded = encoders.encode_phase(Strike)
  let json_string = json.to_string(encoded)

  json_string |> should.equal("\"strike\"")
}

pub fn decode_phase_strike_test() {
  let result = decoders.decode_phase("strike")
  result |> should.equal(Ok(Strike))
}

pub fn decode_initiate_strike_vote_test() {
  let data =
    dynamic.properties([
      #(dynamic.string("type"), dynamic.string("initiate_strike_vote")),
    ])

  let assert Ok(msg) = decoders.decode_client_message(data)
  let assert InitiateStrikeVote = msg
}

pub fn decode_cast_strike_vote_test() {
  let data =
    dynamic.properties([
      #(dynamic.string("type"), dynamic.string("cast_strike_vote")),
      #(dynamic.string("approve"), dynamic.bool(True)),
    ])

  let assert Ok(msg) = decoders.decode_client_message(data)
  let assert CastStrikeVote(approve) = msg
  approve |> should.be_true()
}

pub fn decode_cast_strike_vote_reject_test() {
  let data =
    dynamic.properties([
      #(dynamic.string("type"), dynamic.string("cast_strike_vote")),
      #(dynamic.string("approve"), dynamic.bool(False)),
    ])

  let assert Ok(msg) = decoders.decode_client_message(data)
  let assert CastStrikeVote(approve) = msg
  approve |> should.be_false()
}

pub fn encode_strike_vote_update_test() {
  let msg =
    StrikeVoteUpdate(
      votes: [#("user_1", True)],
      pending: ["user_2"],
      seconds_remaining: 8,
    )

  let encoded = encoders.encode_server_message(msg)
  let json_string = json.to_string(encoded)

  string.contains(json_string, "\"type\":\"strike_vote_update\"")
  |> should.be_true()

  string.contains(json_string, "\"seconds_remaining\":8")
  |> should.be_true()

  string.contains(json_string, "\"user_1\"")
  |> should.be_true()

  string.contains(json_string, "\"user_2\"")
  |> should.be_true()
}

// Game Log Tests

pub fn timestamp_to_unix_ms_roundtrip_test() {
  // Create a timestamp from known values
  let ts =
    timestamp.from_unix_seconds_and_nanoseconds(1_712_345_678, 901_000_000)
  let ms = helpers.timestamp_to_unix_ms(ts)

  // Verify milliseconds
  ms |> should.equal(1_712_345_678_901)

  // Roundtrip back to timestamp
  let ts2 = helpers.unix_ms_to_timestamp(ms)
  let ms2 = helpers.timestamp_to_unix_ms(ts2)
  ms2 |> should.equal(ms)
}

pub fn encode_game_event_round_started_test() {
  let ts = timestamp.from_unix_seconds_and_nanoseconds(1000, 0)
  let event = GameEvent(ts, RoundStarted(3))

  let encoded = encoders.encode_game_event(event)
  let json_string = json.to_string(encoded)

  string.contains(json_string, "\"event_type\":\"round_started\"")
  |> should.be_true()

  string.contains(json_string, "\"round\":3")
  |> should.be_true()

  string.contains(json_string, "\"timestamp\":1000000")
  |> should.be_true()
}

pub fn encode_game_event_card_played_test() {
  let ts = timestamp.from_unix_seconds_and_nanoseconds(1000, 500_000_000)
  let event = GameEvent(ts, CardPlayed("Alice", 42, False))

  let encoded = encoders.encode_game_event(event)
  let json_string = json.to_string(encoded)

  string.contains(json_string, "\"event_type\":\"card_played\"")
  |> should.be_true()

  string.contains(json_string, "\"player_nickname\":\"Alice\"")
  |> should.be_true()

  string.contains(json_string, "\"card\":42")
  |> should.be_true()
}

pub fn encode_game_event_mistake_discard_test() {
  let ts = timestamp.from_unix_seconds_and_nanoseconds(2000, 0)
  let event = GameEvent(ts, MistakeDiscard("Bob", 15))

  let encoded = encoders.encode_game_event(event)
  let json_string = json.to_string(encoded)

  string.contains(json_string, "\"event_type\":\"mistake_discard\"")
  |> should.be_true()

  string.contains(json_string, "\"player_nickname\":\"Bob\"")
  |> should.be_true()

  string.contains(json_string, "\"card\":15")
  |> should.be_true()
}

pub fn encode_game_event_strike_discard_test() {
  let ts = timestamp.from_unix_seconds_and_nanoseconds(3000, 0)
  let event = GameEvent(ts, StrikeDiscard("Carol", 7))

  let encoded = encoders.encode_game_event(event)
  let json_string = json.to_string(encoded)

  string.contains(json_string, "\"event_type\":\"strike_discard\"")
  |> should.be_true()

  string.contains(json_string, "\"player_nickname\":\"Carol\"")
  |> should.be_true()
}

pub fn encode_game_event_life_lost_test() {
  let ts = timestamp.from_unix_seconds_and_nanoseconds(4000, 0)
  let event = GameEvent(ts, LifeLost(2))

  let encoded = encoders.encode_game_event(event)
  let json_string = json.to_string(encoded)

  string.contains(json_string, "\"event_type\":\"life_lost\"")
  |> should.be_true()

  string.contains(json_string, "\"lives_remaining\":2")
  |> should.be_true()
}

pub fn decode_game_event_round_started_test() {
  let ts = timestamp.from_unix_seconds_and_nanoseconds(5000, 0)
  let original = GameEvent(ts, RoundStarted(5))

  // Encode then decode
  let encoded = encoders.encode_game_event(original)
  let json_string = json.to_string(encoded)
  let assert Ok(dynamic_data) = json.parse(json_string, decode.dynamic)
  let assert Ok(decoded) =
    decode.run(dynamic_data, decoders.game_event_decoder())

  // Verify the event type
  case decoded.event_type {
    RoundStarted(round) -> round |> should.equal(5)
    _ -> should.fail()
  }
}

pub fn decode_game_event_card_played_test() {
  let ts = timestamp.from_unix_seconds_and_nanoseconds(6000, 0)
  let original = GameEvent(ts, CardPlayed("Dave", 99, False))

  // Encode then decode
  let encoded = encoders.encode_game_event(original)
  let json_string = json.to_string(encoded)
  let assert Ok(dynamic_data) = json.parse(json_string, decode.dynamic)
  let assert Ok(decoded) =
    decode.run(dynamic_data, decoders.game_event_decoder())

  // Verify the event type
  case decoded.event_type {
    CardPlayed(nick, card, autoplayed) -> {
      nick |> should.equal("Dave")
      card |> should.equal(99)
      autoplayed |> should.equal(False)
    }
    _ -> should.fail()
  }
}

pub fn encode_game_log_event_message_test() {
  let ts = timestamp.from_unix_seconds_and_nanoseconds(7000, 0)
  let event = GameEvent(ts, RoundStarted(1))
  let msg = GameLogEvent(event)

  let encoded = encoders.encode_server_message(msg)
  let json_string = json.to_string(encoded)

  string.contains(json_string, "\"type\":\"game_log_event\"")
  |> should.be_true()

  string.contains(json_string, "\"event\":")
  |> should.be_true()
}

pub fn encode_game_event_strike_used_test() {
  let ts = timestamp.from_unix_seconds_and_nanoseconds(5000, 0)
  let event = GameEvent(ts, StrikeUsed(2))

  let encoded = encoders.encode_game_event(event)
  let json_string = json.to_string(encoded)

  string.contains(json_string, "\"event_type\":\"strike_used\"")
  |> should.be_true()

  string.contains(json_string, "\"strikes_remaining\":2")
  |> should.be_true()
}

pub fn decode_game_event_strike_used_test() {
  let ts = timestamp.from_unix_seconds_and_nanoseconds(5000, 0)
  let original = GameEvent(ts, StrikeUsed(1))

  // Encode then decode
  let encoded = encoders.encode_game_event(original)
  let json_string = json.to_string(encoded)
  let assert Ok(dynamic_data) = json.parse(json_string, decode.dynamic)
  let assert Ok(decoded) =
    decode.run(dynamic_data, decoders.game_event_decoder())

  // Verify the event type
  case decoded.event_type {
    StrikeUsed(remaining) -> remaining |> should.equal(1)
    _ -> should.fail()
  }
}
