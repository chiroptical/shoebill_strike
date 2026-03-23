import gleam/uri.{type Uri}
import protocol/types as protocol

pub type Msg {
  ServerMessage(protocol.ServerMessage)
  OnRouteChange(Uri)
  ShowCreateGame
  ShowJoinGame
  ShowHome
  UpdateCreateNickname(String)
  UpdateJoinCode(String)
  UpdateJoinNickname(String)
  CreateGameClicked
  JoinGameClicked
  ToggleReadyClicked
  StartGameClicked
  ToggleReadyInGameClicked
  PlayCardClicked
  InitiateStrikeClicked
  CastStrikeVoteClicked(Bool)
  InitiateAbandonVoteClicked
  CastAbandonVoteClicked(Bool)
  CopyShareCode(String)
  CopyShareLink(String)
  ToastStartHide
  ToastHideComplete
  LeaveGameClicked
  RestartGameClicked
  ToggleRewardGuide
  NoOp
}

/// Helper function for FFI to create ServerMessage variant
pub fn server_message(msg: protocol.ServerMessage) -> Msg {
  ServerMessage(msg)
}
