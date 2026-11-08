//! Spotify Soloist adapter for the existing private socket and MPRIS interfaces.
//! Only the runtime helper sees the API key. This module consumes public events.
use std::{
    collections::VecDeque,
    path::{Path, PathBuf},
    process::{ExitStatus, Stdio},
    time::{Duration, Instant},
};

use anyhow::{Context, Result, bail};
use futures_util::{SinkExt, StreamExt};
use serde_json::{Value, json};
use tokio::{
    process::{Child, Command as Process},
    sync::{mpsc, oneshot, watch},
};
use tokio_tungstenite::{
    connect_async_with_config,
    tungstenite::{Message, protocol::WebSocketConfig},
};

use crate::{
    config::BackendConfig,
    engine::{EngineRequest, EngineRuntime},
    failure::Failure,
    protocol::{
        BackendState, Command, Lifecycle, PlaybackStatus, ProtocolError, RepeatMode, Track,
    },
    state::StateStore,
};

/// A position change smaller than this is the clock settling, not a seek.
const SEEK_JUMP_MS: u32 = 1500;
/// How long a play or pause we sent decides what the next toggle means.
const TOGGLE_INTENT_WINDOW: Duration = Duration::from_secs(2);
/// A command's acknowledgement deadline.
const COMMAND_TIMEOUT: Duration = Duration::from_secs(5);
const STOP_GRACE: Duration = Duration::from_millis(1500);

fn state_dir() -> PathBuf {
    std::env::var_os("XDG_STATE_HOME")
        .map(PathBuf::from)
        .filter(|path| path.is_absolute())
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
    let directory = state_dir();
    // Left behind by a crash, these could point at whatever now owns that port.
    for endpoint in ["ws.addr", "ws.port"] {
        let _ = std::fs::remove_file(directory.join(endpoint));
    }
    let mut process = Process::new("/usr/bin/python3");
    process
        .arg(helper)
        .arg("run")
        .arg(config.device_name)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        // The helper reports its own failures here, and silences Soloist before handing over.
        .stderr(Stdio::inherit())
        .kill_on_drop(true);
    // SAFETY: prctl only sets a flag on the new process and is async-signal-safe.
    unsafe {
        process.pre_exec(|| {
            libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM);
            Ok(())
        });
    }
    let mut child = process.spawn()?;
    let deadline = Instant::now() + Duration::from_secs(90);
    let ws_config = WebSocketConfig::default()
        .max_message_size(Some(2 * 1024 * 1024))
        .max_frame_size(Some(2 * 1024 * 1024));
    let socket = loop {
        if let Some(status) = child.try_wait()? {
            if let Some(failure) = failure_for_exit(status) {
                return Err(failure.into());
            }
            bail!("Soloist stopped before its local API became ready ({status})")
        }
        if let (Ok(address), Ok(port)) = (
            std::fs::read_to_string(directory.join("ws.addr")),
            std::fs::read_to_string(directory.join("ws.port")),
        ) && address.trim() == "127.0.0.1"
            && let Ok(port) = port.trim().parse::<u16>()
            && port > 0
        {
            // The previous receiver may have left its endpoint files behind.
            // Retry both discovery and connection until the new receiver is ready.
            if let Ok(Ok((socket, _))) = tokio::time::timeout(
                Duration::from_secs(2),
                connect_async_with_config(format!("ws://127.0.0.1:{port}"), Some(ws_config), false),
            )
            .await
            {
                break socket;
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
        // If the API went away, Soloist's exit code may say why.
        let failed_with = match &result {
            Err(_) => tokio::time::timeout(Duration::from_millis(500), child.wait())
                .await
                .ok()
                .and_then(Result::ok)
                .and_then(failure_for_exit),
            Ok(()) => None,
        };
        stop_child(&mut child).await;
        let _ = done_tx.send(match failed_with {
            Some(failure) => Err(failure.into()),
            None => result,
        });
    });
    Ok(EngineRuntime {
        commands,
        shutdown,
        done,
    })
}

