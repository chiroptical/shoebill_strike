# Shoebill Strike

A cooperative card game of patience and timing, built with Gleam.

All game icons came from https://game-icons.net/

This was an experiment for me. My work is encouraging more LLM usage and here is
my practice. I built this using Claude Opus 4.5, the context was mostly managed
and iterated on, pretty diligently, at the beginning. Towards the end I started
to get more lazy and I should probably go through my context more carefully
again.

There is nothing interesting architecturally here. We use a single game
actor which is keyed on a generated code for a lobby. The game is deployed at
https://shoebill.app and can't scale horizontally. I'd need a mechanism to pin
users to instances based on their game code.

## Local Development

### Docker

```sh
docker build -t shoebill-strike .
docker run -p 8000:8000 shoebill-strike
```

### Full Server (with WebSocket)

Build and run the complete application:

```sh
./build.sh
cd server && gleam run
# Open http://localhost:8000
```

### Mock Route Development (UI only)

For iterating on UI styling without the server:

```sh
# Terminal 1: Watch CSS changes
make css-watch

# Terminal 2: Serve static files
make dev-client
# Open http://localhost:3000
```

### Available Mock Routes

Mock routes render UI with static state from URL parameters:

- `/mock/home` - Home screen
- `/mock/create` - Create game screen
- `/mock/join?error=invalid` - Join screen with optional error
- `/mock/lobby?players=3&ready=2` - Lobby with players
- `/mock/dealing?round=2&lives=3&stars=1&cards=10,50,90` - Dealing phase
- `/mock/active?pile=25&cards=30,60` - Active play phase
- `/mock/pause?player=Alice&played=42&expected=38` - Pause after mistake
- `/mock/strike?votes=1&pending=1&seconds=8` - Strike vote
- `/mock/abandon?votes=1&pending=1&seconds=8` - Abandon vote
- `/mock/end?outcome=win&rounds=8` - End game screen

## Test

```sh
make build
```
