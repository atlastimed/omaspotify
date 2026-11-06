//! Spotify Soloist adapter for the existing private socket and MPRIS interfaces.
//! Only the runtime helper sees the API key. This module consumes public events.
use std::{
    collections::VecDeque,
    path::PathBuf,
    process::Stdio,
    time::{Duration, Instant},
};

use anyhow::{Context, Result, bail};
use futures_util::{SinkExt, StreamExt};
use serde_json::{Value, json};
use tokio::{
    process::Command as Process,
    sync::{mpsc, oneshot, watch},
};
use tokio_tungstenite::{
    connect_async_with_config,
    tungstenite::{Message, protocol::WebSocketConfig},
};

use crate::{
    config::BackendConfig,
    engine::{EngineRequest, EngineRuntime},
    protocol::{
        BackendState, Command, Lifecycle, PlaybackStatus, ProtocolError, RepeatMode, Track,
    },
    state::StateStore,
};

fn state_dir() -> PathBuf {
    std::env::var_os("XDG_STATE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".local/state")
        })
        .join("omaspotify/soloist")
}

pub async fn start(config: BackendConfig, state: StateStore) -> Result<EngineRuntime> {
    let executable = std::env::current_exe()?;
    let helper = executable
        .parent()
        .context("backend has no runtime directory")?
        .join("soloist-runtime.py");
    let mut child = Process::new("/usr/bin/python3")
        .arg(helper)
        .arg("run")
        .arg(config.device_name)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .kill_on_drop(true)
        .spawn()?;
    let directory = state_dir();
    let deadline = Instant::now() + Duration::from_secs(90);
    let ws_config = WebSocketConfig::default()
        .max_message_size(Some(2 * 1024 * 1024))
        .max_frame_size(Some(2 * 1024 * 1024));
    let socket = loop {
        if child.try_wait()?.is_some() {
            bail!("Soloist stopped before its local API became ready")
        }
        if let (Ok(address), Ok(port)) = (
            std::fs::read_to_string(directory.join("ws.addr")),
            std::fs::read_to_string(directory.join("ws.port")),
        ) {
            if address.trim() == "127.0.0.1" {
                if let Ok(port) = port.trim().parse::<u16>() {
                    if port > 0 {
                        // The previous receiver may have left its endpoint files behind.
                        // Retry both discovery and connection until the new receiver is ready.
                        if let Ok(Ok((socket, _))) = tokio::time::timeout(
                            Duration::from_secs(2),
                            connect_async_with_config(
                                format!("ws://127.0.0.1:{port}"),
                                Some(ws_config),
                                false,
                            ),
                        )
                        .await
                        {
                            break socket;
                        }
                    }
                }
            }
        }
        if Instant::now() >= deadline {
            bail!("Soloist did not open its loopback API")
        }
        tokio::time::sleep(Duration::from_millis(200)).await;
    };
    state.update(|s| {
        s.engine = "soloist".into();
        s.lifecycle = Lifecycle::Ready;
        true
    });
    let (commands, receiver) = mpsc::channel(64);
    let (shutdown, shutdown_rx) = watch::channel(false);
    let (done_tx, done) = oneshot::channel();
    tokio::spawn(async move {
        let result = drive(socket, receiver, shutdown_rx, state, directory).await;
        let _ = child.kill().await;
        let _ = child.wait().await;
        let _ = done_tx.send(result);
    });
    Ok(EngineRuntime {
        commands,
        shutdown,
        done,
    })
}

fn command(name: &str) -> Value {
    json!({"type":"command", "command": name})
}