/// The helper exits 77 for a missing key and 75 for a build it cannot renew;
/// Soloist itself exits 10 when its build has expired. Restarting helps none of them.
fn failure_for_exit(status: ExitStatus) -> Option<Failure> {
    match status.code() {
        Some(77) => Some(Failure::MissingCredentials),
        Some(75 | 10) => Some(Failure::SoloistExpired),
        _ => None,
    }
}

/// Lets Soloist remove its endpoint files and shut its session down cleanly.
async fn stop_child(child: &mut Child) {
    if matches!(child.try_wait(), Ok(Some(_))) {
        return;
    }
    if let Some(pid) = child.id().and_then(|pid| i32::try_from(pid).ok()) {
        // SAFETY: kill has no memory effects, and tokio has not reaped this pid.
        unsafe { libc::kill(pid, libc::SIGTERM) };
    }
    if tokio::time::timeout(STOP_GRACE, child.wait())
        .await
        .is_err()
    {
        let _ = child.kill().await;
    }
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
            .map(|covers| cover_url(covers))
            .unwrap_or_default(),
        duration_ms: d["playback"]["duration_ms"]
            .as_u64()
            .unwrap_or(0)
            .min(u64::from(u32::MAX)) as u32,
        item_type: string(&entity["entity_type"]),
    })
}

