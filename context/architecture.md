# Shoebill Strike - Architecture Documentation

## Project Structure

```
shoebill_strike/
├── shared/                 # Shared types and logic (used by both server and client)
│   ├── src/
│   │   ├── protocol.gleam  # Message types, encoding/decoding
│   │   ├── game.gleam      # Core game logic (pure functions)
│   │   └── lobby.gleam     # Lobby management logic
│   └── test/
│       ├── game_test.gleam
│       ├── lobby_test.gleam
│       └── protocol_test.gleam
├── server/                 # Gleam server (Erlang target)
│   ├── src/
│   │   ├── server.gleam        # HTTP server, WebSocket handling
│   │   ├── game_server/
│   │   │   ├── actor.gleam     # Actor entry point, message routing
│   │   │   ├── state.gleam     # Server state types (ServerState, ServerMsg)
│   │   │   ├── helpers.gleam   # Pure helper functions
│   │   │   ├── broadcast.gleam # Message broadcasting
│   │   │   ├── countdown.gleam # Countdown timer logic
│   │   │   ├── event_log.gleam # Game event logging
│   │   │   └── handlers/
│   │   │       ├── abandon_vote.gleam   # Abandon vote state and resolution
│   │   │       ├── connection.gleam     # Connection/reconnection handlers
│   │   │       ├── end_game.gleam       # Leave/restart game handlers
│   │   │       ├── game_play.gleam      # Ready/play card handlers
│   │   │       ├── lobby.gleam          # Create/join/start game handlers
│   │   │       ├── strike_vote.gleam    # Strike vote state and resolution
│   │   │       ├── ticks.gleam          # Countdown and vote tick handlers
│   │   │       └── vote_initiation.gleam # Strike/abandon vote initiation
│   │   └── game_server.gleam   # Re-exports actor.start()
│   └── priv/static/            # Built client files served here
└── client/                     # Lustre client (JavaScript target)
    ├── src/
    │   ├── client.gleam        # Lustre application entry point
    │   ├── client.ffi.mjs      # JavaScript interop (WebSocket, localStorage)
    │   ├── icons.gleam         # Game icon SVG definitions
    │   ├── client/
    │   │   ├── model.gleam     # Model type and Screen enum
    │   │   ├── msg.gleam       # Msg type definitions
    │   │   ├── init.gleam      # Initialization logic
    │   │   ├── update.gleam    # Update function and effects
    │   │   ├── effects.gleam   # Effect helpers (WebSocket, clipboard)
    │   │   ├── server_messages.gleam  # Server message dispatch handler
    │   │   └── views/
    │   │       ├── home.gleam      # Home/create/join screens
    │   │       ├── lobby.gleam     # Lobby screen
    │   │       ├── game.gleam      # Game screen (dealing, active, pause)
    │   │       ├── game_phases.gleam # Strike/abandon/end phases
    │   │       ├── game_log.gleam  # Game event log display
    │   │       └── components/
    │   │           ├── feedback.gleam  # Toast, error, countdown, mistake info
    │   │           ├── players.gleam   # Game header, other players
    │   │           ├── cards.gleam     # Card display, pile and hand
    │   │           ├── actions.gleam   # Ready buttons, vote section
    │   │           └── stats.gleam     # Stat display, reward guide
    │   └── mock_routes/
    │       ├── types.gleam         # Route enum, mock param types
    │       ├── parsing.gleam       # URL parsing and param extraction
    │       └── builders/
    │           ├── common.gleam    # Base mock builders
    │           ├── game_log.gleam  # Mock game log builders
    │           └── phases.gleam    # Phase-specific mock builders
    └── tailwind.css            # Tailwind CSS input file
```

## Technology Stack

| Layer | Technology | Purpose |
|-------|------------|---------|
| Server Runtime | Erlang/OTP | Concurrency, fault tolerance |
| Server Framework | Mist | HTTP server with WebSocket support |
| Server State | OTP Actor | Single actor managing all game state |
| Client Framework | Lustre | Elm-like MVU architecture for UI |
| Client Target | JavaScript | Runs in browser |
| Shared Code | Gleam | Type-safe code sharing between targets |
| Communication | WebSocket | Real-time bidirectional messaging |
| Serialization | JSON | Message encoding/decoding |
| CSS Framework | TailwindCSS | Utility-first styling |

## CSS/Styling

### Tailwind Setup

| Item | Path |
|------|------|
| Input CSS | `client/tailwind.css` |
| Output CSS | `server/priv/static/styles.css` |
| Config | `tailwind.config.js` |

The build process compiles Tailwind CSS:
```bash
tailwindcss -i client/tailwind.css -o server/priv/static/styles.css --minify
```

### Design Tokens

