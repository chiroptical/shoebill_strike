import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/option.{type Option}
import protocol/types.{
  type ClientMessage, type Game, type Lobby, type ServerMessage,
}

/// Connection info for a WebSocket client
pub type ConnectionInfo {
  ConnectionInfo(
    subject: Subject(ServerMessage),
    user_id: String,
    lobby_code: Option(String),
    game_code: Option(String),
  )
}

/// Countdown timer state
pub type CountdownTimer {
  CountdownTimer(game_code: String, seconds_remaining: Int)
}

/// Vote state for strike votes
pub type VoteState {
  VoteState(game_code: String, votes: Dict(String, Bool), pending: List(String))
}

/// Server state managing all lobbies, games, and connections
pub type ServerState {
  ServerState(
    lobbies: Dict(String, Lobby),
    games: Dict(String, Game),
    connections: Dict(String, ConnectionInfo),
    countdown_timers: Dict(String, CountdownTimer),
    vote_states: Dict(String, VoteState),
    vote_timers: Dict(String, Int),
    self_subject: Option(Subject(ServerMsg)),
  )
}

/// Messages sent to the server actor
pub type ServerMsg {
  ClientConnected(subject: Subject(ServerMessage), user_id: String)
  ClientDisconnected(user_id: String)
  ClientMsg(user_id: String, message: ClientMessage)
  CountdownTickMsg(game_code: String, seconds_remaining: Int)
  VoteTickMsg(game_code: String, seconds_remaining: Int)
  AbandonVoteTickMsg(game_code: String, seconds_remaining: Int)
  SetSelfSubject(subject: Subject(ServerMsg))
}