/// The largest cover, by name because the order is not documented.
fn cover_url(covers: &[Value]) -> String {
    ["xlarge", "large", "default", "small"]
        .iter()
        .find_map(|size| covers.iter().find(|cover| cover["size"] == *size))
        .or_else(|| covers.last())
        .map(|cover| string(&cover["url"]))
        .filter(|url| url.starts_with("https://"))
        .unwrap_or_default()
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
        // A duration of 0 means it is not known yet, not that the song is over.
        let duration = s
            .track
            .as_ref()
            .map(|t| t.duration_ms)
            .filter(|ms| *ms > 0)
            .unwrap_or(u32::MAX);
        self.ms.saturating_add(delta).min(duration)
    }

    fn advancing(&self, s: &BackendState) -> bool {
        s.playback == PlaybackStatus::Playing && self.speed > 0.0
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
            // Buffering retains playback intent. Reporting it as Stopped made
            // a pause clicked immediately after seeking toggle back to Play.
            Some("playing" | "buffering") => PlaybackStatus::Playing,
            Some("paused") => PlaybackStatus::Paused,
            _ => PlaybackStatus::Stopped,
        };
        if kind == "playback_changed" {
            position.speed = if event["status"] == "playing" {
                1.0
            } else {
                0.0
            };
            s.position_ms = position.ms;
        }
    }
    if ["playback_state", "position_sync"].contains(&kind) && event["position"].is_object() {
        let expected = position.received.is_some().then(|| position.value(s));
        position.sync(&event["position"]);
        s.position_ms = position.value(s);
        // Soloist re-anchors position constantly; only a real jump is a seek.
        if expected.is_none_or(|ms| ms.abs_diff(s.position_ms) > SEEK_JUMP_MS) {
            s.seek_sequence = s.seek_sequence.wrapping_add(1);
        }
    }
    if ["playback_state", "volume_changed"].contains(&kind)
        && let Some(volume) = event["volume"].as_f64()
    {
        s.volume = (volume.clamp(0.0, 100.0) * 65535.0 / 100.0).round() as u16;
    }
    if ["playback_state", "options_changed"].contains(&kind) {
        if let Some(shuffle) = event["options"]["shuffle"].as_bool() {
            s.shuffle = shuffle;
        }
        match event["options"]["repeat"].as_str() {
            Some("context") => s.repeat = RepeatMode::Context,
            Some("track") => s.repeat = RepeatMode::Track,
            Some("off") => s.repeat = RepeatMode::Off,
            _ => {}
        }
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

async fn persist_volume(directory: &Path, volume: u16) -> std::io::Result<()> {
    use tokio::io::AsyncWriteExt;
    let temporary = directory.join("volume.tmp");
    let mut file = tokio::fs::OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(0o600)
        .open(&temporary)
        .await?;
    let percent = (u32::from(volume) * 100 + 32767) / 65535;
    file.write_all(format!("{percent}\n").as_bytes()).await?;
    file.flush().await?;
    drop(file);
    tokio::fs::rename(temporary, directory.join("volume")).await
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
    let mut toggle_intent: Option<(bool, Instant)> = None;
    let mut logged_in: Option<bool> = None;
    let mut device_active = false;
    loop {
        // Nothing to do while paused or idle, so the backend sleeps until spoken to.
        let wake = next_wakeup(
            pending.as_ref().map(|p| p.deadline),
            state.with(|s| position.advancing(s).then(|| position.value(s))),
        );
        tokio::select! {
            _ = shutdown.changed() => { let _ = socket.close(None).await; return Ok(()) },
            request = commands.recv(), if pending.is_none() => {
                let Some(request) = request else { return Ok(()) };
                let result = if state.with(|s| s.session_connected) {
                    // Soloist acknowledges before state changes, so a fast second
                    // toggle has to go by what we last asked for.
                    let playing = toggle_intent
                        .filter(|(_, at)| at.elapsed() < TOGGLE_INTENT_WINDOW)
                        .map_or_else(
                            || state.with(|s| s.playback == PlaybackStatus::Playing),
                            |(playing, _)| playing,
                        );
                    commands_for(request.command, playing)
                } else { Err(ProtocolError::new("not_paired", "Select OmaSpotify in the official Spotify app to pair Soloist")) };
                match result {
                    Ok(messages) => {
                        toggle_intent = match messages[0]["command"].as_str() {
                            Some("play") => Some((true, Instant::now())),
                            Some("pause") => Some((false, Instant::now())),
                            _ => toggle_intent,
                        };
                        socket.send(Message::Text(messages[0].to_string().into())).await?;
                        pending = Some(Pending { messages, reply: request.reply, deadline: Instant::now() + COMMAND_TIMEOUT });
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
                                // Not ours, perhaps another client's. The deadline still applies.
                                if event["command"] != command.messages[0]["command"] {
                                    log::warn!("Ignoring an unexpected Soloist command response");
                                    pending = Some(command);
                                    continue;
                                }
                                command.messages.pop_front();
                                if let Some(next) = command.messages.front() {
                                    socket.send(Message::Text(next.to_string().into())).await?;
                                    command.deadline = Instant::now() + COMMAND_TIMEOUT;
                                    pending = Some(command);
                                } else if let Some(reply) = command.reply { let _ = reply.send(Ok(json!({}))); }
                            }
                        } else if event["type"] == "error" {
                            toggle_intent = None;
                            if let Some(command) = pending.take()
                                && let Some(reply) = command.reply { let _ = reply.send(Err(ProtocolError::new("soloist_error", "Soloist declined the playback command"))); }
                        } else {
                            let kind = event["type"].as_str().unwrap_or("");
                            if ["playback_changed", "playback_state"].contains(&kind) {
                                toggle_intent = None;
                            }
                            state.update(|s| apply_event(s, &event, &mut position));
                            if kind == "volume_changed"
                                && event["volume"].is_number()
                                && persist_volume(&directory, state.with(|s| s.volume)).await.is_err() {
                                log::warn!("Could not save Soloist volume");
                            }
                            // A snapshot only comes unprompted on connect, so anything
                            // that happens later has to ask for one.
                            let mut stale = false;
                            if kind == "auth_state" {
                                let now_logged_in = event["logged_in"] == true;
                                stale = logged_in == Some(false) && now_logged_in;
                                logged_in = Some(now_logged_in);
                                // Pairing outlives a session; only clearing it in Settings ends it.
                                if now_logged_in { let _ = std::fs::write(directory.join("paired"), "1\n"); }
                            }
                            if let Some(active) = event["is_active"].as_bool() {
                                stale |= kind == "device_changed" && active && !device_active;
                                device_active = active;
                            }
                            if stale {
                                socket.send(Message::Text(command("get_state").to_string().into())).await?;
                            }
                        }
                    }
                    Message::Close(_) => bail!("Soloist's local API closed"),
                    _ => {}
                }
            }
            () = tokio::time::sleep_until(wake.unwrap_or_else(Instant::now).into()), if wake.is_some() => {
                if pending.as_ref().is_some_and(|p| Instant::now() >= p.deadline) {
                    if let Some(p) = pending.take() && let Some(reply) = p.reply { let _ = reply.send(Err(ProtocolError::new("timeout", "Soloist did not acknowledge the playback command"))); }
                    bail!("Soloist command timed out")
                }
                state.update(|s| { let value = position.value(s); if value / 1000 == s.position_ms / 1000 { return false } s.position_ms = value; true });
            }
        }
    }
}

