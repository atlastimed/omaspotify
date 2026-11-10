use std::{
    fs, io,
    os::unix::fs::{MetadataExt, OpenOptionsExt, PermissionsExt},
    path::{Path, PathBuf},
    sync::Arc,
    time::Duration,
};

use anyhow::{Context, Result};
use tokio::{
    io::{AsyncBufReadExt, AsyncRead, AsyncWriteExt, BufReader},
    net::{UnixListener, UnixStream},
    sync::{Semaphore, watch},
};

/// The largest single request we will buffer. A load command carries a list of
/// track URIs, so this has room for tens of thousands of them; anything past it
/// is not a request we sent.
const MAX_FRAME_BYTES: usize = 1024 * 1024;

/// The player opens one connection. The rest of the allowance is slack.
const MAX_CLIENTS: usize = 8;

/// A client that stops reading is dropped rather than left holding a slot.
const WRITE_TIMEOUT: Duration = Duration::from_secs(5);

/// Running out of file descriptors would otherwise retry as fast as it can fail.
const ACCEPT_RETRY_DELAY: Duration = Duration::from_millis(100);

/// Reads newline-delimited requests without letting one grow without end.
///
/// `BufReader::lines()` will buffer whatever it is given, so a client that
/// never sends a newline can make the backend allocate until it dies. This
/// keeps the partial line in the struct rather than in the future, so it stays
/// safe to cancel inside `tokio::select!`, and refuses a frame over the cap
/// instead of growing to meet it.
struct BoundedLines<R> {
    reader: BufReader<R>,
    partial: Vec<u8>,
}

impl<R: AsyncRead + Unpin> BoundedLines<R> {
    fn new(reader: R) -> Self {
        Self {
            reader: BufReader::new(reader),
            partial: Vec::new(),
        }
    }

    /// `Ok(None)` at end of stream. An oversized frame is an error, because a
    /// sender that far outside the protocol has nothing more worth reading.
    async fn next_line(&mut self) -> Result<Option<String>, FrameError> {
        loop {
            let available = self.reader.fill_buf().await.map_err(FrameError::Io)?;
            if available.is_empty() {
                if self.partial.is_empty() {
                    return Ok(None);
                }
                let line = std::mem::take(&mut self.partial);
                return Ok(Some(String::from_utf8_lossy(&line).into_owned()));
            }
            if let Some(end) = available.iter().position(|byte| *byte == b'\n') {
                if self.partial.len() + end > MAX_FRAME_BYTES {
                    return Err(FrameError::TooLong);
                }
                self.partial.extend_from_slice(&available[..end]);
                self.reader.consume(end + 1);
                let mut line = std::mem::take(&mut self.partial);
                if line.last() == Some(&b'\r') {
                    line.pop();
                }
                return Ok(Some(String::from_utf8_lossy(&line).into_owned()));
            }
            if self.partial.len() + available.len() > MAX_FRAME_BYTES {
                return Err(FrameError::TooLong);
            }
            let taken = available.len();
            self.partial.extend_from_slice(available);
            self.reader.consume(taken);
        }
    }
}

#[derive(Debug)]
enum FrameError {
    Io(io::Error),
    TooLong,
}

impl std::fmt::Display for FrameError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Io(error) => write!(f, "{error}"),
            Self::TooLong => write!(f, "request longer than {MAX_FRAME_BYTES} bytes"),
        }
    }
}

use crate::{
    engine::{EngineSender, send_with_reply},
    protocol::{PROTOCOL_VERSION, ProtocolError, Request, ServerMessage},
    state::StateStore,
};

pub struct SocketGuard {
    path: PathBuf,
    identity: Option<(u64, u64)>,
}

fn file_identity(path: &Path) -> Option<(u64, u64)> {
    fs::symlink_metadata(path)
        .ok()
        .map(|metadata| (metadata.dev(), metadata.ino()))
}

impl Drop for SocketGuard {
    fn drop(&mut self) {
        // Never remove a socket that has since been replaced by another backend.
        if self.identity.is_some() && file_identity(&self.path) == self.identity {
            let _ = fs::remove_file(&self.path);
        }
    }
}

/// Held for as long as this backend runs. It is let go even if the backend is killed.
pub struct InstanceLock {
    _file: fs::File,
}

