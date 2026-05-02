# Remaining Tasks

Tasks are ordered by importance. HIGH PRIORITY tasks are critical for gameplay or architecture.

## HIGH PRIORITY

**Task 1 [M] (HIGH PRIORITY): Mistake Audit Resolution**
See [mistake-audit-resolution.md](mistake-audit-resolution.md) for detailed implementation plan.
Implements buffering window for near-simultaneous card plays with FIFO resolution. Captures time deltas between card arrivals for audit/display purposes.

**Task 2 [XL] (HIGH PRIORITY): Per-Game Actor Architecture**
Refactor from single central actor to per-game actors using named processes.

**Motivation:**
- Each game actor owns its own state (no Dict lookups)
- Timers are per-actor (simpler than `Dict(String, Timer)`)
- Isolation: bug in one game can't corrupt another
- Natural cleanup: actor terminates when game ends

**Architecture Overview:**
```
Application Supervisor
    │
    └─▶ Factory Supervisor (gleam/otp/factory_supervisor)
            │
            ├─▶ Game Actor "game_ABC123" (named process)
            │
            └─▶ Game Actor "game_XYZ789" (named process)

Connection Process (per WebSocket)
    │
    ├─▶ process.named("game_ABC123") ─▶ Game Actor
    │
    └─▶ process.named("game_XYZ789") ─▶ Game Actor
```

- `factory_supervisor.start_child()` to spawn new game actors
- Game actors register themselves as named processes on startup
- Supervisor handles crashes/restarts; named process lookup handles routing

**2a [M]: Game Actor Module**
- Use `gleam/otp/factory_supervisor` to manage game actor children dynamically
- Factory supervisor spawns game actors on demand, supervises them, handles restarts
- Create `server/src/game_actor.gleam` with new actor type
- Define `GameActorState`:
  - `code: String`
  - `phase: GamePhase` (Lobby | Playing(Game))
  - `players: Dict(String, Player)`
  - `connections: Dict(String, Subject(ServerMessage))` (user_id → subject)
  - `vote_state: Option(VoteState)`
  - `countdown_timer: Option(...)`, `vote_timer: Option(...)`
- Define `GameActorMsg`:
  - `PlayerJoined(user_id, nickname, Subject(ServerMessage))`
  - `PlayerDisconnected(user_id)`
  - `ClientMessage(user_id, ClientMessage)`
  - `CountdownTick`, `VoteTick`, `CleanupTick`
- Implement `start(code) -> Subject(GameActorMsg)` that registers as `"game_" <> code`
- Port existing handlers to operate on `GameActorState` (no Dict lookups)

**2b [M]: Connection Process State**
- Modify `server.gleam` WebSocket handler to maintain connection state:
  - `subject: Subject(ServerMessage)` (to send to client)
  - `user_id: Option(String)`
  - `game_code: Option(String)`
  - `game_subject: Option(Subject(GameActorMsg))` (cached for routing)
- On `CreateGame`: call `factory_supervisor.start_child(factory, game_code)` to spawn supervised game actor
- On `JoinGame`: lookup `process.named("game_" <> code)`, forward `PlayerJoined`
- On other messages: forward to cached `game_subject`
- On WebSocket close: send `PlayerDisconnected` to game actor

**2c [S]: Reconnection Handling**
- Client sends `JoinGame(code, user_id, nickname)` on reconnect (has both in localStorage)
- Connection process looks up `process.named("game_" <> code)`
- Game actor receives `PlayerJoined`, detects existing `user_id` → reconnection
- Game actor updates `connections` dict with new subject
- Game actor sends current state (game, vote status, countdown) to reconnected player
- No separate "reconnect" message needed

**2d [M]: Disconnect Cleanup & Server State Cleanup**
- Connection process sends `PlayerDisconnected(user_id)` on WebSocket close
- Game actor marks player disconnected, starts cleanup timer if last player
- If all players disconnect: 5-minute timer, then actor terminates and unregisters
- If player reconnects: cancel cleanup timer
- Prevents orphaned games from accumulating in memory

**2e [M]: Remove Central Actor**
- Delete `server/src/game_server/` directory (or repurpose minimally)
- Remove `game_server` actor startup from `server.gleam`
- All game state now lives in per-game actors
- Consider: keep a lightweight registry actor for admin/metrics (list all games, count players)

**Migration Strategy:**
- Can be done incrementally: start with game actor for new games while central actor handles existing
- Or: clean cutover (simpler, no compatibility layer)