- **Dark mode primary**: `bg-gray-900` (page), `bg-gray-800` (cards), `bg-gray-700` (elements)
- **Text**: `text-gray-100` (primary), `text-gray-400` (secondary)
- **Status**: `text-red-400` (error)
- **Custom button colors** (hex values in tailwind.css):
  - `#687487` (btn-primary) - muted blue-gray
  - `#876884` (btn-ready) - muted purple
  - `#68876B` (btn-approve) - muted green
  - `#877B68` (btn-strike) - muted gold
  - `bg-gray-700` (btn-secondary)

### Custom Component Classes

Defined in `@layer components` in `client/tailwind.css`:

| Class | Purpose |
|-------|---------|
| `.btn` | Base button: full width, padding, rounded, font-semibold, transition |
| `.btn-primary` | Primary action (muted blue-gray) |
| `.btn-ready` | Ready toggle (muted purple) |
| `.btn-secondary` | Secondary action (gray) |
| `.btn-disabled` | Disabled state (muted, cursor-not-allowed) |
| `.btn-approve` | Vote approve (muted green) |
| `.btn-reject` | Vote reject (red) |
| `.btn-strike` | Strike action (muted gold) |
| `.btn-abandon` | Abandon action (muted red) |
| `.btn-small` | Smaller button variant |
| `.btn-copy` | Copy to clipboard button |
| `.input` | Text input with focus ring |
| `.card` | Card container (gray-800, rounded, shadow, responsive max-width) |
| `.error-message` | Error text (red, small, centered) |

### Responsive Layout Classes

**IMPORTANT** The UI uses a mobile-first approach with Tailwind breakpoints:
- **Default (mobile)**: Single column, `max-w-md` (448px)
- **md (768px+)**: Two-column layouts for Lobby/EndGame
- **lg (1024px+)**: Two-column game layout with sidebar log

| Class | Purpose |
|-------|---------|
| `.game-container` | Responsive width container for game screens |
| `.game-screen-wrapper` | Wrapper for game screen layout |
| `.game-log` | Fixed bottom overlay on mobile, sidebar on lg+ |
| `.game-log-list` | Scrollable list container for log entries |
| `.game-log-entry` | Individual log entry with timestamp and event |
| `.hand-grid` | Responsive card grid: 4 cols (mobile) → 6 cols (md) → 8 cols (lg) |
| `.other-players-grid` | Responsive player grid: 3 cols (mobile) → 2 cols (md) → 1 col (lg) |
| `.responsive-two-col` | Two-column responsive layout |
| `.responsive-three-col` | Three-column responsive layout |
| `.col-main` | Main content column |
| `.col-side` | Side content column |
| `.col-players` | Players list column |
| `.col-log` | Game log column |
| `.reward-guide-toggle` | Toggle button for reward guide |
| `.reward-guide` | Reward guide panel container |
| `.reward-guide-list` | Reward list items |
| `.reward-guide-item` | Individual reward item |

**IMPORTANT** media queries should not be used for the mobile designs

**Layout by Screen:**

| Screen | Mobile | md (768px+) | lg (1024px+) |
|--------|--------|-------------|--------------|
| Lobby | Single column | Two columns (code+buttons \| players) | Same as md |
| Game (play phases) | Stacked, log overlay | Same as mobile | Two columns (main \| log sidebar) |
| EndGame | Stacked | Two columns (stats+buttons \| players+log) | Same as md |

**Game Phase Layout Pattern:**

All game phases (Dealing, ActivePlay, Pause, Strike, AbandonVote) use responsive layout with a single game log component:

```html
<!-- Outer container - centers content -->
<div class="min-h-screen p-3 flex flex-col items-center lg:justify-center">
  <!-- Wrapper with relative positioning -->
  <div class="relative">
    <!-- Main column - determines the height -->
    <div class="flex flex-col gap-3 w-full max-w-md lg:w-[28rem]">
      <!-- Header, players, hand, buttons -->
    </div>
    <!-- Game log - responsive: fixed bottom on mobile, sidebar on lg+ -->
    <div class="game-log">
      <!-- Single log component that adapts via CSS -->
    </div>
  </div>
</div>
```

Key aspects:
- Wrapper has `relative` positioning to act as the positioned ancestor
- Main column has fixed width (`lg:w-[28rem]`) and determines the container height
- **Single game log component** - renders once, uses CSS to adapt between mobile overlay and desktop sidebar
- On mobile/tablet: `.game-log` is fixed at bottom of screen
- On lg+ screens: `.game-log` is positioned as sidebar to the right of main content

**IMPORTANT: Responsive Design Pattern**
The game log must NOT be rendered twice with one hidden. This violates responsive design principles. Instead, render the component once and use CSS breakpoints to change its layout/positioning.

**Button Position Consistency:** The Ready button (Lobby/Dealing/Pause) and Play button (ActivePlay) are positioned in the same column across screen transitions for easier discovery.

