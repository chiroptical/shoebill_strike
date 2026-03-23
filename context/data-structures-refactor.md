# Data Structures Refactor Plan

This document tracks proposed changes from Task 6 (Evaluate Server Data Structures) in game-rules.md.

---

## Example 1: Convert `players` from List to Dict

### Summary

Change `Lobby.players: List(Player)` to `Dict(String, Player)` and
`Game.players: List(GamePlayer)` to `Dict(String, GamePlayer)`, keyed by
`user_id`.

**Rationale:** Eliminates O(n) lookups by user_id. With max 4 players the
performance difference is negligible, but the code becomes cleaner with
`dict.get`/`dict.insert` instead of `list.find`/`list.map` patterns.

**Wire format:** Changed to JSON objects keyed by user_id. This is a breaking change.

---

### Files to Modify

#### 1. shared/src/protocol.gleam

**Imports:**
- Add `import gleam/dict.{type Dict}`

**Type changes:**
```gleam
// Before
pub type Lobby {
  Lobby(code: String, players: List(Player), games_played: Int)
}

// After
pub type Lobby {
  Lobby(code: String, players: Dict(String, Player), games_played: Int)
}
```

```gleam
// Before
pub type Game {
  Game(
    ...
    players: List(GamePlayer),
    ...
  )
}

// After
pub type Game {
  Game(
    ...
    players: Dict(String, GamePlayer),
    ...
  )
}
```

**Encoder changes:**

```gleam
// encode_lobby - Before
#("players", json.array(lobby.players, encode_player))

// encode_lobby - After
#("players", encode_player_dict(lobby.players))

// New helper function
fn encode_player_dict(players: Dict(String, Player)) -> json.Json {
  players
  |> dict.to_list
  |> list.map(fn(pair) { #(pair.0, encode_player(pair.1)) })
  |> json.object
}
```

```gleam
// encode_game - Before
#("players", json.array(game.players, encode_game_player))

// encode_game - After
#("players", encode_game_player_dict(game.players))

// New helper function
fn encode_game_player_dict(players: Dict(String, GamePlayer)) -> json.Json {
  players
  |> dict.to_list
  |> list.map(fn(pair) { #(pair.0, encode_game_player(pair.1)) })
  |> json.object
}
```

**Decoder changes:**

```gleam
// Player decoder - takes user_id as parameter since it comes from the object key
fn player_decoder_with_id(user_id: String) -> decode.Decoder(Player) {
  use nickname <- decode.field("nickname", decode.string)
  use is_ready <- decode.field("is_ready", decode.bool)
  use is_creator <- decode.field("is_creator", decode.bool)
  decode.success(Player(user_id, nickname, is_ready, is_creator))
}

// Decode a Dict(String, Player) from a JSON object
fn player_dict_decoder() -> decode.Decoder(Dict(String, Player)) {
  decode.dict(decode.string, fn(user_id) { player_decoder_with_id(user_id) })
}

// GamePlayer decoder - takes user_id as parameter
fn game_player_decoder_with_id(user_id: String) -> decode.Decoder(GamePlayer) {
  use nickname <- decode.field("nickname", decode.string)
  use hand <- decode.field("hand", decode.list(decode.int))
  use is_ready <- decode.field("is_ready", decode.bool)
  decode.success(GamePlayer(user_id, nickname, hand, is_ready))
}

// Decode a Dict(String, GamePlayer) from a JSON object
fn game_player_dict_decoder() -> decode.Decoder(Dict(String, GamePlayer)) {
  decode.dict(decode.string, fn(user_id) { game_player_decoder_with_id(user_id) })
}

// lobby_decoder
pub fn lobby_decoder() -> decode.Decoder(Lobby) {
  use code <- decode.field("code", decode.string)
  use players <- decode.field("players", player_dict_decoder())
  use games_played <- decode.field("games_played", decode.int)
  decode.success(Lobby(code, players, games_played))
}
```

```gleam
// game_decoder - Before
use players <- decode.field("players", decode.list(game_player_decoder()))
...
decode.success(Game(
  ...
  players,
  ...
))

// game_decoder - After
use players <- decode.field("players", game_player_dict_decoder())
...
decode.success(Game(
  ...
  players,
  ...
))
```

**Note:** The `user_id` field is no longer needed in the JSON payload for each player since it's the object key. The encoders should be updated to omit `user_id` from the player object body.

