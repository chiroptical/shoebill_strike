# Shoebill Strike

A cooperative card game of patience and timing, built with Gleam.

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

## Testing

```sh
make build
```