/// Refuses to go on while another backend owns this socket, even one still starting.
pub fn claim(path: &Path) -> Result<InstanceLock> {
    let parent = path
        .parent()
        .context("backend socket path has no parent directory")?;
    fs::create_dir_all(parent)
        .with_context(|| format!("failed to create socket directory {}", parent.display()))?;
    let mut lock_path = path.as_os_str().to_owned();
    lock_path.push(".lock");
    let lock_path = PathBuf::from(lock_path);
    let file = fs::OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(false)
        .mode(0o600)
        .open(&lock_path)
        .with_context(|| format!("failed to open {}", lock_path.display()))?;
    match file.try_lock() {
        Ok(()) => {}
        Err(fs::TryLockError::WouldBlock) => {
            anyhow::bail!("another backend is already running for {}", path.display())
        }
        Err(fs::TryLockError::Error(error)) => {
            return Err(error).with_context(|| format!("failed to lock {}", lock_path.display()));
        }
    }
    // A backend from before the lock existed still gives itself away by answering.
    if std::os::unix::net::UnixStream::connect(path).is_ok() {
        anyhow::bail!("another backend is already serving {}", path.display());
    }
    Ok(InstanceLock { _file: file })
}

/// A leftover socket is replaced, but one with a backend behind it is not ours to take.
fn clear_stale_socket(path: &Path) -> Result<()> {
    if !path.exists() {
        return Ok(());
    }
    if std::os::unix::net::UnixStream::connect(path).is_ok() {
        anyhow::bail!("another backend is already serving {}", path.display());
    }
    fs::remove_file(path)
        .with_context(|| format!("failed to remove stale socket {}", path.display()))
}

pub async fn serve(
    path: PathBuf,
    state: StateStore,
    commands: EngineSender,
    mut shutdown: watch::Receiver<bool>,
) -> Result<SocketGuard> {
    let parent = path
        .parent()
        .context("backend socket path has no parent directory")?;
    fs::create_dir_all(parent)
        .with_context(|| format!("failed to create socket directory {}", parent.display()))?;
    clear_stale_socket(&path)?;

    let listener = UnixListener::bind(&path)
        .with_context(|| format!("failed to bind backend socket {}", path.display()))?;
    fs::set_permissions(&path, fs::Permissions::from_mode(0o600))
        .with_context(|| format!("failed to secure backend socket {}", path.display()))?;
    let identity = file_identity(&path);
    let guard = SocketGuard { path, identity };

    let clients = Arc::new(Semaphore::new(MAX_CLIENTS));
    tokio::spawn(async move {
        loop {
            tokio::select! {
                accepted = listener.accept() => match accepted {
                    Ok((stream, _)) => {
                        // Refuse rather than queue: a caller holding connections
                        // open should not be able to grow our work list.
                        match Arc::clone(&clients).try_acquire_owned() {
                            Ok(permit) => {
                                tokio::spawn(handle_client(
                                    stream,
                                    state.clone(),
                                    commands.clone(),
                                    permit,
                                ));
                            }
                            Err(_) => {
                                log::warn!(
                                    "backend socket refused a client: {MAX_CLIENTS} already connected"
                                );
                                drop(stream);
                            }
                        }
                    }
                    Err(error) => {
                        log::warn!("backend socket accept failed: {error}");
                        tokio::time::sleep(ACCEPT_RETRY_DELAY).await;
                    }
                },
                changed = shutdown.changed() => {
                    if changed.is_err() || *shutdown.borrow() {
                        break;
                    }
                }
            }
        }
    });

    Ok(guard)
}

async fn handle_client(
    stream: UnixStream,
    state: StateStore,
    commands: EngineSender,
    permit: tokio::sync::OwnedSemaphorePermit,
) {
    if let Err(error) = client_loop(stream, state, commands).await {
        log::debug!("backend client disconnected: {error}");
    }
    drop(permit);
}

async fn client_loop(stream: UnixStream, state: StateStore, commands: EngineSender) -> Result<()> {
    let (reader, mut writer) = stream.into_split();
    let mut lines = BoundedLines::new(reader);
    let mut states = state.subscribe();
    let initial = state.with(|snapshot| {
        encode_message(&ServerMessage::Event {
            v: PROTOCOL_VERSION,
            event: "state_changed",
            state: snapshot,
        })
    })?;
    write_encoded(&mut writer, &initial).await?;

    loop {
        tokio::select! {
            line = lines.next_line() => {
                let line = match line {
                    Ok(Some(line)) => line,
                    Ok(None) => break,
                    Err(FrameError::TooLong) => {
                        log::warn!("backend client sent an oversized request; closing");
                        let refusal = ServerMessage::failure(
                            0,
                            ProtocolError::new(
                                "request_too_large",
                                format!("request longer than {MAX_FRAME_BYTES} bytes"),
                            ),
                        );
                        let _ = write_message(&mut writer, &refusal).await;
                        break;
                    }
                    Err(FrameError::Io(error)) => return Err(error.into()),
                };
                let message = handle_line(&line, &state, &commands).await;
                write_message(&mut writer, &message).await?;
            }
            changed = states.changed() => {
                if changed.is_err() { break; }
                let encoded = {
                    let snapshot = states.borrow_and_update();
                    encode_message(&ServerMessage::Event {
                        v: PROTOCOL_VERSION,
                        event: "state_changed",
                        state: &snapshot,
                    })?
                };
                write_encoded(&mut writer, &encoded).await?;
            }
        }
    }
    Ok(())
}

