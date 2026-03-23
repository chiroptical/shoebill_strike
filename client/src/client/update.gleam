import client/effects
import client/init
import client/model.{
  type Model, CreateScreen, HomeScreen, JoinScreen, Model, ToastHidden,
  ToastHiding, ToastShowing,
}
import client/msg.{
  type Msg, CastAbandonVoteClicked, CastStrikeVoteClicked, CopyShareCode,
  CopyShareLink, CreateGameClicked, InitiateAbandonVoteClicked,
  InitiateStrikeClicked, JoinGameClicked, LeaveGameClicked, NoOp, OnRouteChange,
  PlayCardClicked, RestartGameClicked, ServerMessage, ShowCreateGame, ShowHome,
  ShowJoinGame, StartGameClicked, ToastHideComplete, ToastStartHide,
  ToggleReadyClicked, ToggleReadyInGameClicked, ToggleRewardGuide,
  UpdateCreateNickname, UpdateJoinCode, UpdateJoinNickname,
}
import client/server_messages
import gleam/io
import gleam/json
import gleam/option.{None, Some}
import lustre/effect
import mock_routes/builders/common as builders_common
import mock_routes/parsing
import mock_routes/types.{AppRoute}

pub fn update(model: Model, msg: Msg) -> #(Model, effect.Effect(Msg)) {
  case msg {
    ServerMessage(server_msg) ->
      server_messages.handle_server_msg(model, server_msg)

    OnRouteChange(new_uri) -> {
      let new_route = parsing.parse_route(new_uri)
      io.println(
        "[Client] Route changed to: "
        <> case new_route {
          AppRoute -> "AppRoute"
          _ -> "MockRoute"
        },
      )

      let #(
        new_lobby,
        new_game,
        new_screen,
        new_countdown,
        new_vote_status,
        new_abandon_vote_status,
      ) = init.build_initial_state_from_route(new_route)

      let new_user_id = case new_route {
        AppRoute -> effects.get_or_create_user_id()
        _ -> builders_common.get_mock_user_id()
      }

      // Connect WebSocket when transitioning to AppRoute
      let eff = case model.route, new_route {
        _, AppRoute ->
          effect.from(fn(dispatch) {
            effects.connect_websocket(dispatch)
            effects.check_saved_game(dispatch)
          })
        _, _ -> effect.none()
      }

      #(
        Model(
          ..model,
          route: new_route,
          screen: new_screen,
          user_id: new_user_id,
          current_lobby: new_lobby,
          current_game: new_game,
          countdown: new_countdown,
          vote_status: new_vote_status,
          abandon_vote_status: new_abandon_vote_status,
          error: None,
        ),
        eff,
      )
    }

    ShowCreateGame -> #(
      Model(..model, screen: CreateScreen, error: None),
      effect.none(),
    )

    ShowJoinGame -> #(
      Model(..model, screen: JoinScreen, error: None),
      effect.none(),
    )

    ShowHome -> #(
      Model(..model, screen: HomeScreen, error: None),
      effects.clear_saved_game_effect(),
    )

    UpdateCreateNickname(nickname) -> #(
      Model(..model, create_nickname: nickname),
      effect.none(),
    )

    UpdateJoinCode(code) -> #(Model(..model, join_code: code), effect.none())

    UpdateJoinNickname(nickname) -> #(
      Model(..model, join_nickname: nickname),
      effect.none(),
    )

    CreateGameClicked -> {
      case model.create_nickname {
        "" -> #(
          Model(..model, error: Some("Please enter a nickname")),
          effect.none(),
        )
        nickname -> {
          effects.send_message(
            json.object([
              #("type", json.string("create_game")),
              #("user_id", json.string(model.user_id)),
              #("nickname", json.string(nickname)),
            ]),
          )
          #(Model(..model, error: None), effect.none())
        }
      }
    }

    JoinGameClicked -> {
      case model.join_code, model.join_nickname {
        "", _ | _, "" -> #(
          Model(..model, error: Some("Please enter both code and nickname")),
          effect.none(),
        )
        code, nickname -> {
          effects.send_message(
            json.object([
              #("type", json.string("join_game")),
              #("code", json.string(code)),
              #("user_id", json.string(model.user_id)),
              #("nickname", json.string(nickname)),
            ]),
          )
          #(Model(..model, error: None), effect.none())
        }
      }
    }

    ToggleReadyClicked -> {
      effects.send_message(
        json.object([#("type", json.string("toggle_ready"))]),
      )
      #(model, effect.none())
    }

    StartGameClicked -> {
      effects.send_message(json.object([#("type", json.string("start_game"))]))
      #(model, effect.none())
    }

    ToggleReadyInGameClicked -> {
      io.println("[Client] ToggleReadyInGameClicked")
      effects.send_message(
        json.object([#("type", json.string("toggle_ready_in_game"))]),
      )
      #(model, effect.none())
    }

    PlayCardClicked -> {
      io.println("[Client] PlayCardClicked")
      effects.send_message(json.object([#("type", json.string("play_card"))]))
      #(model, effect.none())
    }

    InitiateStrikeClicked -> {
      effects.send_message(
        json.object([#("type", json.string("initiate_strike_vote"))]),
      )
      #(model, effect.none())
    }

    CastStrikeVoteClicked(approve) -> {
      effects.send_message(
        json.object([
          #("type", json.string("cast_strike_vote")),
          #("approve", json.bool(approve)),
        ]),
      )
      #(model, effect.none())
    }

    InitiateAbandonVoteClicked -> {
      effects.send_message(
        json.object([#("type", json.string("initiate_abandon_vote"))]),
      )
      #(model, effect.none())
    }

    CastAbandonVoteClicked(approve) -> {
      effects.send_message(
        json.object([
          #("type", json.string("cast_abandon_vote")),
          #("approve", json.bool(approve)),
        ]),
      )
      #(model, effect.none())
    }

    CopyShareCode(code) -> {
      effects.copy_to_clipboard(code)
      #(
        Model(..model, toast: ToastShowing("Code copied to clipboard")),
        effect.from(fn(dispatch) {
          effects.dispatch_after_ms(dispatch, ToastStartHide, 2000)
        }),
      )
    }

    CopyShareLink(url) -> {
      effects.copy_to_clipboard(url)
      #(
        Model(..model, toast: ToastShowing("Link copied to clipboard")),
        effect.from(fn(dispatch) {
          effects.dispatch_after_ms(dispatch, ToastStartHide, 2000)
        }),
      )
    }

    ToastStartHide -> {
      case model.toast {
        ToastShowing(toast_msg) -> #(
          Model(..model, toast: ToastHiding(toast_msg)),
          effect.from(fn(dispatch) {
            effects.dispatch_after_ms(dispatch, ToastHideComplete, 400)
          }),
        )
        _ -> #(model, effect.none())
      }
    }

    ToastHideComplete -> {
      #(Model(..model, toast: ToastHidden), effect.none())
    }

    LeaveGameClicked -> {
      effects.send_message(json.object([#("type", json.string("leave_game"))]))
      #(model, effect.none())
    }

    RestartGameClicked -> {
      effects.send_message(
        json.object([#("type", json.string("restart_game"))]),
      )
      #(model, effect.none())
    }

    ToggleRewardGuide -> {
      #(
        Model(..model, is_reward_guide_open: !model.is_reward_guide_open),
        effect.none(),
      )
    }

    NoOp -> #(model, effect.none())
  }
}