**Helper function changes:**

```gleam
// get_player_hand - Before
pub fn get_player_hand(game: Game, user_id: String) -> List(Card) {
  game.players
  |> list.find(fn(p) { p.user_id == user_id })
  |> fn(result) {
    case result {
      Ok(player) -> player.hand
      Error(_) -> []
    }
  }
}

// get_player_hand - After
pub fn get_player_hand(game: Game, user_id: String) -> List(Card) {
  case dict.get(game.players, user_id) {
    Ok(player) -> player.hand
    Error(_) -> []
  }
}
```

```gleam
// is_player_ready_in_game - Before
pub fn is_player_ready_in_game(game: Game, user_id: String) -> Bool {
  game.players
  |> list.find(fn(p) { p.user_id == user_id })
  |> fn(result) {
    case result {
      Ok(player) -> player.is_ready
      Error(_) -> False
    }
  }
}

// is_player_ready_in_game - After
pub fn is_player_ready_in_game(game: Game, user_id: String) -> Bool {
  case dict.get(game.players, user_id) {
    Ok(player) -> player.is_ready
    Error(_) -> False
  }
}
```

---

#### 2. shared/src/lobby.gleam

**Imports:**
- Add `import gleam/dict`

**Function changes:**

```gleam
// create_lobby - Before
pub fn create_lobby(code: String, user_id: String, nickname: String) -> Lobby {
  let creator =
    Player(
      user_id: user_id,
      nickname: nickname,
      is_ready: False,
      is_creator: True,
    )
  Lobby(code: code, players: [creator], games_played: 0)
}

// create_lobby - After
pub fn create_lobby(code: String, user_id: String, nickname: String) -> Lobby {
  let creator =
    Player(
      user_id: user_id,
      nickname: nickname,
      is_ready: False,
      is_creator: True,
    )
  Lobby(code: code, players: dict.from_list([#(user_id, creator)]), games_played: 0)
}
```

```gleam
// add_player - Before
pub fn add_player(
  lobby: Lobby,
  user_id: String,
  nickname: String,
) -> Result(Lobby, String) {
  let existing_user =
    lobby.players
    |> list.find(fn(p) { p.user_id == user_id })

  case existing_user {
    Ok(old_player) -> {
      let reconnected_player =
        Player(
          user_id: user_id,
          nickname: old_player.nickname,
          is_ready: False,
          is_creator: old_player.is_creator,
        )
      let updated_players =
        lobby.players
        |> list.filter(fn(p) { p.user_id != user_id })
        |> list.prepend(reconnected_player)
      Ok(Lobby(..lobby, players: updated_players))
    }
    Error(_) -> {
      let nickname_taken =
        lobby.players
        |> list.any(fn(p) { p.nickname == nickname })

      case nickname_taken {
        True -> Error("Nickname already in use")
        False -> {
          let new_player =
            Player(
              user_id: user_id,
              nickname: nickname,
              is_ready: False,
              is_creator: False,
            )
          Ok(Lobby(..lobby, players: [new_player, ..lobby.players]))
        }
      }
    }
  }
}

// add_player - After
pub fn add_player(
  lobby: Lobby,
  user_id: String,
  nickname: String,
) -> Result(Lobby, String) {
  case dict.get(lobby.players, user_id) {
    Ok(old_player) -> {
      // Reconnection: reset ready status, preserve everything else
      let reconnected_player =
        Player(
          user_id: user_id,
          nickname: old_player.nickname,
          is_ready: False,
          is_creator: old_player.is_creator,
        )
      let updated_players = dict.insert(lobby.players, user_id, reconnected_player)
      Ok(Lobby(..lobby, players: updated_players))
    }
    Error(_) -> {
      // New player - check if nickname is already taken
      let nickname_taken =
        dict.values(lobby.players)
        |> list.any(fn(p) { p.nickname == nickname })

      case nickname_taken {
        True -> Error("Nickname already in use")
        False -> {
          let new_player =
            Player(
              user_id: user_id,
              nickname: nickname,
              is_ready: False,
              is_creator: False,
            )
          Ok(Lobby(..lobby, players: dict.insert(lobby.players, user_id, new_player)))
        }
      }
    }
  }
}
```