/// When the loop next has work: a command deadline, or the moment the displayed
/// position reaches its next whole second.
fn next_wakeup(deadline: Option<Instant>, position_ms: Option<u32>) -> Option<Instant> {
    let tick = position_ms.map(|ms| {
        let to_next_second = 1000 - u64::from(ms % 1000);
        Instant::now() + Duration::from_millis(to_next_second + 5)
    });
    match (deadline, tick) {
        (Some(deadline), Some(tick)) => Some(deadline.min(tick)),
        (deadline, tick) => deadline.or(tick),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[tokio::test]
    async fn volume_persistence_preserves_mute_and_full_volume() {
        let directory =
            std::env::temp_dir().join(format!("omaspotify-soloist-volume-{}", std::process::id()));
        std::fs::create_dir(&directory).unwrap();
        for (volume, expected) in [(0, "0\n"), (54394, "83\n"), (u16::MAX, "100\n")] {
            persist_volume(&directory, volume).await.unwrap();
            assert_eq!(
                std::fs::read_to_string(directory.join("volume")).unwrap(),
                expected
            );
        }
        assert!(!directory.join("volume.tmp").exists());
        std::fs::remove_dir_all(directory).unwrap();
    }
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
    fn pause_during_seek_buffering_does_not_resume_playback() {
        let mut s = BackendState::default();
        let mut p = Position::default();
        apply_event(
            &mut s,
            &json!({"type":"playback_changed", "status":"buffering"}),
            &mut p,
        );
        assert_eq!(s.playback, PlaybackStatus::Playing);
        assert_eq!(p.speed, 0.0);
        let commands =
            commands_for(Command::Toggle, s.playback == PlaybackStatus::Playing).unwrap();
        assert_eq!(commands[0]["command"], "pause");
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

    #[test]
    fn unknown_duration_does_not_pin_position_to_zero() {
        let mut s = BackendState::default();
        let mut p = Position::default();
        apply_event(
            &mut s,
            &json!({"type":"playback_state","status":"playing",
                "item":{"uri":"spotify:track:abc","entity_type":"track","decorations":{}},
                "position":{"position_ms":45000,"speed":1}}),
            &mut p,
        );
        assert_eq!(s.track.as_ref().unwrap().duration_ms, 0);
        assert!(s.position_ms >= 45000);
        assert!(p.value(&s) >= 45000);
    }

    #[test]
    fn position_anchors_are_not_seeks_but_jumps_are() {
        let mut s = BackendState::default();
        let mut p = Position::default();
        let sync = |ms| json!({"type":"position_sync","position":{"position_ms":ms,"speed":1}});
        apply_event(&mut s, &sync(10_000), &mut p);
        let first = s.seek_sequence;
        apply_event(&mut s, &sync(10_100), &mut p);
        assert_eq!(s.seek_sequence, first, "a small re-anchor is not a seek");
        apply_event(&mut s, &sync(90_000), &mut p);
        assert_eq!(s.seek_sequence, first.wrapping_add(1));
    }

    #[test]
    fn events_without_a_field_leave_it_alone() {
        let mut s = BackendState {
            volume: 40_000,
            shuffle: true,
            repeat: RepeatMode::Context,
            ..BackendState::default()
        };
        let mut p = Position::default();
        apply_event(
            &mut s,
            &json!({"type":"volume_changed","volume":"loud"}),
            &mut p,
        );
        apply_event(
            &mut s,
            &json!({"type":"options_changed","options":{}}),
            &mut p,
        );
        apply_event(
            &mut s,
            &json!({"type":"playback_state","status":"paused"}),
            &mut p,
        );
        assert_eq!(s.volume, 40_000);
        assert!(s.shuffle);
        assert_eq!(s.repeat, RepeatMode::Context);
    }

    #[test]
    fn the_largest_cover_is_chosen_whatever_the_order() {
        let covers = [
            json!({"url":"https://a/large","size":"large"}),
            json!({"url":"https://a/xlarge","size":"xlarge"}),
            json!({"url":"https://a/small","size":"small"}),
        ];
        assert_eq!(cover_url(&covers), "https://a/xlarge");
        assert_eq!(
            cover_url(&[json!({"url":"https://a/other"})]),
            "https://a/other"
        );
        assert_eq!(cover_url(&[json!({"url":"file:///etc/passwd"})]), "");
        assert_eq!(cover_url(&[]), "");
    }

    #[test]
    fn expired_builds_and_missing_keys_are_not_retried() {
        use std::os::unix::process::ExitStatusExt;
        let exit = |code: i32| ExitStatus::from_raw(code << 8);
        assert!(matches!(
            failure_for_exit(exit(77)),
            Some(Failure::MissingCredentials)
        ));
        assert!(matches!(
            failure_for_exit(exit(75)),
            Some(Failure::SoloistExpired)
        ));
        assert!(matches!(
            failure_for_exit(exit(10)),
            Some(Failure::SoloistExpired)
        ));
        assert!(failure_for_exit(exit(1)).is_none());
        assert!(failure_for_exit(ExitStatus::from_raw(libc::SIGKILL)).is_none());
    }

    #[test]
    fn the_loop_sleeps_unless_there_is_work() {
        assert!(next_wakeup(None, None).is_none());
        let deadline = Instant::now() + Duration::from_millis(50);
        assert_eq!(next_wakeup(Some(deadline), None), Some(deadline));
        let tick = next_wakeup(None, Some(1_900)).unwrap();
        assert!(tick <= Instant::now() + Duration::from_millis(110));
        assert_eq!(next_wakeup(Some(deadline), Some(0)), Some(deadline));
    }

    struct Fixture {
        server: tokio_tungstenite::WebSocketStream<tokio::io::DuplexStream>,
        commands: mpsc::Sender<EngineRequest>,
        state: StateStore,
        directory: PathBuf,
        stop: watch::Sender<bool>,
        task: tokio::task::JoinHandle<Result<()>>,
    }

    impl Fixture {
        async fn new(name: &str) -> Self {
            use tokio_tungstenite::tungstenite::protocol::Role;
            let directory = std::env::temp_dir()
                .join(format!("omaspotify-soloist-{name}-{}", std::process::id()));
            std::fs::create_dir_all(&directory).unwrap();
            let (left, right) = tokio::io::duplex(65536);
            let client =
                tokio_tungstenite::WebSocketStream::from_raw_socket(left, Role::Client, None).await;
            let server =
                tokio_tungstenite::WebSocketStream::from_raw_socket(right, Role::Server, None)
                    .await;
            let (commands, rx) = mpsc::channel(4);
            let (stop, stopped) = watch::channel(false);
            let state = StateStore::new(BackendState::default());
            let task = tokio::spawn(drive(client, rx, stopped, state.clone(), directory.clone()));
            Self {
                server,
                commands,
                state,
                directory,
                stop,
                task,
            }
        }

        async fn push(&mut self, event: Value) {
            self.server
                .send(Message::Text(event.to_string().into()))
                .await
                .unwrap();
        }

        async fn next_command(&mut self) -> Value {
            let message = tokio::time::timeout(Duration::from_secs(1), self.server.next())
                .await
                .unwrap()
                .unwrap()
                .unwrap();
            serde_json::from_str(message.to_text().unwrap()).unwrap()
        }

        async fn wait_for(&self, ready: impl Fn(&BackendState) -> bool) {
            let mut states = self.state.subscribe();
            tokio::time::timeout(Duration::from_secs(1), async {
                while !ready(&states.borrow_and_update()) {
                    states.changed().await.unwrap();
                }
            })
            .await
            .unwrap();
        }

        async fn finish(self) {
            self.stop.send(true).unwrap();
            self.task.await.unwrap().unwrap();
            std::fs::remove_dir_all(self.directory).unwrap();
        }
    }

    #[tokio::test]
    async fn a_login_after_connecting_asks_for_state_and_a_logout_keeps_the_pairing() {
        let mut f = Fixture::new("late-login").await;
        f.push(json!({"type":"auth_state","logged_in":false,"is_active":false}))
            .await;
        f.push(json!({"type":"auth_state","logged_in":true,"is_active":true}))
            .await;
        assert_eq!(f.next_command().await["command"], "get_state");
        assert!(f.directory.join("paired").exists());
        f.push(json!({"type":"auth_state","logged_in":false,"is_active":false}))
            .await;
        f.wait_for(|s| !s.session_connected).await;
        assert!(f.directory.join("paired").exists());
        f.finish().await;
    }

    #[tokio::test]
    async fn the_snapshot_sent_on_connect_is_not_requested_again() {
        let mut f = Fixture::new("first-login").await;
        f.push(json!({"type":"auth_state","logged_in":true,"is_active":true}))
            .await;
        f.wait_for(|s| s.session_connected).await;
        let (reply, result) = oneshot::channel();
        f.commands
            .send(EngineRequest {
                command: Command::Next,
                reply: Some(reply),
            })
            .await
            .unwrap();
        assert_eq!(f.next_command().await["command"], "skip_next");
        f.push(json!({"type":"command_result","command":"skip_next"}))
            .await;
        assert!(result.await.unwrap().is_ok());
        f.finish().await;
    }

    #[tokio::test]
    async fn a_device_becoming_active_asks_for_state() {
        let mut f = Fixture::new("device").await;
        f.push(json!({"type":"auth_state","logged_in":true,"is_active":false}))
            .await;
        f.wait_for(|s| s.session_connected).await;
        f.push(json!({"type":"device_changed","is_active":true}))
            .await;
        assert_eq!(f.next_command().await["command"], "get_state");
        f.finish().await;
    }

    #[tokio::test]
    async fn two_fast_toggles_undo_each_other() {
        let mut f = Fixture::new("toggle").await;
        f.push(json!({"type":"auth_state","logged_in":true,"is_active":true}))
            .await;
        f.push(json!({"type":"playback_changed","status":"playing"}))
            .await;
        f.wait_for(|s| s.session_connected && s.playback == PlaybackStatus::Playing)
            .await;
        for expected in ["pause", "play"] {
            f.commands
                .send(EngineRequest {
                    command: Command::Toggle,
                    reply: None,
                })
                .await
                .unwrap();
            let sent = f.next_command().await;
            assert_eq!(sent["command"], expected);
            f.push(json!({"type":"command_result","command":expected}))
                .await;
        }
        f.finish().await;
    }

    #[tokio::test]
    async fn another_clients_acknowledgement_does_not_kill_playback() {
        let mut f = Fixture::new("ack").await;
        f.push(json!({"type":"auth_state","logged_in":true,"is_active":true}))
            .await;
        f.wait_for(|s| s.session_connected).await;
        let (reply, result) = oneshot::channel();
        f.commands
            .send(EngineRequest {
                command: Command::Pause,
                reply: Some(reply),
            })
            .await
            .unwrap();
        assert_eq!(f.next_command().await["command"], "pause");
        f.push(json!({"type":"command_result","command":"skip_next"}))
            .await;
        f.push(json!({"type":"command_result","command":"pause"}))
            .await;
        assert!(result.await.unwrap().is_ok());
        f.finish().await;
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