fn commands_for(input: Command, playing: bool) -> Result<VecDeque<Value>, ProtocolError> {
    let mut result = VecDeque::new();
    let value = match input {
        Command::Activate => command("activate"),
        Command::Play => command("play"),
        Command::Pause | Command::Stop => command("pause"),
        Command::Toggle => command(if playing { "pause" } else { "play" }),
        Command::Next => command("skip_next"),
        Command::Previous => command("skip_prev"),
        Command::Seek { position_ms } => {
            json!({"type":"command","command":"seek","position_ms":position_ms})
        }
        Command::SetVolume { volume } => {
            json!({"type":"command","command":"set_volume","volume":(u32::from(volume)*100+32767)/65535})
        }
        Command::SetShuffle { enabled } => {
            json!({"type":"command","command":"set_shuffle","enabled":enabled})
        }
        Command::SetRepeat { mode } => {
            result
                .push_back(json!({"type":"command","command":"set_repeat_track","enabled":false}));
            result.push_back(json!({"type":"command","command":"set_repeat_context","enabled":mode == RepeatMode::Context}));
            if mode == RepeatMode::Track {
                result.push_back(
                    json!({"type":"command","command":"set_repeat_track","enabled":true}),
                );
            }
            return Ok(result);
        }
        Command::AddToQueue { uri } => json!({"type":"command","command":"add_to_queue","uri":uri}),
        Command::Load {
            context_uri,
            uris,
            offset_uri,
            offset_index,
            position_ms,
            play,
        } => {
            // Soloist's local API cannot select an offset within a context or load a list.
            // Report this explicitly so Service preserves the playlist via the Web API.
            if offset_uri.is_some()
                || offset_index.is_some()
                || uris.len() > 1
                || position_ms != 0
                || !play
            {
                return Err(ProtocolError::new(
                    "web_api_required",
                    "This playback context requires Spotify Web API control",
                ));
            }
            let uri = context_uri
                .or_else(|| uris.into_iter().next())
                .filter(|uri| valid_uri(uri))
                .ok_or_else(|| {
                    ProtocolError::new("invalid_uri", "A playable Spotify URI is required")
                })?;
            json!({"type":"command","command":"play","uri":uri})
        }
        _ => {
            return Err(ProtocolError::new(
                "unsupported",
                "Unsupported local playback command",
            ));
        }
    };
    result.push_back(value);
    Ok(result)
}

fn valid_uri(uri: &str) -> bool {
    let fields: Vec<_> = uri.split(':').collect();
    fields.len() == 3
        && fields[0] == "spotify"
        && ["track", "album", "playlist", "episode", "artist", "show"].contains(&fields[1])
        && !fields[2].is_empty()
        && fields[2].len() <= 128
        && fields[2].chars().all(|c| c.is_ascii_alphanumeric())
}

fn string(value: &Value) -> String {
    value.as_str().unwrap_or("").chars().take(2048).collect()
}
fn track(entity: &Value) -> Option<Track> {
    let uri = string(&entity["uri"]);
    if !valid_uri(&uri) {
        return None;
    }
    let d = &entity["decorations"];
    Some(Track {
        uri,
        title: string(&d["identity"]["name"]),
        artists: d["creators"]
            .as_array()
            .map(|a| {
                a.iter()
                    .take(32)
                    .map(|c| string(&c["entity"]["decorations"]["identity"]["name"]))
                    .collect()
            })
            .unwrap_or_default(),
        album: string(&d["parent"]["entity"]["decorations"]["identity"]["name"]),
        art_url: d["visual_identity"]["cover"]
            .as_array()
            .and_then(|a| a.last())
            .map(|c| string(&c["url"]))
            .unwrap_or_default(),
        duration_ms: d["playback"]["duration_ms"]
            .as_u64()
            .unwrap_or(0)
            .min(u64::from(u32::MAX)) as u32,
        item_type: string(&entity["entity_type"]),
    })
}