```gleam
// remove_player - Before
pub fn remove_player(lobby: Lobby, user_id: String) -> Lobby {
  Lobby(
    ..lobby,
    players: list.filter(lobby.players, fn(p) { p.user_id != user_id }),
  )
}

// remove_player - After
pub fn remove_player(lobby: Lobby, user_id: String) -> Lobby {
  Lobby(..lobby, players: dict.delete(lobby.players, user_id))
}
```

```gleam
// toggle_ready - Before
pub fn toggle_ready(lobby: Lobby, user_id: String) -> Result(Lobby, String) {
  let updated_players =
    lobby.players
    |> list.map(fn(player) {
      case player.user_id == user_id {
        True -> Player(..player, is_ready: !player.is_ready)
        False -> player
      }
    })

  let player_exists = list.any(updated_players, fn(p) { p.user_id == user_id })

  case player_exists {
    True -> Ok(Lobby(..lobby, players: updated_players))
    False -> Error("Player not found")
  }
}

// toggle_ready - After
pub fn toggle_ready(lobby: Lobby, user_id: String) -> Result(Lobby, String) {
  case dict.get(lobby.players, user_id) {
    Ok(player) -> {
      let updated_player = Player(..player, is_ready: !player.is_ready)
      Ok(Lobby(..lobby, players: dict.insert(lobby.players, user_id, updated_player)))
    }
    Error(_) -> Error("Player not found")
  }
}
```

```gleam
// all_players_ready - Before
pub fn all_players_ready(lobby: Lobby) -> Bool {
  case lobby.players {
    [] -> False
    _ -> list.all(lobby.players, fn(p) { p.is_ready })
  }
}

// all_players_ready - After
pub fn all_players_ready(lobby: Lobby) -> Bool {
  case dict.is_empty(lobby.players) {
    True -> False
    False -> dict.values(lobby.players) |> list.all(fn(p) { p.is_ready })
  }
}
```

```gleam
// is_creator - Before
pub fn is_creator(lobby: Lobby, user_id: String) -> Bool {
  lobby.players
  |> list.any(fn(p) { p.user_id == user_id && p.is_creator })
}

// is_creator - After
pub fn is_creator(lobby: Lobby, user_id: String) -> Bool {
  case dict.get(lobby.players, user_id) {
    Ok(player) -> player.is_creator
    Error(_) -> False
  }
}
```

```gleam
// get_player - Before
pub fn get_player(lobby: Lobby, user_id: String) -> Option(Player) {
  lobby.players
  |> list.find(fn(p) { p.user_id == user_id })
  |> option.from_result
}

// get_player - After
pub fn get_player(lobby: Lobby, user_id: String) -> Option(Player) {
  dict.get(lobby.players, user_id)
  |> option.from_result
}
```

---

#### 3. shared/src/game.gleam

**Imports:**
- Add `import gleam/dict.{type Dict}`

**Function changes:**

```gleam
// create_game_from_lobby - Before
let game_players =
  list.index_map(lobby.players, fn(player, idx) {
    let hand =
      hands
      |> list.drop(idx)
      |> list.first
      |> result.unwrap([])

    GamePlayer(
      user_id: player.user_id,
      nickname: player.nickname,
      hand: hand,
      is_ready: False,
    )
  })

let host_user_id =
  lobby.players
  |> list.find(fn(p) { p.is_creator })
  |> result.map(fn(p) { p.user_id })
  |> result.unwrap("")

// create_game_from_lobby - After
let players_list = dict.values(lobby.players)
let game_players =
  list.index_map(players_list, fn(player, idx) {
    let hand =
      hands
      |> list.drop(idx)
      |> list.first
      |> result.unwrap([])

    GamePlayer(
      user_id: player.user_id,
      nickname: player.nickname,
      hand: hand,
      is_ready: False,
    )
  })
  |> list.fold(dict.new(), fn(acc, p) { dict.insert(acc, p.user_id, p) })

let host_user_id =
  dict.values(lobby.players)
  |> list.find(fn(p) { p.is_creator })
  |> result.map(fn(p) { p.user_id })
  |> result.unwrap("")
```