async fn handle_line<'a>(
    line: &str,
    state: &StateStore,
    commands: &EngineSender,
) -> ServerMessage<'a> {
    let invalid = |id, error: serde_json::Error| {
        ServerMessage::failure(
            id,
            ProtocolError::new("invalid_request", format!("invalid JSON request: {error}")),
        )
    };
    // Read the id first, so a request we cannot use is still refused under it.
    let value: serde_json::Value = match serde_json::from_str(line) {
        Ok(value) => value,
        Err(error) => return invalid(0, error),
    };
    let id = value["id"].as_u64().unwrap_or(0);
    if let Some(version) = value["v"].as_u64()
        && version != u64::from(PROTOCOL_VERSION)
    {
        return ServerMessage::failure(
            id,
            ProtocolError::new(
                "unsupported_version",
                format!("protocol version {version} is unsupported; expected {PROTOCOL_VERSION}"),
            ),
        );
    }
    let request: Request = match serde_json::from_value(value) {
        Ok(request) => request,
        Err(error) => return invalid(id, error),
    };

    let result = match request.command {
        crate::protocol::Command::Hello => Ok(serde_json::json!({
            "protocol_version": PROTOCOL_VERSION,
            "backend_version": env!("CARGO_PKG_VERSION"),
            "engine": state.with(|snapshot| snapshot.engine.clone())
        })),
        crate::protocol::Command::Ping => Ok(serde_json::json!({ "pong": true })),
        crate::protocol::Command::GetState => state
            .with(|snapshot| serde_json::to_value(snapshot))
            .map_err(|error| ProtocolError::new("serialization_error", error.to_string())),
        command => send_with_reply(commands, command).await,
    };

    match result {
        Ok(value) => ServerMessage::success(request.id, value),
        Err(error) => ServerMessage::failure(request.id, error),
    }
}

async fn write_message(
    writer: &mut tokio::net::unix::OwnedWriteHalf,
    message: &ServerMessage<'_>,
) -> Result<()> {
    let encoded = encode_message(message)?;
    write_encoded(writer, &encoded).await
}

fn encode_message(message: &ServerMessage<'_>) -> Result<Vec<u8>> {
    let mut encoded = serde_json::to_vec(message).context("failed to encode backend message")?;
    encoded.push(b'\n');
    Ok(encoded)
}