#[derive(Default)]
struct Position {
    ms: u32,
    received: Option<Instant>,
    speed: f64,
}
impl Position {
    fn sync(&mut self, value: &Value) {
        self.ms = value["position_ms"]
            .as_u64()
            .unwrap_or(0)
            .min(u64::from(u32::MAX)) as u32;
        self.speed = value["speed"].as_f64().unwrap_or(0.0).clamp(0.0, 4.0);
        // Use a monotonic anchor, correcting for bounded transport delay only.
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis() as u64;
        let delay = value["timestamp_ms"]
            .as_u64()
            .map(|t| now.saturating_sub(t).min(5000))
            .unwrap_or(0);
        self.ms = self.ms.saturating_add((delay as f64 * self.speed) as u32);
        self.received = Some(Instant::now());
    }
    fn value(&self, s: &BackendState) -> u32 {
        let delta = if s.playback == PlaybackStatus::Playing {
            self.received
                .map(|t| (t.elapsed().as_millis() as f64 * self.speed) as u32)
                .unwrap_or(0)
        } else {
            0
        };
        self.ms
            .saturating_add(delta)
            .min(s.track.as_ref().map_or(u32::MAX, |t| t.duration_ms))
    }
}

fn apply_event(s: &mut BackendState, event: &Value, position: &mut Position) -> bool {
    let kind = event["type"].as_str().unwrap_or("");
    if kind == "auth_state" {
        s.session_connected = event["logged_in"] == true;
        if !s.session_connected {
            s.track = None;
            s.playback = PlaybackStatus::Stopped;
            s.position_ms = 0;
            *position = Position::default();
        }
    }
    if ["playback_state", "track_changed"].contains(&kind) {
        s.track = track(&event["item"]);
        if kind == "track_changed" {
            // The following position_sync is authoritative. Until it arrives,
            // do not display the previous song's position on the new track.
            *position = Position::default();
            s.position_ms = 0;
        }
    }
    if ["playback_state", "playback_changed"].contains(&kind) {
        position.ms = position.value(s);
        position.received = Some(Instant::now());
        s.playback = match event["status"].as_str() {
            Some("playing") => PlaybackStatus::Playing,
            Some("paused") => PlaybackStatus::Paused,
            Some("buffering") => PlaybackStatus::Loading,
            _ => PlaybackStatus::Stopped,
        };
        if kind == "playback_changed" {
            position.speed = if s.playback == PlaybackStatus::Playing {
                1.0
            } else {
                0.0
            };
            s.position_ms = position.ms;
        }
    }
    if ["playback_state", "position_sync"].contains(&kind) {
        position.sync(&event["position"]);
        s.position_ms = position.value(s);
        s.seek_sequence = s.seek_sequence.wrapping_add(1);
    }
    if ["playback_state", "volume_changed"].contains(&kind) {
        s.volume = (event["volume"].as_f64().unwrap_or(0.0).clamp(0.0, 100.0) * 65535.0 / 100.0)
            .round() as u16;
    }
    if ["playback_state", "options_changed"].contains(&kind) {
        s.shuffle = event["options"]["shuffle"] == true;
        s.repeat = match event["options"]["repeat"].as_str() {
            Some("context") => RepeatMode::Context,
            Some("track") => RepeatMode::Track,
            _ => RepeatMode::Off,
        };
    }
    if ["device_changed", "auth_state", "playback_state"].contains(&kind)
        && event["is_active"] == false
    {
        s.track = None;
        s.playback = PlaybackStatus::Stopped;
        s.position_ms = 0;
        *position = Position::default();
    }
    [
        "auth_state",
        "playback_state",
        "track_changed",
        "playback_changed",
        "position_sync",
        "volume_changed",
        "options_changed",
        "device_changed",
    ]
    .contains(&kind)
}

struct Pending {
    messages: VecDeque<Value>,
    reply: Option<oneshot::Sender<Result<Value, ProtocolError>>>,
    deadline: Instant,
}