```gleam
// toggle_ready_in_game - Before
pub fn toggle_ready_in_game(game: Game, user_id: String) -> Result(Game, String) {
  let player_exists =
    game.players
    |> list.any(fn(p) { p.user_id == user_id })

  case player_exists {
    False -> Error("Player not found")
    True -> {
      let updated_players =
        game.players
        |> list.map(fn(player) {
          case player.user_id == user_id {
            True -> GamePlayer(..player, is_ready: !player.is_ready)
            False -> player
          }
        })

      Ok(Game(..game, players: updated_players))
    }
  }
}

// toggle_ready_in_game - After
pub fn toggle_ready_in_game(game: Game, user_id: String) -> Result(Game, String) {
  case dict.get(game.players, user_id) {
    Error(_) -> Error("Player not found")
    Ok(player) -> {
      let updated_player = GamePlayer(..player, is_ready: !player.is_ready)
      Ok(Game(..game, players: dict.insert(game.players, user_id, updated_player)))
    }
  }
}
```

```gleam
// all_players_ready_in_game - Before
pub fn all_players_ready_in_game(game: Game) -> Bool {
  case game.players {
    [] -> False
    _ -> list.all(game.players, fn(p) { p.is_ready })
  }
}

// all_players_ready_in_game - After
pub fn all_players_ready_in_game(game: Game) -> Bool {
  case dict.is_empty(game.players) {
    True -> False
    False -> dict.values(game.players) |> list.all(fn(p) { p.is_ready })
  }
}
```

```gleam
// get_game_player - Before
pub fn get_game_player(game: Game, user_id: String) -> Result(GamePlayer, Nil) {
  game.players
  |> list.find(fn(p) { p.user_id == user_id })
}

// get_game_player - After
pub fn get_game_player(game: Game, user_id: String) -> Result(GamePlayer, Nil) {
  dict.get(game.players, user_id)
}
```

```gleam
// deal_round - Before
let updated_players =
  list.index_map(game.players, fn(player, idx) {
    let hand =
      hands
      |> list.drop(idx)
      |> list.first
      |> result.unwrap([])

    GamePlayer(..player, hand: hand, is_ready: False)
  })

// deal_round - After
let players_list = dict.values(game.players)
let updated_players =
  list.index_map(players_list, fn(player, idx) {
    let hand =
      hands
      |> list.drop(idx)
      |> list.first
      |> result.unwrap([])

    GamePlayer(..player, hand: hand, is_ready: False)
  })
  |> list.fold(dict.new(), fn(acc, p) { dict.insert(acc, p.user_id, p) })
```

```gleam
// resolve_nicknames - Before
fn resolve_nicknames(
  game: Game,
  user_id_card_pairs: List(#(String, Card)),
) -> List(#(String, Card)) {
  list.map(user_id_card_pairs, fn(pair) {
    let nickname = case list.find(game.players, fn(p) { p.user_id == pair.0 }) {
      Ok(p) -> p.nickname
      Error(_) -> pair.0
    }
    #(nickname, pair.1)
  })
}

// resolve_nicknames - After
fn resolve_nicknames(
  game: Game,
  user_id_card_pairs: List(#(String, Card)),
) -> List(#(String, Card)) {
  list.map(user_id_card_pairs, fn(pair) {
    let nickname = case dict.get(game.players, pair.0) {
      Ok(p) -> p.nickname
      Error(_) -> pair.0
    }
    #(nickname, pair.1)
  })
}
```

```gleam
// reset_ready_states - Before
fn reset_ready_states(game: Game) -> Game {
  let updated_players =
    list.map(game.players, fn(p) { GamePlayer(..p, is_ready: False) })
  Game(..game, players: updated_players)
}

// reset_ready_states - After
fn reset_ready_states(game: Game) -> Game {
  let updated_players =
    dict.map_values(game.players, fn(_, p) { GamePlayer(..p, is_ready: False) })
  Game(..game, players: updated_players)
}
```

```gleam
// find_mistake_cards - Before
fn find_mistake_cards(
  game: Game,
  playing_user_id: String,
  played_card: Card,
) -> List(#(String, Card)) {
  game.players
  |> list.filter(fn(p) { p.user_id != playing_user_id })
  |> list.filter_map(fn(p) {
    case p.hand {
      [lowest, ..] if lowest < played_card -> Ok(#(p.user_id, lowest))
      _ -> Error(Nil)
    }
  })
}

// find_mistake_cards - After
fn find_mistake_cards(
  game: Game,
  playing_user_id: String,
  played_card: Card,
) -> List(#(String, Card)) {
  dict.values(game.players)
  |> list.filter(fn(p) { p.user_id != playing_user_id })
  |> list.filter_map(fn(p) {
    case p.hand {
      [lowest, ..] if lowest < played_card -> Ok(#(p.user_id, lowest))
      _ -> Error(Nil)
    }
  })
}
```