async fn write_encoded(
    writer: &mut tokio::net::unix::OwnedWriteHalf,
    encoded: &[u8],
) -> Result<()> {
    tokio::time::timeout(WRITE_TIMEOUT, writer.write_all(encoded))
        .await
        .context("backend client stopped reading")?
        .context("failed to write backend message")?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_socket_path(name: &str) -> PathBuf {
        let directory =
            std::env::temp_dir().join(format!("omaspotify-socket-{name}-{}", std::process::id()));
        fs::create_dir_all(&directory).unwrap();
        directory.join("backend.sock")
    }

    #[test]
    fn a_live_backend_keeps_its_socket_and_a_dead_ones_is_cleared() {
        let path = test_socket_path("live");
        let listener = std::os::unix::net::UnixListener::bind(&path).unwrap();
        assert!(clear_stale_socket(&path).is_err());
        assert!(path.exists());
        drop(listener);
        clear_stale_socket(&path).unwrap();
        assert!(!path.exists());
        fs::remove_dir(path.parent().unwrap()).unwrap();
    }

    #[test]
    fn a_second_backend_is_refused_until_the_first_has_gone() {
        let path = test_socket_path("claim");
        let first = claim(&path).unwrap();
        assert!(claim(&path).is_err());
        drop(first);
        drop(claim(&path).unwrap());
        fs::remove_dir_all(path.parent().unwrap()).unwrap();
    }

    #[test]
    fn a_backend_that_is_answering_is_not_disturbed_but_a_dead_ones_socket_is_no_obstacle() {
        let path = test_socket_path("claim-live");
        let listener = std::os::unix::net::UnixListener::bind(&path).unwrap();
        assert!(claim(&path).is_err());
        assert!(path.exists());
        drop(listener);
        drop(claim(&path).unwrap());
        fs::remove_dir_all(path.parent().unwrap()).unwrap();
    }

    #[test]
    fn leaving_does_not_remove_a_socket_someone_else_now_owns() {
        let path = test_socket_path("guard");
        let first = std::os::unix::net::UnixListener::bind(&path).unwrap();
        let guard = SocketGuard {
            path: path.clone(),
            identity: file_identity(&path),
        };
        fs::remove_file(&path).unwrap();
        let second = std::os::unix::net::UnixListener::bind(&path).unwrap();
        drop(guard);
        assert!(path.exists(), "the newer backend lost its socket");
        drop((first, second));
        fs::remove_file(&path).unwrap();
        fs::remove_dir(path.parent().unwrap()).unwrap();
    }

    async fn answer(line: &str) -> serde_json::Value {
        let state = StateStore::new(crate::protocol::BackendState::default());
        let (commands, _receiver) = tokio::sync::mpsc::channel(1);
        serde_json::to_value(handle_line(line, &state, &commands).await).unwrap()
    }

    #[tokio::test]
    async fn a_request_that_cannot_be_read_is_refused_under_its_own_id() {
        let unknown = answer(r#"{"v":1,"id":7,"command":"dance"}"#).await;
        assert_eq!(unknown["id"], 7);
        assert_eq!(unknown["error"]["code"], "invalid_request");

        let incomplete = answer(r#"{"v":1,"id":8,"command":"seek"}"#).await;
        assert_eq!(incomplete["id"], 8);
        assert_eq!(incomplete["error"]["code"], "invalid_request");

        for line in ["not json", r#"{"v":1,"command":"ping"}"#, r#"[1,2]"#] {
            let refused = answer(line).await;
            assert_eq!(refused["id"], 0, "{line}");
            assert_eq!(refused["error"]["code"], "invalid_request", "{line}");
        }
    }

    #[tokio::test]
    async fn another_protocol_version_is_refused_under_its_own_id() {
        for line in [
            r#"{"v":2,"id":9,"command":"ping"}"#,
            r#"{"v":2,"id":9,"command":"added_in_version_two"}"#,
            r#"{"v":70000,"id":9,"command":"ping"}"#,
        ] {
            let refused = answer(line).await;
            assert_eq!(refused["id"], 9, "{line}");
            assert_eq!(refused["error"]["code"], "unsupported_version", "{line}");
        }
    }

    #[tokio::test]
    async fn a_good_request_is_answered_under_its_own_id() {
        let pong = answer(r#"{"v":1,"id":11,"command":"ping"}"#).await;
        assert_eq!(pong["id"], 11);
        assert_eq!(pong["ok"], true);
        assert_eq!(pong["result"]["pong"], true);
    }

    #[tokio::test]
    async fn reads_whole_lines_and_stops_at_the_end() {
        let input: &[u8] = b"one\ntwo\r\nthree";
        let mut lines = BoundedLines::new(input);
        assert_eq!(lines.next_line().await.unwrap().unwrap(), "one");
        assert_eq!(lines.next_line().await.unwrap().unwrap(), "two");
        assert_eq!(lines.next_line().await.unwrap().unwrap(), "three");
        assert!(lines.next_line().await.unwrap().is_none());
    }

    // A client that never sends a newline used to make us allocate until we died.
    #[tokio::test]
    async fn refuses_a_frame_past_the_cap() {
        let flood = vec![b'x'; MAX_FRAME_BYTES + 1];
        let mut lines = BoundedLines::new(flood.as_slice());
        assert!(matches!(lines.next_line().await, Err(FrameError::TooLong)));
    }

    #[tokio::test]
    async fn accepts_a_frame_right_up_to_the_cap() {
        let mut framed = vec![b'x'; MAX_FRAME_BYTES];
        framed.push(b'\n');
        let mut lines = BoundedLines::new(framed.as_slice());
        let line = lines.next_line().await.unwrap().unwrap();
        assert_eq!(line.len(), MAX_FRAME_BYTES);
    }

    // The cap is on one frame, not on the connection: a long-lived client keeps
    // sending commands.
    #[tokio::test]
    async fn many_small_frames_are_fine() {
        let mut input = Vec::new();
        for _ in 0..1000 {
            input.extend_from_slice(b"{\"v\":1,\"id\":1,\"command\":\"ping\"}\n");
        }
        let mut lines = BoundedLines::new(input.as_slice());
        let mut seen = 0;
        while lines.next_line().await.unwrap().is_some() {
            seen += 1;
        }
        assert_eq!(seen, 1000);
    }
}
