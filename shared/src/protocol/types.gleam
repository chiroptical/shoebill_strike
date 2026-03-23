import gleam/option.{type Option}
import gleam/time/timestamp.{type Timestamp}

/// Player representation in the lobby
pub type Player {
  Player(
    user_id: String,
    nickname: String,
    is_ready: Bool,
    is_creator: Bool,
    is_connected: Bool,
  )
}

/// Lobby state
pub type Lobby {
  Lobby(code: String, players: List(Player), games_played: Int)
}

/// Card type (1-100)
pub type Card =
  Int

/// Game outcome for end game phase
pub type GameOutcome {
  Win
  Loss
  Abandoned
}

/// Game phase
pub type Phase {
  Dealing
  ActivePlay
  Pause
  Strike
  AbandonVote
  EndGame(GameOutcome)
}

/// Player representation in an active game
pub type GamePlayer {
  GamePlayer(
    user_id: String,
    nickname: String,
    hand: List(Card),
    is_ready: Bool,
    is_connected: Bool,
    last_card_played: Option(Int),
  )
}

/// Information about a mistake that occurred during play
pub type MistakeInfo {
  MistakeInfo(
    player_nickname: String,
    played_card: Card,
    mistake_cards: List(#(String, Card)),
  )
}

/// Game event types for the game log
pub type GameEventType {
  RoundStarted(round: Int)
  CardPlayed(player_nickname: String, card: Int, autoplayed: Bool)
  MistakeDiscard(player_nickname: String, card: Int)
  StrikeDiscard(player_nickname: String, card: Int)
  LifeLost(lives_remaining: Int)
  StrikeUsed(strikes_remaining: Int)
  PlayerDisconnectedEvent(nickname: String)
  PlayerReconnectedEvent(nickname: String)
}

/// A game event with timestamp
pub type GameEvent {
  GameEvent(timestamp: Timestamp, event_type: GameEventType)
}

/// Active game state
pub type Game {
  Game(
    code: String,
    host_user_id: String,
    games_played: Int,
    players: List(GamePlayer),
    current_round: Int,
    total_rounds: Int,
    lives: Int,
    strikes: Int,
    phase: Phase,
    played_cards: List(Card),
    last_mistake: Option(MistakeInfo),
    abandon_vote_previous_phase: Option(Phase),
    game_start_timestamp: Timestamp,
    game_log: List(GameEvent),
  )
}

/// Messages from client to server
pub type ClientMessage {
  CreateGame(user_id: String, nickname: String)
  JoinGame(code: String, user_id: String, nickname: String)
  ToggleReady
  StartGame
  ToggleReadyInGame
  PlayCard
  InitiateStrikeVote
  CastStrikeVote(approve: Bool)
  InitiateAbandonVote
  CastAbandonVote(approve: Bool)
  LeaveGame
  RestartGame
}

/// Messages from server to client
pub type ServerMessage {
  GameCreated(code: String)
  GameJoined
  LobbyState(lobby: Lobby)
  GameStarted
  ServerError(message: String)
  GameStateUpdate(game: Game)
  CountdownTick(seconds: Int)
  PhaseTransition(phase: Phase)
  StrikeVoteUpdate(
    votes: List(#(String, Bool)),
    pending: List(String),
    seconds_remaining: Int,
  )
  AbandonVoteUpdate(
    votes: List(#(String, Bool)),
    pending: List(String),
    seconds_remaining: Int,
  )
  PlayerLeft(user_id: String, new_host_user_id: Option(String))
  YouLeft
  GameLogEvent(event: GameEvent)
  PlayerDisconnected(user_id: String)
  PlayerReconnected(user_id: String)
}