```gleam
// discard_cards_below - Before
fn discard_cards_below(game: Game, played_card: Card) -> Game {
  let updated_players =
    game.players
    |> list.map(fn(player) {
      let new_hand = list.filter(player.hand, fn(c) { c >= played_card })
      GamePlayer(..player, hand: new_hand)
    })
  Game(..game, players: updated_players)
}

// discard_cards_below - After
fn discard_cards_below(game: Game, played_card: Card) -> Game {
  let updated_players =
    dict.map_values(game.players, fn(_, player) {
      let new_hand = list.filter(player.hand, fn(c) { c >= played_card })
      GamePlayer(..player, hand: new_hand)
    })
  Game(..game, players: updated_players)
}
```

```gleam
// all_hands_empty - Before
fn all_hands_empty(game: Game) -> Bool {
  list.all(game.players, fn(p) { p.hand == [] })
}

// all_hands_empty - After
fn all_hands_empty(game: Game) -> Bool {
  dict.values(game.players) |> list.all(fn(p) { p.hand == [] })
}
```

```gleam
// update_player_hand - Before
fn update_player_hand(game: Game, user_id: String, new_hand: List(Card)) -> Game {
  let updated_players =
    game.players
    |> list.map(fn(player) {
      case player.user_id == user_id {
        True -> GamePlayer(..player, hand: new_hand)
        False -> player
      }
    })
  Game(..game, players: updated_players)
}

// update_player_hand - After
fn update_player_hand(game: Game, user_id: String, new_hand: List(Card)) -> Game {
  case dict.get(game.players, user_id) {
    Ok(player) -> {
      let updated_player = GamePlayer(..player, hand: new_hand)
      Game(..game, players: dict.insert(game.players, user_id, updated_player))
    }
    Error(_) -> game
  }
}
```

```gleam
// get_throwing_star_discards - Before
pub fn get_throwing_star_discards(game: Game) -> List(#(String, Card)) {
  game.players
  |> list.filter_map(fn(player) {
    case player.hand {
      [lowest, ..] -> Ok(#(player.nickname, lowest))
      [] -> Error(Nil)
    }
  })
}

// get_throwing_star_discards - After
pub fn get_throwing_star_discards(game: Game) -> List(#(String, Card)) {
  dict.values(game.players)
  |> list.filter_map(fn(player) {
    case player.hand {
      [lowest, ..] -> Ok(#(player.nickname, lowest))
      [] -> Error(Nil)
    }
  })
}
```

```gleam
// apply_throwing_star - Before (relevant part)
let discarded_cards =
  game.players
  |> list.filter_map(fn(player) {
    case player.hand {
      [lowest, ..] -> Ok(lowest)
      [] -> Error(Nil)
    }
  })
...
let updated_players =
  game.players
  |> list.map(fn(player) {
    case player.hand {
      [_, ..rest] -> GamePlayer(..player, hand: rest)
      [] -> player
    }
  })

// apply_throwing_star - After (relevant part)
let discarded_cards =
  dict.values(game.players)
  |> list.filter_map(fn(player) {
    case player.hand {
      [lowest, ..] -> Ok(lowest)
      [] -> Error(Nil)
    }
  })
...
let updated_players =
  dict.map_values(game.players, fn(_, player) {
    case player.hand {
      [_, ..rest] -> GamePlayer(..player, hand: rest)
      [] -> player
    }
  })
```

```gleam
// game_to_lobby - Before
pub fn game_to_lobby(game: Game) -> Lobby {
  let lobby_players =
    list.map(game.players, fn(p) {
      Player(
        user_id: p.user_id,
        nickname: p.nickname,
        is_ready: False,
        is_creator: p.user_id == game.host_user_id,
      )
    })
  Lobby(
    code: game.code,
    players: lobby_players,
    games_played: game.games_played + 1,
  )
}

// game_to_lobby - After
pub fn game_to_lobby(game: Game) -> Lobby {
  let lobby_players =
    dict.map_values(game.players, fn(_, p) {
      Player(
        user_id: p.user_id,
        nickname: p.nickname,
        is_ready: False,
        is_creator: p.user_id == game.host_user_id,
      )
    })
  Lobby(
    code: game.code,
    players: lobby_players,
    games_played: game.games_played + 1,
  )
}
```