### Animation Utilities

Defined in `@layer utilities` in `client/tailwind.css`:

| Class | Purpose |
|-------|---------|
| `.animate-countdown` | Pulse animation for countdown numbers |
| `.animate-breathe` | Breathing animation (3s cycle) |
| `.animate-breathe-fast` | Fast breathing (1s cycle) |
| `.animate-urgent` | Red glow pulse for urgent timer (≤3s) |
| `.animate-toast-in` | Toast entrance animation (slide up, fade in) |
| `.animate-toast-out` | Toast exit animation (slide down, fade out) |

### Game Log Responsive Design

The game log component **must be rendered exactly once** and adapt its layout via CSS breakpoints. This is a core responsive design principle.

**Anti-pattern (DO NOT DO THIS):**
```html
<!-- BAD: Rendering twice with one hidden -->
<div class="lg:hidden"><!-- mobile game log --></div>
<div class="hidden lg:block"><!-- desktop game log --></div>
```

**Correct pattern:**
```html
<!-- GOOD: Single render, CSS adapts layout -->
<div class="game-log">
  <div class="game-log-list">
    <!-- Log entries rendered once -->
  </div>
</div>
```

The `.game-log` class handles the responsive behavior:
- **Mobile/tablet**: Fixed position at bottom of screen, collapsible overlay
- **Desktop (lg+)**: Positioned as sidebar next to main content

This approach:
- Avoids duplicate DOM nodes
- Prevents state synchronization issues
- Reduces bundle size and rendering work
- Follows mobile-first responsive design principles

### Vote Timer Urgency Colors

The voting UI uses color-coded timer display:

| Seconds | Color | Animation |
|---------|-------|-----------|
| ≥6 | White (`text-white`) | None |
| 4-5 | Yellow (`text-yellow-400`) | None |
| ≤3 | Red (`text-red-400`) | `.animate-urgent` (pulsing glow) |

### Breathing Countdown

The dealing phase countdown uses a server-driven breathing animation with CSS transitions:

```gleam
// In view_breathing_countdown(seconds):
// 3 = start inhale (scale-100, opacity-80)
// 2 = peak inhale (scale-125, opacity-100)
// 1 = exhale (scale-100, opacity-70)
```

This uses `transition-all duration-700` to smoothly animate between states, keeping all clients synchronized via the server's `CountdownTick` messages rather than client-side infinite animations

## Mock Routes

The client supports mock routes for UI development without a WebSocket connection. These are client-side only routes parsed using the **modem** package.

### How It Works

1. Client initializes with `modem.initial_uri()` to get the current URL
2. Routes are parsed in `mock_routes.gleam`
3. Mock routes build static state from URL parameters
4. No WebSocket connection is established for mock routes

### Available Mock Routes

| Route | Parameters | Description |
|-------|------------|-------------|
| `/mock/home` | - | Home screen |
| `/mock/create` | `nickname` | Create game screen |
| `/mock/join` | `code`, `nickname`, `error` | Join game screen |
| `/mock/lobby` | `code`, `players`, `ready`, `host` | Lobby with players |
| `/mock/dealing` | `round`, `lives`, `stars`, `cards`, `players`, `countdown` | Dealing phase |
| `/mock/active` | `round`, `lives`, `stars`, `pile`, `cards`, `players` | Active play phase |
| `/mock/pause` | `player`, `played`, `expected`, `cards` | Pause after mistake |
| `/mock/strike` | `votes`, `pending`, `seconds`, `cards`, `voted` | Strike vote |
| `/mock/abandon` | `votes`, `pending`, `seconds`, `voted` | Abandon vote |
| `/mock/end` | `outcome`, `rounds`, `lives`, `stars`, `games` | End game screen |

### Local Development

Start the CSS watcher and mock server in separate terminals:
```bash
# Terminal 1: Watch and rebuild CSS on changes
make css-watch

# Terminal 2: Build client and serve static files
make dev-client
```

Then access mock routes at:
```
http://localhost:3000/mock/{route}?{params}
```

Use mock routes to test UI at different screen widths without needing a real game session.

### Example Usage

```
http://localhost:3000/mock/dealing?round=3&lives=2&stars=1&cards=12,34,56&countdown=2
```

This renders the dealing phase with round 3, 2 lives, 1 star, cards [12, 34, 56], and a countdown overlay showing "2".

**More examples:**
```
# Lobby with 3 players, 1 ready
http://localhost:3000/mock/lobby?players=3&ready=1

# Active play with 4 players, pile at 42
http://localhost:3000/mock/active?round=4&lives=3&stars=2&pile=42&cards=55,68,73,81,94&players=4

# Strike vote in progress
http://localhost:3000/mock/strike?votes=1&pending=2&seconds=12&cards=45,67,89

# End game victory
http://localhost:3000/mock/end?outcome=win&rounds=8&lives=2&stars=0&games=3
```

