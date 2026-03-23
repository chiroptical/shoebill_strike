import client/effects
import client/model.{type Model, GameScreen, HomeScreen, LobbyScreen, Model}
import client/msg.{type Msg}
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{None, Some}
import lustre/effect
import protocol/types as protocol

pub fn handle_server_msg(
  model: Model,
  msg: protocol.ServerMessage,
) -> #(Model, effect.Effect(Msg)) {
  case msg {
    protocol.GameCreated(code) -> {
      io.println("[Client] Game created: " <> code)
      #(model, effect.none())
    }

    protocol.GameJoined -> {
      io.println("[Client] Game joined")
      #(model, effect.none())
    }

    protocol.LobbyState(lobby) -> {
      io.println(
        "[Client] Lobby state received. Players: "
        <> int.to_string(list.length(lobby.players)),
      )

      // Save to localStorage
      case list.find(lobby.players, fn(p) { p.user_id == model.user_id }) {
        Ok(my_player) -> {
          effects.save_game_to_storage(
            lobby.code,
            model.user_id,
            my_player.nickname,
          )
          Nil
        }
        Error(_) -> Nil
      }

      #(
        Model(..model, current_lobby: Some(lobby), screen: LobbyScreen),
        effect.none(),
      )
    }

    protocol.GameStarted -> {
      io.println("[Client] Game started")
      #(Model(..model, screen: GameScreen), effects.clear_saved_game_effect())
    }

    protocol.ServerError(message) -> {
      io.println("[Client] Server error: " <> message)
      case message {
        "Lobby not found" -> #(
          Model(..model, screen: HomeScreen, error: Some(message)),
          effects.clear_saved_game_effect(),
        )
        _ -> #(Model(..model, error: Some(message)), effect.none())
      }
    }

    protocol.GameStateUpdate(game) -> {
      io.println(
        "[Client] Game state update received. Players: "
        <> int.to_string(list.length(game.players)),
      )
      #(
        Model(..model, current_game: Some(game), screen: GameScreen),
        effect.none(),
      )
    }

    protocol.CountdownTick(seconds) -> {
      io.println(
        "[Client] Countdown tick: "
        <> int.to_string(seconds)
        <> ", current phase: "
        <> case model.current_game {
          Some(g) -> phase_to_string(g.phase)
          None -> "no game"
        },
      )
      #(Model(..model, countdown: Some(seconds)), effect.none())
    }

    protocol.PhaseTransition(phase) -> {
      io.println("[Client] Phase transition to: " <> phase_to_string(phase))
      // Update the game phase and clear countdown
      let updated_game = case model.current_game {
        Some(g) -> Some(protocol.Game(..g, phase: phase))
        None -> None
      }
      case phase {
        protocol.ActivePlay -> #(
          Model(
            ..model,
            countdown: None,
            current_game: updated_game,
            vote_status: None,
            abandon_vote_status: None,
          ),
          effect.none(),
        )
        protocol.Dealing -> #(
          Model(
            ..model,
            current_game: updated_game,
            vote_status: None,
            abandon_vote_status: None,
          ),
          effect.none(),
        )
        protocol.Pause -> #(
          Model(
            ..model,
            current_game: updated_game,
            vote_status: None,
            abandon_vote_status: None,
          ),
          effect.none(),
        )
        _ -> #(Model(..model, current_game: updated_game), effect.none())
      }
    }

    protocol.StrikeVoteUpdate(votes, pending, seconds_remaining) -> {
      io.println(
        "[Client] Strike vote update: "
        <> int.to_string(list.length(votes))
        <> " votes, "
        <> int.to_string(list.length(pending))
        <> " pending, "
        <> int.to_string(seconds_remaining)
        <> "s remaining",
      )
      #(
        Model(..model, vote_status: Some(#(votes, pending, seconds_remaining))),
        effect.none(),
      )
    }

    protocol.AbandonVoteUpdate(votes, pending, seconds_remaining) -> {
      io.println(
        "[Client] Abandon vote update: "
        <> int.to_string(list.length(votes))
        <> " votes, "
        <> int.to_string(list.length(pending))
        <> " pending, "
        <> int.to_string(seconds_remaining)
        <> "s remaining",
      )
      #(
        Model(
          ..model,
          abandon_vote_status: Some(#(votes, pending, seconds_remaining)),
        ),
        effect.none(),
      )
    }

    protocol.PlayerLeft(left_user_id, _new_host_user_id) -> {
      io.println("[Client] Player left: " <> left_user_id)
      #(model, effect.none())
    }

    protocol.YouLeft -> {
      io.println("[Client] You left the game")
      #(
        Model(
          ..model,
          screen: HomeScreen,
          current_game: None,
          current_lobby: None,
        ),
        effects.clear_saved_game_effect(),
      )
    }

    protocol.GameLogEvent(event) -> {
      io.println("[Client] Game log event received")
      // Append event to the game's log
      let updated_game = case model.current_game {
        Some(g) -> Some(protocol.Game(..g, game_log: [event, ..g.game_log]))
        None -> None
      }
      #(Model(..model, current_game: updated_game), effect.none())
    }

    protocol.PlayerDisconnected(user_id) -> {
      io.println("[Client] Player disconnected: " <> user_id)
      let updated_lobby = case model.current_lobby {
        Some(lobby) ->
          Some(update_player_connection_in_lobby(lobby, user_id, False))
        None -> None
      }
      let updated_game = case model.current_game {
        Some(game) ->
          Some(update_player_connection_in_game(game, user_id, False))
        None -> None
      }
      #(
        Model(..model, current_lobby: updated_lobby, current_game: updated_game),
        effect.none(),
      )
    }

    protocol.PlayerReconnected(user_id) -> {
      io.println("[Client] Player reconnected: " <> user_id)
      let updated_lobby = case model.current_lobby {
        Some(lobby) ->
          Some(update_player_connection_in_lobby(lobby, user_id, True))
        None -> None
      }
      let updated_game = case model.current_game {
        Some(game) ->
          Some(update_player_connection_in_game(game, user_id, True))
        None -> None
      }
      #(
        Model(..model, current_lobby: updated_lobby, current_game: updated_game),
        effect.none(),
      )
    }
  }
}

/// Update a player's connection status in a lobby
pub fn update_player_connection_in_lobby(
  lobby: protocol.Lobby,
  user_id: String,
  is_connected: Bool,
) -> protocol.Lobby {
  let updated_players =
    list.map(lobby.players, fn(p) {
      case p.user_id == user_id {
        True -> protocol.Player(..p, is_connected: is_connected)
        False -> p
      }
    })
  protocol.Lobby(..lobby, players: updated_players)
}

/// Update a player's connection status in a game
pub fn update_player_connection_in_game(
  game: protocol.Game,
  user_id: String,
  is_connected: Bool,
) -> protocol.Game {
  let updated_players =
    list.map(game.players, fn(p) {
      case p.user_id == user_id {
        True -> protocol.GamePlayer(..p, is_connected: is_connected)
        False -> p
      }
    })
  protocol.Game(..game, players: updated_players)
}

pub fn phase_to_string(phase: protocol.Phase) -> String {
  case phase {
    protocol.Dealing -> "Dealing"
    protocol.ActivePlay -> "Active Play"
    protocol.Pause -> "Pause"
    protocol.Strike -> "Strike"
    protocol.AbandonVote -> "Abandon Vote"
    protocol.EndGame(_) -> "End Game"
  }
}