---

#### 4. server/src/game_server.gleam

Key patterns to update (search and replace):

| Pattern | Replacement |
|---------|-------------|
| `list.length(lobby.players)` | `dict.size(lobby.players)` |
| `list.length(game.players)` | `dict.size(game.players)` |
| `list.find(lobby.players, fn(p) { p.user_id == ... })` | `dict.get(lobby.players, ...)` |
| `list.find(game.players, fn(p) { p.user_id == ... })` | `dict.get(game.players, ...)` |
| `list.map(game.players, ...)` where updating by user_id | `dict.map_values(game.players, ...)` or `dict.insert` |
| `list.filter(lobby.players, ...)` for removal | `dict.delete(lobby.players, ...)` |
| `lobby.players` iteration | `dict.values(lobby.players)` |
| `game.players` iteration | `dict.values(game.players)` |
| `list.first(lobby.players)` for host reassignment | `dict.values(lobby.players) |> list.first` |

Specific functions to update (non-exhaustive, search for `players` usages):
- `handle_leave_game` - host reassignment logic
- `handle_restart_game` - player count check
- `handle_start_game` - player count check
- Vote initiation - pending list creation
- Broadcasting - iteration over players

---

#### 5. client/src/client.gleam

Key patterns to update:

| Pattern | Replacement |
|---------|-------------|
| `list.find(lobby.players, fn(p) { p.user_id == ... })` | `dict.get(lobby.players, ...)` |
| `list.find(game.players, fn(p) { p.user_id == ... })` | `dict.get(game.players, ...)` |
| `list.map(lobby.players, view_player)` | `dict.values(lobby.players) |> list.map(view_player)` |
| `list.map(game.players, view_game_player)` | `dict.values(game.players) |> list.map(view_game_player)` |
| `list.length(lobby.players)` | `dict.size(lobby.players)` |
| `list.length(game.players)` | `dict.size(game.players)` |

---

### Pattern Reference

| Old Pattern | New Pattern |
|-------------|-------------|
| `list.find(players, fn(p) { p.user_id == id })` | `dict.get(players, id)` |
| `list.map(players, fn(p) { ... })` | `dict.map_values(players, fn(_, p) { ... })` |
| `list.filter(players, fn(p) { p.user_id != id })` | `dict.delete(players, id)` |
| `list.any(players, fn(p) { ... })` | `dict.values(players) \|> list.any(...)` |
| `list.all(players, fn(p) { ... })` | `dict.values(players) \|> list.all(...)` |
| `list.length(players)` | `dict.size(players)` |
| `[player, ..players]` | `dict.insert(players, player.user_id, player)` |
| `case players { [] -> ... }` | `case dict.is_empty(players) { True -> ... }` |

---

## Example 2: VoteState.pending from List to Set

**Status:** Not yet planned

**Summary:** Change `VoteState.pending: List(String)` to `Set(String)` for O(1) membership checks and clearer semantics.

### Use Cases in Codebase

| Location | Current Code | Required API |
|----------|--------------|--------------|
| game_server.gleam:1221, 1479 | `pending: user_ids` (from List) | `set.from_list(user_ids)` |
| game_server.gleam:933, 1033 | `list.contains(vote_state.pending, user_id)` | `set.contains(pending, user_id)` |
| game_server.gleam:1260, 1518 | `list.filter(vote_state.pending, fn(uid) { uid != user_id })` | `set.delete(pending, user_id)` |
| game_server.gleam:206, 277 | `list.fold(vote_state.pending, ...)` | `set.fold(pending, ...)` |
| game_server.gleam:210, 282 | `pending: []` | `set.new()` |
| game_server.gleam:197, 267, 1951, 1957 | passed to `VoteUpdate` message | `set.to_list(pending)` |

### Changes to server/src/game_server.gleam

**Imports:**
```gleam
import gleam/set.{type Set}
```

**Type change:**
```gleam
// Before
pub type VoteState {
  VoteState(game_code: String, votes: Dict(String, Bool), pending: List(String))
}

// After
pub type VoteState {
  VoteState(game_code: String, votes: Dict(String, Bool), pending: Set(String))
}
```

**Pattern replacements:**