**Crash Recovery Consideration:**
- If a game actor crashes, game state is lost (in-memory only)
- Options: (1) let supervisor restart with fresh state (players see empty lobby), or (2) don't restart (players get "game not found" error and start new game)
- Option 2 is simpler - avoids re-registration complexity, acceptable UX for rare crashes
- Future: persist state to ETS for recovery (out of scope for initial implementation)

**Testing:**
- Unit tests for game actor message handling
- Integration test: create game, join, play cards, disconnect/reconnect
- Test: game cleanup after all players leave
- Test: named process collision handling (generate unique codes)

**Task 3 [S] (HIGH PRIORITY): Display Game Log on Defeat Screen**
- Game log should be visible on EndGame screen when outcome is Loss
- Helps players review what went wrong in the final moments
- Follow existing EndGame layout pattern (two-column on md+, includes log)

**Task 4 [S] (HIGH PRIORITY): Investigate Auto-Play UX After Pause**
- **Observed:** After mistake, Pause phase with one player having one card. Players ready up, transition directly to Dealing (new round) with no visible auto-play feedback.
- **Expected behavior (per rules):** Auto-play should apply the single player's cards, complete the round, then transition to Dealing. This IS happening server-side.
- **Investigate:**
  1. Verify auto-played cards ARE logged (game log shows "X automatically played Y")
  2. Check if game log is visible during this transition (Pause → Dealing)
  3. Consider adding toast/animation feedback for auto-play so players understand what happened
  4. Verify the pile reflects the auto-played card before transition
- **Root cause hypothesis:** Auto-play works correctly but UX is confusing - no visual feedback, transition too fast, or game log not visible during Pause phase exit.
- **Code paths:** `game_play.gleam:61` (`AutoPlayThenDeal`), `perform_auto_play()`, `game_log.gleam:158` (log formatting)

## MEDIUM PRIORITY

**Task 5 [S]: Eliminate GameLogEvent Server Message**
- `GameLogEvent` is redundant: every action that logs an event also broadcasts `GameStateUpdate` with full `game_log`
- Client already uses `game_log` from `GameStateUpdate` (replaces whole game state)
- Remove `GameLogEvent` broadcasts from server (`log_event` function and disconnect/reconnect handlers)
- Remove `GameLogEvent` handling from client
- Add timestamp to `PlayerDisconnected`/`PlayerReconnected` messages (these don't trigger `GameStateUpdate`)
- Server still maintains `game_log` on `Game` type for reconnection state
- Simplifies protocol and reduces network traffic

## LOW PRIORITY

**Task 6 [M]: Latency Compensation**
See [latency-compensation.md](latency-compensation.md) for detailed implementation plan.
Builds on Task 1 (Mistake Audit Resolution) by adding ping/pong latency measurement and latency-adjusted timestamp resolution.

**Task 7 [S]: Spacebar to Play Card**
- Add keyboard shortcut: spacebar triggers "Play" button in ActivePlay phase
- Only active when Play button is visible and enabled
- Consider focus management (don't trigger if typing in input)

**Task 8 [L]: Data Structure Refactoring**
See `context/data-structures-refactor.md` for detailed implementation plan.

- **8a [S]: PlayedPile opaque type** - Replace `played_cards: List(Card)` with `played_pile: PlayedPile` opaque type that encapsulates card history and cached top card. Includes unit tests. Provides O(1) top card access.
- **8b [M]: Players List to Dict** - Change `Lobby.players: List(Player)` and `Game.players: List(GamePlayer)` to `Dict(String, Player/GamePlayer)` keyed by user_id. Cleaner lookups via `dict.get` instead of `list.find`. Wire format unchanged (JSON arrays).
- **8c [S]: VoteState.pending List to Set** - Change `VoteState.pending: List(String)` to `Set(String)` for O(1) membership checks and clearer semantics.

**Task 9 [L]: Type-Safe UserId with youid**
- Add `youid` dependency to shared/server/client
- Replace `user_id: String` with `user_id: Uuid` from `youid/uuid`
- Update `Player`, `GamePlayer`, `Game` (host_user_id), `Model` types
- Update JSON encoding/decoding (UUID ↔ String conversion at protocol boundary)
- Update Dict keys where user_id is used (connections, player_latencies, votes, etc.)
- Update localStorage read/write in client.ffi.mjs
- Benefits: compile-time safety, can't mix up user_id with nickname/game_code