async fn drive<S>(
    mut socket: tokio_tungstenite::WebSocketStream<S>,
    mut commands: mpsc::Receiver<EngineRequest>,
    mut shutdown: watch::Receiver<bool>,
    state: StateStore,
    directory: PathBuf,
) -> Result<()>
where
    S: tokio::io::AsyncRead + tokio::io::AsyncWrite + Unpin,
{
    let mut position = Position::default();
    let mut pending: Option<Pending> = None;
    let mut tick = tokio::time::interval(Duration::from_millis(250));
    loop {
        tokio::select! {
            _ = shutdown.changed() => { let _ = socket.close(None).await; return Ok(()) },
            request = commands.recv(), if pending.is_none() => {
                let Some(request) = request else { return Ok(()) };
                let result = if state.with(|s| s.session_connected) {
                    commands_for(request.command, state.with(|s| s.playback == PlaybackStatus::Playing))
                } else { Err(ProtocolError::new("not_paired", "Select OmaSpotify in the official Spotify app to pair Soloist")) };
                match result {
                    Ok(messages) => {
                        socket.send(Message::Text(messages[0].to_string().into())).await?;
                        pending = Some(Pending { messages, reply: request.reply, deadline: Instant::now()+Duration::from_secs(5) });
                    }
                    Err(error) => { if let Some(reply) = request.reply { let _ = reply.send(Err(error)); } }
                }
            }
            message = socket.next() => {
                let Some(message) = message else { bail!("Soloist's local API disconnected") };
                match message? {
                    Message::Text(raw) => {
                        let Ok(event) = serde_json::from_str::<Value>(&raw) else { continue };
                        if event["type"] == "command_result" {
                            if let Some(mut command) = pending.take() {
                                if event["command"] != command.messages[0]["command"] { bail!("Unexpected Soloist command response") }
                                command.messages.pop_front();
                                if let Some(next) = command.messages.front() {
                                    socket.send(Message::Text(next.to_string().into())).await?;
                                    command.deadline = Instant::now()+Duration::from_secs(5);
                                    pending = Some(command);
                                } else if let Some(reply) = command.reply { let _ = reply.send(Ok(json!({}))); }
                            }
                        } else if event["type"] == "error" {
                            if let Some(command) = pending.take() {
                                if let Some(reply) = command.reply { let _ = reply.send(Err(ProtocolError::new("soloist_error", "Soloist declined the playback command"))); }
                            }
                        } else {
                            state.update(|s| apply_event(s, &event, &mut position));
                            if event["type"] == "auth_state" {
                                if event["logged_in"] == true { let _ = std::fs::write(directory.join("paired"), "1\n"); }
                                else { let _ = std::fs::remove_file(directory.join("paired")); }
                            }
                        }
                    }
                    Message::Ping(bytes) => socket.send(Message::Pong(bytes)).await?,
                    Message::Close(_) => bail!("Soloist's local API closed"),
                    _ => {}
                }
            }
            _ = tick.tick() => {
                if pending.as_ref().is_some_and(|p| Instant::now() >= p.deadline) {
                    if let Some(p) = pending.take() { if let Some(reply) = p.reply { let _ = reply.send(Err(ProtocolError::new("timeout", "Soloist did not acknowledge the playback command"))); } }
                    bail!("Soloist command timed out")
                }
                state.update(|s| { let value = position.value(s); if value / 1000 == s.position_ms / 1000 { return false } s.position_ms = value; true });
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn track_change_does_not_inherit_previous_position() {
        let mut s = BackendState::default();
        let mut p = Position::default();
        apply_event(
            &mut s,
            &json!({"type":"playback_state", "status":"playing",
            "position":{"position_ms":90000,"speed":1}}),
            &mut p,
        );
        apply_event(
            &mut s,
            &json!({"type":"track_changed", "item":null}),
            &mut p,
        );
        assert_eq!(s.position_ms, 0);
        assert_eq!(p.value(&s), 0);
        apply_event(
            &mut s,
            &json!({"type":"position_sync",
            "position":{"position_ms":1200,"speed":1}}),
            &mut p,
        );
        assert!(p.value(&s) >= 1200);
    }
    #[test]
    fn context_offsets_explicitly_use_web_api() {
        let error = commands_for(
            Command::Load {
                context_uri: Some("spotify:playlist:abc".into()),
                uris: vec![],
                offset_uri: Some("spotify:track:clicked".into()),
                offset_index: None,
                position_ms: 0,
                play: true,
            },
            false,
        )
        .unwrap_err();
        assert_eq!(error.code, "web_api_required");
        assert_eq!(
            commands_for(Command::SetVolume { volume: u16::MAX }, false).unwrap()[0]["volume"],
            100
        );
        assert_eq!(
            commands_for(Command::Toggle, true).unwrap()[0]["command"],
            "pause"
        );
    }
    #[test]
    fn events_update_metadata_and_clear_on_device_transfer() {
        let mut s = BackendState::default();
        let mut p = Position::default();
        apply_event(
            &mut s,
            &json!({"type":"auth_state","logged_in":true,"is_active":true}),
            &mut p,
        );
        apply_event(
            &mut s,
            &json!({"type":"playback_state","status":"playing","is_active":true,
            "item":{"uri":"spotify:track:abc","entity_type":"track","decorations":{"identity":{"name":"Song"},"playback":{"duration_ms":210000},"creators":[{"entity":{"decorations":{"identity":{"name":"Artist"}}}}]}},
            "position":{"position_ms":12000,"speed":1},"volume":50,"options":{"shuffle":true,"repeat":"context"}}),
            &mut p,
        );
        assert_eq!(s.track.as_ref().unwrap().title, "Song");
        assert_eq!(s.track.as_ref().unwrap().artists, vec!["Artist"]);
        assert_eq!(s.position_ms, 12000);
        assert_eq!(s.volume, 32768);
        assert!(s.shuffle);
        apply_event(
            &mut s,
            &json!({"type":"device_changed","is_active":false}),
            &mut p,
        );
        assert!(s.track.is_none());
        assert_eq!(s.playback, PlaybackStatus::Stopped);
        assert_eq!(p.value(&s), 0);
    }

    #[tokio::test]
    async fn socket_commands_wait_for_ack_and_publish_real_state() {
        use tokio_tungstenite::tungstenite::protocol::Role;
        let (left, right) = tokio::io::duplex(65536);
        let client =
            tokio_tungstenite::WebSocketStream::from_raw_socket(left, Role::Client, None).await;
        let mut server =
            tokio_tungstenite::WebSocketStream::from_raw_socket(right, Role::Server, None).await;
        let (tx, rx) = mpsc::channel(4);
        let (stop, stopped) = watch::channel(false);
        let state = StateStore::new(BackendState::default());
        let task = tokio::spawn(drive(
            client,
            rx,
            stopped,
            state.clone(),
            PathBuf::from("/nonexistent/soloist-fixture"),
        ));
        server
            .send(Message::Text(
                json!({"type":"auth_state","logged_in":true,"is_active":true})
                    .to_string()
                    .into(),
            ))
            .await
            .unwrap();
        let mut states = state.subscribe();
        tokio::time::timeout(Duration::from_secs(1), async {
            while !states.borrow_and_update().session_connected {
                states.changed().await.unwrap();
            }
        })
        .await
        .unwrap();
        let (reply, result) = oneshot::channel();
        tx.send(EngineRequest {
            command: Command::SetRepeat {
                mode: RepeatMode::Track,
            },
            reply: Some(reply),
        })
        .await
        .unwrap();
        for (name, enabled) in [
            ("set_repeat_track", false),
            ("set_repeat_context", false),
            ("set_repeat_track", true),
        ] {
            let message = tokio::time::timeout(Duration::from_secs(1), server.next())
                .await
                .unwrap()
                .unwrap()
                .unwrap();
            let value: Value = serde_json::from_str(message.to_text().unwrap()).unwrap();
            assert_eq!(value["command"], name);
            assert_eq!(value["enabled"], enabled);
            server
                .send(Message::Text(
                    json!({"type":"command_result","command":name})
                        .to_string()
                        .into(),
                ))
                .await
                .unwrap();
        }
        assert!(result.await.unwrap().is_ok());
        server
            .send(Message::Text(
                json!({"type":"volume_changed","volume":25})
                    .to_string()
                    .into(),
            ))
            .await
            .unwrap();
        tokio::time::timeout(Duration::from_secs(1), async {
            while states.borrow_and_update().volume != 16384 {
                states.changed().await.unwrap();
            }
        })
        .await
        .unwrap();
        stop.send(true).unwrap();
        task.await.unwrap().unwrap();
    }
}