```gleam
// Creation - Before
VoteState(game_code: game_code, votes: dict.new(), pending: user_ids)

// Creation - After
VoteState(game_code: game_code, votes: dict.new(), pending: set.from_list(user_ids))
```

```gleam
// Membership check - Before
list.contains(vote_state.pending, user_id)

// Membership check - After
set.contains(vote_state.pending, user_id)
```

```gleam
// Removal - Before
list.filter(vote_state.pending, fn(uid) { uid != user_id })

// Removal - After
set.delete(vote_state.pending, user_id)
```

```gleam
// Iteration - Before
list.fold(vote_state.pending, vote_state.votes, fn(acc, pid) { ... })

// Iteration - After
set.fold(vote_state.pending, vote_state.votes, fn(acc, pid) { ... })
```

```gleam
// Clear - Before
VoteState(..vote_state, votes: final_votes, pending: [])

// Clear - After
VoteState(..vote_state, votes: final_votes, pending: set.new())
```

```gleam
// Serialization (for VoteUpdate messages) - Before
protocol.ThrowingStarVoteUpdate(votes_list, vote_state.pending, seconds)

// Serialization - After
protocol.ThrowingStarVoteUpdate(votes_list, set.to_list(vote_state.pending), seconds)
```

### Benefits

1. **O(1) membership check** - `set.contains` vs O(n) `list.contains`
2. **Clearer semantics** - Set explicitly communicates "unique collection"
3. **Cleaner removal** - `set.delete` vs `list.filter`
4. **No duplicates possible** - enforced by data structure

---

## Example 3: PlayedPile opaque type

**Status:** Not yet planned

**Summary:** Replace `played_cards: List(Card)` with `played_pile: PlayedPile` where `PlayedPile` is an opaque type that maintains both the card history and the top card via a tested API.

**Problem:** Currently `list.last(played_cards)` is O(n) and called frequently.

**Solution:** Create an opaque type that encapsulates the invariant.

### Use Cases in Codebase

| Location | Current Code | Required API |
|----------|--------------|--------------|
| game.gleam:149 (create_game_from_lobby) | `played_cards: []` | `played_pile.new()` |
| game.gleam:234 (deal_round) | `played_cards: []` | `played_pile.new()` |
| game.gleam:405 (handle_round_complete) | `played_cards: []` | `played_pile.new()` |
| game.gleam:425 (add_played_card) | `list.append(game.played_cards, [card])` | `played_pile.push(pile, card)` |
| game.gleam:476 (apply_throwing_star) | `list.append(game.played_cards, [highest_discard])` | `played_pile.push(pile, card)` |
| client.gleam:1144 (view_played_pile) | `list.last(played_cards)` | `played_pile.top(pile)` |
| protocol.gleam:317 (encode_game) | `json.array(game.played_cards, json.int)` | `played_pile.to_list(pile)` |
| protocol.gleam:605 (game_decoder) | `decode_int_list()` then use directly | `played_pile.from_list(cards)` |
| client.ffi.mjs:240 | `toList(gameData.played_cards)` | (unchanged - works with to_list output) |
| game_test.gleam (assertions) | `updated.played_cards \|> should.equal([...])` | `played_pile.to_list(pile) \|> should.equal([...])` |

### Required API

| Function | Signature | Description |
|----------|-----------|-------------|
| `new` | `() -> PlayedPile` | Create empty pile |
| `push` | `(PlayedPile, Int) -> PlayedPile` | Add card to pile, update top |
| `top` | `(PlayedPile) -> Option(Int)` | Get top card in O(1) |
| `to_list` | `(PlayedPile) -> List(Int)` | Get all cards for serialization |
| `from_list` | `(List(Int)) -> PlayedPile` | Create from list (deserialization) |
| `is_empty` | `(PlayedPile) -> Bool` | Check if pile is empty |

### New file: shared/src/played_pile.gleam

