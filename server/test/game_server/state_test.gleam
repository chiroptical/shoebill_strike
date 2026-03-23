import game_server/state.{CountdownTimer, ServerState, VoteState}
import gleam/dict
import gleam/option.{None}
import gleeunit/should

pub fn countdown_timer_construction_test() {
  let timer = CountdownTimer(game_code: "GAME123", seconds_remaining: 3)

  timer.game_code |> should.equal("GAME123")
  timer.seconds_remaining |> should.equal(3)
}

pub fn vote_state_construction_test() {
  let votes = dict.from_list([#("user_1", True), #("user_2", False)])
  let pending = ["user_3", "user_4"]
  let vote_state =
    VoteState(game_code: "GAME456", votes: votes, pending: pending)

  vote_state.game_code |> should.equal("GAME456")
  dict.get(vote_state.votes, "user_1") |> should.equal(Ok(True))
  dict.get(vote_state.votes, "user_2") |> should.equal(Ok(False))
  vote_state.pending |> should.equal(["user_3", "user_4"])
}

pub fn vote_state_empty_votes_test() {
  let vote_state =
    VoteState(game_code: "GAME789", votes: dict.new(), pending: ["user_1"])

  dict.size(vote_state.votes) |> should.equal(0)
  vote_state.pending |> should.equal(["user_1"])
}

pub fn server_state_empty_construction_test() {
  let state =
    ServerState(
      lobbies: dict.new(),
      games: dict.new(),
      connections: dict.new(),
      countdown_timers: dict.new(),
      vote_states: dict.new(),
      vote_timers: dict.new(),
      self_subject: None,
    )

  dict.size(state.lobbies) |> should.equal(0)
  dict.size(state.games) |> should.equal(0)
  dict.size(state.connections) |> should.equal(0)
  dict.size(state.countdown_timers) |> should.equal(0)
  dict.size(state.vote_states) |> should.equal(0)
  dict.size(state.vote_timers) |> should.equal(0)
  state.self_subject |> should.equal(None)
}

pub fn server_msg_countdown_tick_construction_test() {
  let state.CountdownTickMsg(code, seconds) =
    state.CountdownTickMsg(game_code: "GAME001", seconds_remaining: 2)

  code |> should.equal("GAME001")
  seconds |> should.equal(2)
}

pub fn server_msg_vote_tick_construction_test() {
  let state.VoteTickMsg(code, seconds) =
    state.VoteTickMsg(game_code: "GAME002", seconds_remaining: 8)

  code |> should.equal("GAME002")
  seconds |> should.equal(8)
}

pub fn server_msg_abandon_vote_tick_construction_test() {
  let state.AbandonVoteTickMsg(code, seconds) =
    state.AbandonVoteTickMsg(game_code: "GAME003", seconds_remaining: 5)

  code |> should.equal("GAME003")
  seconds |> should.equal(5)
}

pub fn server_msg_client_disconnected_construction_test() {
  let state.ClientDisconnected(uid) =
    state.ClientDisconnected(user_id: "user_abc")

  uid |> should.equal("user_abc")
}