## Client-Side Behaviors

### Button Click Debounce

Rapid double-clicks on buttons are prevented via a global event capture mechanism in `client.ffi.mjs`. This approach was chosen over alternatives because Lustre's `event.on_click(Msg)` takes message values rather than callbacks, making per-handler wrapping awkward.

**Implementation:**
- Uses document-level event listener in capture phase (fires before Lustre handlers)
- Tracks last click time per DOM element using a `WeakMap` (auto-cleans when elements removed)
- Blocks clicks within 300ms of the previous click on the same `.btn` element
- Calls `stopPropagation()` and `preventDefault()` on debounced clicks

**Why global capture instead of debounce wrapper:**

| Aspect | Debounce wrapper | Global capture |
|--------|------------------|----------------|
| Integration | Need to wrap each handler | Automatic for all `.btn` elements |
| Lustre compatibility | Tricky - Lustre uses `Msg` values, not callbacks | Works without Gleam changes |
| Memory cleanup | Manual (closure lifetime) | Automatic (WeakMap) |

**Code location:** `client/src/client.ffi.mjs`, `setupClickDebounce()` function.

## Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                          CLIENT                                  │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐  │
│  │  View    │───▶│   Msg    │───▶│  Update  │───▶│  Model   │  │
│  └──────────┘    └──────────┘    └──────────┘    └──────────┘  │
│       ▲                               │                          │
│       │                               ▼                          │
│       │                      ┌──────────────┐                   │
│       └──────────────────────│  client.ffi  │                   │
│                              └──────────────┘                   │
│                                     │ ▲                          │
└─────────────────────────────────────│─│──────────────────────────┘
                              WebSocket│ │JSON
                                      ▼ │
┌─────────────────────────────────────│─│──────────────────────────┐
│                          SERVER     │ │                          │
│                              ┌──────────────┐                   │
│                              │   server.gleam│                   │
│                              │  (WebSocket)  │                   │
│                              └──────────────┘                   │
│                                     │ ▲                          │
│                             ServerMsg│ │ServerMessage            │
│                                     ▼ │                          │
│                              ┌──────────────┐                   │
│                              │ game_server  │                   │
│                              │   (Actor)    │                   │
│                              └──────────────┘                   │
│                                     │                            │
│                    ┌────────────────┼────────────────┐          │
│                    ▼                ▼                ▼          │
│              ┌──────────┐    ┌──────────┐    ┌──────────┐      │
│              │ lobbies  │    │  games   │    │connections│      │
│              │  Dict    │    │  Dict    │    │   Dict    │      │
│              └──────────┘    └──────────┘    └──────────┘      │
└─────────────────────────────────────────────────────────────────┘
```

## Key Modules

### shared/protocol.gleam
Defines all types shared between client and server:

```gleam
// Lobby types
type Player { user_id, nickname, is_ready, is_creator, is_connected }  // user_id is UUID, sole identifier
type Lobby { code, players, games_played }

