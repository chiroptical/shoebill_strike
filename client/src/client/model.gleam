import gleam/option.{type Option}
import mock_routes/types.{type Route}
import protocol/types as protocol

pub type Screen {
  HomeScreen
  CreateScreen
  JoinScreen
  LobbyScreen
  GameScreen
}

pub type ToastState {
  ToastHidden
  ToastShowing(String)
  ToastHiding(String)
}

pub type Model {
  Model(
    route: Route,
    screen: Screen,
    user_id: String,
    current_lobby: Option(protocol.Lobby),
    current_game: Option(protocol.Game),
    countdown: Option(Int),
    create_nickname: String,
    join_code: String,
    join_nickname: String,
    error: Option(String),
    vote_status: Option(#(List(#(String, Bool)), List(String), Int)),
    abandon_vote_status: Option(#(List(#(String, Bool)), List(String), Int)),
    toast: ToastState,
    is_reward_guide_open: Bool,
  )
}