```gleam
import gleam/list
import gleam/option.{type Option, None, Some}

/// Opaque type representing the pile of played cards.
/// Maintains both the full history and cached top card.
pub opaque type PlayedPile {
  PlayedPile(cards: List(Int), top: Option(Int))
}

/// Create an empty pile
pub fn new() -> PlayedPile {
  PlayedPile(cards: [], top: None)
}

/// Push a card onto the pile. Returns the updated pile.
pub fn push(pile: PlayedPile, card: Int) -> PlayedPile {
  PlayedPile(cards: list.append(pile.cards, [card]), top: Some(card))
}

/// Get the top card of the pile (O(1))
pub fn top(pile: PlayedPile) -> Option(Int) {
  pile.top
}

/// Get all cards in the pile in play order
pub fn to_list(pile: PlayedPile) -> List(Int) {
  pile.cards
}

/// Check if pile is empty
pub fn is_empty(pile: PlayedPile) -> Bool {
  pile.top == None
}

/// Create a pile from a list of cards (for deserialization)
pub fn from_list(cards: List(Int)) -> PlayedPile {
  PlayedPile(cards: cards, top: list.last(cards) |> option.from_result)
}
```

### Test file: shared/test/played_pile_test.gleam

```gleam
import gleeunit/should
import gleam/option.{None, Some}
import played_pile

pub fn new_pile_is_empty_test() {
  let pile = played_pile.new()

  played_pile.is_empty(pile) |> should.be_true
  played_pile.top(pile) |> should.equal(None)
  played_pile.to_list(pile) |> should.equal([])
}

pub fn push_single_card_test() {
  let pile = played_pile.new() |> played_pile.push(42)

  played_pile.is_empty(pile) |> should.be_false
  played_pile.top(pile) |> should.equal(Some(42))
  played_pile.to_list(pile) |> should.equal([42])
}

pub fn push_multiple_cards_test() {
  let pile =
    played_pile.new()
    |> played_pile.push(5)
    |> played_pile.push(23)
    |> played_pile.push(47)

  played_pile.top(pile) |> should.equal(Some(47))
  played_pile.to_list(pile) |> should.equal([5, 23, 47])
}

pub fn from_list_empty_test() {
  let pile = played_pile.from_list([])

  played_pile.is_empty(pile) |> should.be_true
  played_pile.top(pile) |> should.equal(None)
}

pub fn from_list_with_cards_test() {
  let pile = played_pile.from_list([5, 23, 47])

  played_pile.top(pile) |> should.equal(Some(47))
  played_pile.to_list(pile) |> should.equal([5, 23, 47])
}
```

### Changes to protocol.gleam

```gleam
// Before
pub type Game {
  Game(
    ...
    played_cards: List(Card),
    ...
  )
}

// After
import played_pile.{type PlayedPile}

pub type Game {
  Game(
    ...
    played_pile: PlayedPile,
    ...
  )
}
```

**JSON encoding** (wire format unchanged - still an array):
```gleam
// encode_game
#("played_cards", json.array(played_pile.to_list(game.played_pile), json.int))

// game_decoder
use played_cards <- decode.field("played_cards", decode_int_list())
...
decode.success(Game(
  ...
  played_pile: played_pile.from_list(played_cards),
  ...
))
```

### Changes to game.gleam

```gleam
// add_played_card - Before
fn add_played_card(game: Game, card: Card) -> Game {
  Game(..game, played_cards: list.append(game.played_cards, [card]))
}

// add_played_card - After
fn add_played_card(game: Game, card: Card) -> Game {
  Game(..game, played_pile: played_pile.push(game.played_pile, card))
}
```

```gleam
// Anywhere checking pile top - Before
case list.last(game.played_cards) {
  Ok(top) -> ...
  Error(_) -> ...
}

// After
case played_pile.top(game.played_pile) {
  Some(top) -> ...
  None -> ...
}
```

```gleam
// create_game_from_lobby - Before
played_cards: []

// After
played_pile: played_pile.new()
```

```gleam
// deal_round - Before
played_cards: []

// After
played_pile: played_pile.new()
```

### Benefits

1. **Invariant enforced by API** - impossible to have mismatched top/cards
2. **Tested** - unit tests verify correctness
3. **O(1) top access** - via `played_pile.top()`
4. **Encapsulated** - opaque type prevents direct field access
5. **Wire format unchanged** - JSON still uses `played_cards` array

---

## Implementation Order

1. Example 3: PlayedPile opaque type (smallest change, good test coverage, establishes pattern)
2. Example 1: Convert players to Dict (largest change, most value)
3. Example 2: VoteState.pending (optional, minimal impact)

---

## Testing Strategy

After each change:
1. Run `gleam build` in shared/, server/, client/
2. Run `gleam test` in shared/ (if tests exist)
3. Manual testing: create lobby, join, start game, play cards, vote, end game