// Game types
type Card = Int  // 1-100
type GameOutcome { Win | Loss | Abandoned }
type Phase { Dealing | ActivePlay | Pause | Strike | AbandonVote | EndGame(GameOutcome) }  // GameSetup is server-side only, not sent to clients
type GamePlayer { user_id, nickname, hand, is_ready, is_connected, last_card_played }  // user_id is UUID, sole identifier
type MistakeInfo { player_nickname, played_card, mistake_cards: List(#(String, Card)) }
type Game { code, host_user_id, games_played, players, current_round, total_rounds, lives, strikes, phase, played_cards, last_mistake, abandon_vote_previous_phase, game_start_timestamp, game_log }

// Game log types
type GameEventType { RoundStarted(round) | CardPlayed(player_nickname, card, autoplayed) | MistakeDiscard(player_nickname, card) | StrikeDiscard(player_nickname, card) | LifeLost(lives_remaining) | StrikeUsed(stars_remaining) | PlayerDisconnectedEvent(nickname) | PlayerReconnectedEvent(nickname) }
type GameEvent { timestamp: Timestamp, event_type: GameEventType }

// Messages (server identifies user from connection's user_id)
type ClientMessage { CreateGame(user_id, nickname) | JoinGame(code, user_id, nickname) | ToggleReady | StartGame | ToggleReadyInGame | PlayCard | InitiateStrikeVote | CastStrikeVote(approve) | InitiateAbandonVote | CastAbandonVote(approve) | LeaveGame | RestartGame }
type ServerMessage { GameCreated(code) | GameJoined | LobbyState | GameStarted | ServerError | GameStateUpdate | CountdownTick | PhaseTransition | StrikeVoteUpdate | AbandonVoteUpdate | PlayerLeft(user_id, new_host_user_id?) | YouLeft | PlayerDisconnected(user_id) | PlayerReconnected(user_id) | GameLogEvent(event) }
```

### shared/game.gleam
Pure functions for game logic (no side effects, easily testable):

```gleam
// Types
type PauseExitAction { AutoPlayThenDeal(user_id, nickname, cards) | CountdownThenActivePlay }

// Functions
fn create_deck() -> List(Card)                    // [1..100]
fn shuffle_deck(deck, random_fn) -> List(Card)    // Fisher-Yates shuffle
fn get_game_config(player_count) -> #(lives, stars, total_rounds)
fn create_game_from_lobby(lobby, shuffle_fn) -> Game  // sets host_user_id from lobby creator, games_played from lobby
fn get_game_player(game, user_id) -> Result(GamePlayer, Nil)  // lookup player by user_id
fn toggle_ready_in_game(game, user_id) -> Result(Game, String)
fn all_players_ready_in_game(game) -> Bool
fn transition_phase(game, phase) -> Game
fn play_card(game, user_id) -> Result(Game, String)  // plays lowest card, detects mistakes
fn deal_round(game, shuffle_fn) -> Game                // deal new round, reset ready states
fn reset_ready_states(game) -> Game                    // reset all players to not ready
fn get_strike_discards(game) -> List(#(String, Card))  // preview discards
fn apply_strike(game) -> Result(Game, String)   // consume star, discard lowest cards
fn game_to_lobby(game) -> Lobby                        // convert game back to lobby for restart
fn phase_to_string(phase) -> String
fn get_auto_play_candidate(game) -> Option(#(user_id, nickname, cards))  // check if only one player has cards
fn apply_auto_play(game, user_id) -> Game              // auto-play all cards for one player
fn get_pause_exit_action(game) -> PauseExitAction      // determine action when exiting Pause phase
```

### server/game_server.gleam and game_server/
OTP Actor managing all server state. The game_server module is split into domain submodules:

**game_server/state.gleam** - Server state types:
```gleam
type ConnectionInfo { subject, user_id, lobby_code, game_code }
type CountdownTimer { game_code, seconds_remaining }
type VoteState { game_code, votes: Dict(String, Bool), pending: List(String) }
type ServerState {
  lobbies: Dict(String, Lobby)
  games: Dict(String, Game)
  connections: Dict(String, ConnectionInfo)
  countdown_timers: Dict(String, CountdownTimer)
  vote_states: Dict(String, VoteState)
  vote_timers: Dict(String, Int)
  self_subject: Option(Subject(ServerMsg))
}
type ServerMsg {
  ClientConnected(subject, user_id)
  ClientDisconnected(user_id)
  ClientMsg(user_id, message)
  CountdownTickMsg(game_code, seconds)
  VoteTickMsg(game_code, seconds)
  AbandonVoteTickMsg(game_code, seconds)
  SetSelfSubject(subject)
}
```

**game_server/helpers.gleam** - Pure helper functions:
- `update_player_lobby` - Update user's lobby code in connection info
- `update_player_game` - Update user's game code in connection info
- `generate_unique_code` - Generate unique lobby/game codes

**game_server/broadcast.gleam** - Message broadcasting:
- `send_message` - Send message to specific user
- `broadcast_message` - Broadcast to all users in a lobby
- `broadcast_lobby_state` - Broadcast current lobby state
- `broadcast_game_message` - Broadcast to all users in a game

**game_server/countdown.gleam** - Countdown timer logic:
- `start_countdown` - Start 3-2-1 countdown for a game

**game_server/event_log.gleam** - Game event logging:
- `create_event` - Create timestamped event
- `log_event` - Log event and broadcast to players

**game_server/handlers/connection.gleam** - Connection handlers:
- `mark_player_disconnected_in_lobby` - Handle lobby disconnection
- `mark_player_disconnected_in_game` - Handle game disconnection
- `mark_player_reconnected_in_game` - Handle game reconnection
- `handle_game_reconnection` - Send current state to reconnecting user

**game_server/handlers/ticks.gleam** - Timer tick handlers:
- `handle_countdown_tick` - Process countdown ticks (3-2-1), transition to ActivePlay
- `handle_vote_tick` - Process strike vote timer ticks
- `handle_abandon_vote_tick` - Process abandon vote timer ticks

**game_server/handlers/vote_initiation.gleam** - Vote initiation handlers:
- `handle_initiate_strike_vote` - Start strike vote from ActivePlay
- `handle_cast_strike_vote` - Process player's strike vote
- `handle_initiate_abandon_vote` - Start abandon vote from Dealing/ActivePlay/Pause
- `handle_cast_abandon_vote` - Process player's abandon vote

**game_server/handlers/strike_vote.gleam** - Strike vote management:
- `start_strike_vote` - Initialize strike vote state and timer
- `cast_strike_vote` - Record player vote, check for resolution
- `resolve_strike_vote` - Apply strike or reject and transition phase
- `handle_post_strike` - Handle phase transitions after successful strike

**game_server/handlers/abandon_vote.gleam** - Abandon vote management:
- `start_abandon_vote` - Initialize abandon vote state and timer
- `cast_abandon_vote` - Record player vote, check for resolution
- `resolve_abandon_vote` - Abandon game or return to previous phase

**game_server/handlers/lobby.gleam** - Lobby management handlers:
- `handle_create_game` - Create new lobby, generate code
- `handle_join_game` - Join existing lobby by code
- `handle_start_game` - Host starts game from lobby

**game_server/handlers/game_play.gleam** - Game play handlers:
- `handle_toggle_ready_in_game` - Toggle player ready state
- `handle_play_card` - Process card play request
- `check_and_perform_auto_play` - Auto-play when single player has cards

**game_server/handlers/end_game.gleam** - End game handlers:
- `handle_leave_game` - Remove player from game
- `handle_restart_game` - Host restarts game from EndGame phase

### server/server.gleam
HTTP server and WebSocket handling:

- Serves static files from `priv/static/`
- Upgrades `/ws` requests to WebSocket
- Parses incoming JSON messages (has its own message type switch — must be updated when adding new ClientMessage variants, in addition to protocol.gleam's decoder)
- Routes to game_server actor
- Forwards server messages to clients

### client/client.gleam
Lustre application (Elm architecture):

```gleam
type Model {
  route: Route                      // Current URL route (for mock routes)
  screen: Screen                    // HomeScreen | CreateScreen | JoinScreen | LobbyScreen | GameScreen
  user_id: String                   // UUID, stored in localStorage
  current_lobby: Option(Lobby)
  current_game: Option(Game)
  countdown: Option(Int)
  vote_status: Option(#(List(#(String, Bool)), List(String), Int))  // strike votes
  abandon_vote_status: Option(#(List(#(String, Bool)), List(String), Int))  // abandon votes
  create_nickname: String           // Form field: nickname for creating game
  join_code: String                 // Form field: game code to join
  join_nickname: String             // Form field: nickname for joining
  error: Option(String)             // Error message to display
  toast: ToastState                 // Toast notification state
  is_reward_guide_open: Bool        // Whether reward guide panel is open
}

type Msg {
  // Navigation
  OnRouteChange(Uri)
  ShowHome | ShowCreateGame | ShowJoinGame
  // Form updates
  UpdateCreateNickname(String) | UpdateJoinCode(String) | UpdateJoinNickname(String)
  // Game actions
  CreateGameClicked | JoinGameClicked | StartGameClicked
  ToggleReadyClicked | ToggleReadyInGameClicked
  PlayCardClicked
  InitiateStrikeClicked | CastStrikeVoteClicked(Bool)
  InitiateAbandonVoteClicked | CastAbandonVoteClicked(Bool)
  LeaveGameClicked | RestartGameClicked
  // UI actions
  CopyShareCode(String) | CopyShareLink(String)
  ToastStartHide | ToastHideComplete
  ToggleRewardGuide
  // Server
  ServerMessage(ServerMessage)
  NoOp
}
```

## Communication Protocol

### Message Flow Examples

**Creating a Game:**
```
Client                          Server
  │                               │
  │─── CreateGame(user_id, nick) ─▶│
  │                               │ create lobby, generate code
  │◀── GameCreated(code) ─────────│
  │◀── LobbyState(lobby) ─────────│
```

**Starting the Game:**
```
Client                          Server
  │                               │
  │─── StartGame ─────────────────▶│
  │                               │ create game from lobby
  │◀── GameStarted ───────────────│
  │◀── GameStateUpdate(game) ─────│
```

**Ready & Countdown:**
```
Client                          Server
  │                               │
  │─── ToggleReadyInGame ─────────▶│
  │◀── GameStateUpdate(game) ─────│ (player now ready)
  │                               │
  │   (when all ready)            │
  │◀── CountdownTick(3) ──────────│
  │◀── CountdownTick(2) ──────────│ (1 second intervals)
  │◀── CountdownTick(1) ──────────│
  │◀── CountdownTick(0) ──────────│
  │◀── PhaseTransition(ActivePlay)│
```

**Strike Vote:**
```
Client                          Server
  │                               │
  │─── InitiateStrikeVote ──▶│
  │◀── PhaseTransition(Strike)│
  │◀── StrikeVoteUpdate ────│ (vote state, 10s timer starts)
  │                               │
  │─── CastStrikeVote(yes) ─▶│ (each player votes)
  │◀── StrikeVoteUpdate ────│ (updated votes, time remaining)
  │                               │
  │   (when all voted OR timeout) │
  │◀── GameStateUpdate(game) ─────│ (cards discarded if approved)
  │◀── PhaseTransition(ActivePlay)│
```

**Abandon Vote:**
```
Client                          Server
  │                               │
  │─── InitiateAbandonVote ───────▶│
  │◀── GameStateUpdate(game) ─────│ (abandon_vote_previous_phase set)
  │◀── PhaseTransition(AbandonVote)│
  │◀── AbandonVoteUpdate ─────────│ (vote state, 10s timer starts)
  │                               │
  │─── CastAbandonVote(yes/no) ───▶│ (each player votes)
  │◀── AbandonVoteUpdate ─────────│ (updated votes, time remaining)
  │                               │
  │   (when all voted OR timeout) │
  │◀── GameStateUpdate(game) ─────│
  │◀── PhaseTransition(...) ──────│ (EndGame(Abandoned) or previous phase)
```

Notes:
- Abandon vote can be initiated from Dealing, ActivePlay, or Pause phases
- Server stores `abandon_vote_previous_phase` to return to on vote failure
- Any single rejection immediately fails the vote (returns to previous phase)
- Timeout auto-approves all pending voters

**Leave Game:**
```
Client                          Server
  │                               │
  │─── LeaveGame ─────────────────▶│
  │◀── YouLeft ────────────────────│ (leaver navigates to HomeScreen)
  │                               │
  │   (to remaining players)      │
  │◀── PlayerLeft(user_id, new_host_user_id?) │
  │◀── GameStateUpdate(game) ─────│ (updated player list, possibly new host_user_id)
```

**Restart Game (host only, EndGame phase):**
```
Client                          Server
  │                               │
  │─── RestartGame ───────────────▶│
  │                               │ validate: host, EndGame, all ready, 2-4 players
  │                               │ game_to_lobby → create_game_from_lobby
  │◀── GameStarted ───────────────│
  │◀── GameStateUpdate(game) ─────│ (Dealing phase, all players ready)
  │◀── CountdownTick(3) ──────────│ (immediate countdown)
  │◀── CountdownTick(2) ──────────│
  │◀── CountdownTick(1) ──────────│
  │◀── CountdownTick(0) ──────────│
  │◀── PhaseTransition(ActivePlay)│
```

Notes:
- Players who haven't voted when the 10-second timer expires default to approve
- Server ignores `InitiateStrikeVote` if already in Strike phase or no stars available
- Server ignores `InitiateAbandonVote` if already in AbandonVote phase or not in allowed phases (Dealing, ActivePlay, Pause)

### JSON Message Format

```javascript
// Client -> Server
{ "type": "create_game", "user_id": "550e8400-e29b-41d4-a716-446655440000", "nickname": "Alice" }
{ "type": "toggle_ready_in_game" }  // server identifies user from connection
{ "type": "initiate_strike_vote" }
{ "type": "cast_strike_vote", "approve": true }
{ "type": "initiate_abandon_vote" }
{ "type": "cast_abandon_vote", "approve": true }
{ "type": "leave_game" }
{ "type": "restart_game" }

// Server -> Client
{ "type": "game_created", "code": "ABC123" }
{ "type": "game_state_update", "game": { "code": "ABC123", "host_user_id": "550e8400-...", "games_played": 0, "players": [...], "abandon_vote_previous_phase": null, ... }}
{ "type": "countdown_tick", "seconds": 3 }
{ "type": "phase_transition", "phase": "active_play" }
{ "type": "phase_transition", "phase": "abandon_vote" }
{ "type": "phase_transition", "phase": { "type": "end_game", "outcome": "win" } }
{ "type": "phase_transition", "phase": { "type": "end_game", "outcome": "abandoned" } }
{ "type": "strike_vote_update", "votes": [{ "user_id": "550e8400-...", "approve": true }], "pending": ["660e8400-..."], "seconds_remaining": 8 }
{ "type": "abandon_vote_update", "votes": [{ "user_id": "550e8400-...", "approve": true }], "pending": ["660e8400-..."], "seconds_remaining": 8 }
{ "type": "player_left", "user_id": "550e8400-...", "new_host_user_id": "660e8400-..." }
{ "type": "you_left" }
{ "type": "player_disconnected", "user_id": "550e8400-..." }
{ "type": "player_reconnected", "user_id": "550e8400-..." }
{ "type": "game_log_event", "event": { "timestamp": 1712345678901, "event_type": "card_played", "player_nickname": "Alice", "card": 42 } }
```

Note: Timestamps are serialized as Unix milliseconds (Int). The `game_start_timestamp` and `game_log` fields are included in `GameStateUpdate`. Incremental `GameLogEvent` messages are broadcast during play.

## State Management

### Server State (Single Source of Truth)
- All game state lives on the server
- Clients receive read-only copies via `GameStateUpdate`
- State mutations happen through message handlers
- Actor model ensures sequential processing (no race conditions)

### Client State (View Model)
- Mirrors server state for rendering
- Adds UI-specific state (form fields, countdown)
- Updated when server messages arrive
- Optimistic updates not used (wait for server confirmation)

### Reconnection Handling
- `user_id` (UUID) stored in localStorage, used as sole identifier everywhere
- On reconnect: client sends `JoinGame` with same `user_id`
- Server recognizes `user_id`, updates connection subject mapping
- No ID migration needed - all state (latencies, votes, buffered cards) keyed by `user_id`
- Client receives current `LobbyState` or `GameStateUpdate`
- If reconnecting during countdown:
  - Player receives current game state and countdown value
  - Proceeds to next phase when countdown completes
- If reconnecting during Strike Phase:
  - Server sends `StrikeVoteUpdate` with current vote state
  - Player's previous vote (if any) is preserved
  - Player can vote if they haven't yet and timer hasn't expired
- If reconnecting during Abandon Vote Phase:
  - Server sends `AbandonVoteUpdate` with current vote state
  - Player's previous vote (if any) is preserved
  - Player can vote if they haven't yet and timer hasn't expired
- If reconnecting during Mistake Resolution:
  - Player's buffered card (if any) is preserved
  - Resolution continues normally when timer expires

## Testing Strategy

### Unit Tests (shared/)
```bash
cd shared && gleam test
```

- `game_test.gleam`: Deck creation, shuffling, dealing, ready toggling, phase transitions
- `lobby_test.gleam`: Player management, reconnection, nickname conflicts
- `protocol_test.gleam`: JSON encoding/decoding round-trips

### Manual Testing Flow
1. Start server: `cd server && gleam run`
2. Open browser to `http://localhost:8000`
3. Create game (Player 1)
4. Join game in another tab (Player 2)
5. Both ready up, creator starts game
6. Verify dealing phase, ready up, countdown, transition

## Phase Transition Rules

The following table defines all phase transitions and whether they include a countdown animation.

| # | From | Condition | To | Countdown? | Notes |
|---|------|-----------|-----|------------|-------|
| 1 | Dealing | All ready | ActivePlay | Yes | 3-2-1 breathing sync |
| 2 | Pause | All ready, single player has cards | Dealing | No | Apply auto-play, advance round |
| 3 | Pause | All ready, multiple players have cards | ActivePlay | Yes | 3-2-1 breathing sync |
| 4 | Strike (success) | Vote approved | Pause | No | Cards discarded, ready states reset |
| 5 | Strike (failure) | Vote rejected | Pause | No | No changes, ready states reset |
| 6 | Mistake | Single player has cards | Dealing | No | Apply auto-play, advance round |
| 7 | Mistake | Multiple players have cards, lives > 0 | Pause | No | Regroup before resuming |
| 8 | EndGame | Host restarts | Dealing | No | Ready states reset |

**Key principles:**
- Countdown (3-2-1 breathing animation) occurs before entering ActivePlay
- Pause phase is used for regrouping after mistakes or strike votes
- When only one player has cards, auto-play is applied and round advances to Dealing
- EndGame restart resets ready states so players can see their new hands before readying up

**Testable decision logic:**
The `game.get_pause_exit_action()` function encapsulates the decision for Rules #2 and #3, returning either `AutoPlayThenDeal` or `CountdownThenActivePlay`. This is unit tested in `shared/test/game_test.gleam`.

## Transition-Time Behavior (Planned)

> **Note:** Latency compensation is documented in `context/remaining-tasks.md` as Task 5. The ping/pong mechanism and latency-based mistake resolution described below are **not yet implemented**.

Certain behaviors need to run at specific points during game state transitions. Future features will include latency measurement (ping/pong) for fair mistake resolution.

### Planned: Latency-Based Mistake Resolution

When implemented, the server will use latency compensation to handle near-simultaneous card plays fairly. See `context/remaining-tasks.md` for the full implementation plan.

## Design Decisions

### Why OTP Actor for Game State?
- Sequential message processing eliminates race conditions
- Built-in supervision for fault tolerance
- Natural fit for Gleam/Erlang ecosystem
- Easy to extend with more actors (e.g., per-game actors)

### Why Shared Code Between Client/Server?
- Type safety: same types on both ends, no drift
- Single source of truth for game logic
- Reduces bugs from mismatched expectations

### Why Server-Driven Countdown?
- All clients see synchronized countdown
- Server maintains authority over game flow
- Handles client disconnection gracefully
- Uses `process.send_after` for timing

### Why Separate Lobby and Game States?
- Clear lifecycle: lobby (pre-game) → game (active play)
- Lobby can be cleaned up after game starts
- Different data structures for different phases
- Easier reasoning about state transitions
