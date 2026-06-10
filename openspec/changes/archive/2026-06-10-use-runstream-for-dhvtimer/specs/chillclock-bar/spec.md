## ADDED Requirements

### Requirement: Connection Configuration Loaded Before Streaming
The widget SHALL load `server_url` (from `~/.config/ChillClock/config.json`, defaulting to `http://localhost:2420`) and `CHILLCLOCK_API_KEY` (from `~/.config/ChillClock/.env`) before establishing any connection to ChillClock, and SHALL NOT attempt to start the SSE stream until both values have been loaded.

#### Scenario: Widget starts with no config loaded yet
- **WHEN** the widget runs its update cycle for the first time and `server_url`/`apiKey` have not yet been loaded
- **THEN** the widget loads them from `config.json` and `.env` before doing anything else, and does not start the SSE stream on this cycle

#### Scenario: Config loaded, stream not yet started
- **WHEN** `server_url` and `apiKey` are loaded and no SSE connection has been started yet
- **THEN** the widget starts a single long-lived connection to `<server_url>/events`

### Requirement: Status Display Updated via Long-Lived SSE Stream
The widget SHALL display timer status by maintaining a single long-lived `noctalia.runStream` connection to ChillClock's `/events` endpoint, updating the bar's text and color from each received status event rather than by periodically polling `/status`.

#### Scenario: SSE event updates bar text and color
- **WHEN** the SSE stream delivers an event whose payload contains `"text"` and `"class"` fields
- **THEN** the widget sets the bar text to the `"text"` value and the bar color to the color mapped from the `"class"` value (`green`/`yellow`/`red`/`white`), falling back to `#ffffff` for an unrecognized class

#### Scenario: No status received yet
- **WHEN** the SSE stream has not yet delivered its first event since the connection was started
- **THEN** the bar displays `"0:00"` with color `#888888`, matching the prior no-data display

### Requirement: Stream Reconnection on Silence
The widget SHALL detect when the SSE connection has gone silent for longer than a configured timeout and SHALL re-establish the connection, so that the bar does not remain stuck on stale data indefinitely after a server restart or network interruption.

#### Scenario: No events received within the timeout
- **WHEN** no SSE event has been received for longer than the configured silence timeout since the connection was established (or since the last received event)
- **THEN** the widget re-establishes the `/events` connection

#### Scenario: Reconnected stream resumes updates
- **WHEN** a new `/events` connection is established after a reconnect
- **THEN** subsequent events from the new connection update the bar's text and color as described in "Status Display Updated via Long-Lived SSE Stream"

### Requirement: Timer Control via Click Handlers
The widget SHALL allow the user to control ChillClock timers via mouse clicks, issuing one-shot HTTP requests independent of the status stream: left-click toggles the configured default timer, right-click toggles the other timer, and middle-click switches the active timer.

#### Scenario: Left click toggles the default timer
- **WHEN** the user left-clicks the widget and `server_url` is loaded
- **THEN** the widget issues a `POST` to `/toggle?timer=<default_timer>`

#### Scenario: Right click toggles the non-default timer
- **WHEN** the user right-clicks the widget and `server_url` is loaded
- **THEN** the widget issues a `POST` to `/toggle?timer=<other_timer>`, where `<other_timer>` is `2` if `default_timer` is `1`, and `1` otherwise

#### Scenario: Middle click switches the active timer
- **WHEN** the user middle-clicks the widget and `server_url` is loaded
- **THEN** the widget issues a `POST` to `/switch`

#### Scenario: Click before config is loaded
- **WHEN** the user clicks the widget before `server_url` has been loaded
- **THEN** the widget takes no action
