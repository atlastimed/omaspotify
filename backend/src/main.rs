mod config;
mod engine;
mod fade;
mod failure;
mod mpris;
mod protocol;
mod socket;
mod soloist;
mod state;

use std::path::PathBuf;

use anyhow::{Context, Result};
use clap::{Parser, Subcommand};
use protocol::{BackendState, Lifecycle};
use tokio::{
    signal::unix::{SignalKind, signal},
    sync::watch,
};

use crate::{config::BackendConfig, state::StateStore};

const ENGINE_STOP_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(4);
const MPRIS_STOP_GRACE: std::time::Duration = std::time::Duration::from_millis(100);

#[derive(Debug, Parser)]
#[command(version, about)]
struct Cli {
    /// Use Spotify's official Soloist receiver with the native MPRIS/socket adapter.
    #[arg(long, global = true)]
    soloist: bool,
    #[arg(long, global = true)]
    config_path: Option<PathBuf>,
    #[arg(long, global = true)]
    socket_path: Option<PathBuf>,
    /// Override the configured Connect device name (useful for parallel A/B testing).
    #[arg(long, global = true)]
    device_name: Option<String>,
    #[command(subcommand)]
    action: Option<Action>,
}

#[derive(Debug, Subcommand)]
enum Action {
    /// Validate configuration without connecting to Spotify.
    Check,
    /// Authorize local playback and store a private reusable credential.
    Authenticate {
        #[arg(long, default_value_t = 8000)]
        oauth_port: u16,
    },
}

#[tokio::main(flavor = "current_thread")]
async fn main() -> std::process::ExitCode {
    let cli = Cli::parse();
    let daemon = cli.action.is_none();
    let socket = cli
        .socket_path
        .clone()
        .unwrap_or_else(config::default_socket_path);
    match launch(cli).await {
        Ok(()) => std::process::ExitCode::SUCCESS,
        Err(error) => {
            let kind = error
                .downcast_ref::<failure::Failure>()
                .copied()
                .unwrap_or(failure::Failure::Transient);
            if daemon {
                let _ = failure::record(&socket, kind);
                eprintln!("Playback failed: {kind}: {error:#}");
            } else {
                eprintln!("{error:#}");
            }
            std::process::ExitCode::from(kind.exit_code())
        }
    }
}

async fn launch(cli: Cli) -> Result<()> {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info")).init();
    let config_path = cli.config_path.unwrap_or_else(config::default_config_path);
    let mut config =
        BackendConfig::load(&config_path).context(failure::Failure::InvalidConfiguration)?;
    if let Some(device_name) = cli.device_name {
        config.device_name = device_name_override(&device_name)?;
    }

    match cli.action {
        Some(Action::Check) => {
            println!("{}", serde_json::to_string(&config.summary())?);
            return Ok(());
        }
        Some(Action::Authenticate { oauth_port }) => {
            return engine::authenticate(&config, oauth_port).await;
        }
        None => {}
    }

    run(
        config,
        cli.socket_path.unwrap_or_else(config::default_socket_path),
        cli.soloist,
    )
    .await
}

fn device_name_override(name: &str) -> Result<String> {
    let name = name.trim();
    if name.is_empty() || name.len() > 64 || name.chars().any(char::is_control) {
        return Err(anyhow::anyhow!(
            "device name override must contain 1 to 64 printable characters"
        ))
        .context(failure::Failure::InvalidConfiguration);
    }
    Ok(name.to_string())
}

async fn run(config: BackendConfig, socket_path: PathBuf, use_soloist: bool) -> Result<()> {
    // Taken before anything starts, so a second backend cannot disturb a running one.
    let _instance = socket::claim(&socket_path)?;
    let state = StateStore::new(BackendState::default());
    let (shutdown_tx, shutdown_rx) = watch::channel(false);
    let mut runtime = if use_soloist {
        soloist::start(config, state.clone()).await
    } else {
        engine::start(config, state.clone()).await
    }?;

    let served = socket::serve(
        socket_path.clone(),
        state.clone(),
        runtime.commands.clone(),
        shutdown_rx.clone(),
    )
    .await;
    let _socket_guard = match served {
        Ok(guard) => guard,
        Err(error) => {
            stop_engine(&mut runtime, &state, &shutdown_tx).await;
            return Err(error);
        }
    };
    failure::clear(&socket_path);
    let mpris_task = tokio::spawn(mpris::serve(
        state.clone(),
        runtime.commands.clone(),
        shutdown_tx.clone(),
    ));
    run_until_stopped(
        &mut runtime,
        mpris_task,
        stop_requested(shutdown_rx),
        &state,
        &shutdown_tx,
    )
    .await
}

/// Resolves when the backend is asked to stop, by a signal or through MPRIS.
async fn stop_requested(mut requested: watch::Receiver<bool>) -> Result<()> {
    // systemd stops services with SIGTERM, so without this nothing after it would run.
    let mut terminate =
        signal(SignalKind::terminate()).context("failed to wait for termination signal")?;
    tokio::select! {
        signal = tokio::signal::ctrl_c() => signal.context("failed to wait for termination signal"),
        _ = terminate.recv() => Ok(()),
        _ = requested.changed() => Ok(()),
    }
}

/// Waits for whatever ends the backend, then stops the engine cleanly before reporting it.
async fn run_until_stopped(
    runtime: &mut engine::EngineRuntime,
    mut mpris_task: tokio::task::JoinHandle<mpris_server::zbus::Result<()>>,
    stop: impl Future<Output = Result<()>>,
    state: &StateStore,
    shutdown_tx: &watch::Sender<bool>,
) -> Result<()> {
    let mut mpris_ended = false;
    let outcome = tokio::select! {
        result = stop => result,
        result = runtime.wait_done() => Err(match result {
            Ok(()) => anyhow::anyhow!("playback engine stopped unexpectedly"),
            Err(error) => error.context("playback engine stopped"),
        }),
        result = &mut mpris_task => {
            mpris_ended = true;
            Err(match result {
                Ok(Ok(())) => anyhow::anyhow!("MPRIS server ended unexpectedly"),
                Ok(Err(error)) => anyhow::Error::new(error).context("MPRIS server failed"),
                Err(error) => anyhow::Error::new(error).context("MPRIS task failed"),
            })
        }
    };
    stop_engine(runtime, state, shutdown_tx).await;
    if !mpris_ended {
        // Long enough to tell MPRIS clients about the stop, then there is nothing left to serve.
        let _ = tokio::time::timeout(MPRIS_STOP_GRACE, &mut mpris_task).await;
        mpris_task.abort();
    }
    outcome
}

/// Soloist needs this to sign off and remove its files, so every way out goes through it.
async fn stop_engine(
    runtime: &mut engine::EngineRuntime,
    state: &StateStore,
    shutdown_tx: &watch::Sender<bool>,
) {
    let _ = shutdown_tx.send(true);
    runtime.shutdown();
    state.update(|current| {
        current.lifecycle = Lifecycle::Stopped;
        current.playback = crate::protocol::PlaybackStatus::Stopped;
        true
    });
    // This and the MPRIS grace must finish inside the unit's TimeoutStopSec of 5 seconds.
    let _ = tokio::time::timeout(ENGINE_STOP_TIMEOUT, runtime.wait_done()).await;
}

#[cfg(test)]
mod tests {
    use std::sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    };

    use tokio::sync::{mpsc, oneshot};

    use super::*;

    #[test]
    fn a_bad_device_name_is_a_configuration_error() {
        for name in ["", "   ", "a\nb", &"x".repeat(65)] {
            let error = device_name_override(name).unwrap_err();
            let failure = error.downcast_ref::<failure::Failure>().unwrap();
            assert_eq!(failure.exit_code(), 78, "{name:?}");
        }
        assert_eq!(device_name_override("  Desk  ").unwrap(), "Desk");
    }

    type MprisTask = tokio::task::JoinHandle<mpris_server::zbus::Result<()>>;

    // Stands in for an engine, noting whether it was asked to stop before it ended.
    fn engine_that_waits_to_be_stopped() -> (engine::EngineRuntime, Arc<AtomicBool>) {
        let (commands, _) = mpsc::channel(1);
        let (shutdown, mut asked) = watch::channel(false);
        let (finished, done) = oneshot::channel();
        let stopped = Arc::new(AtomicBool::new(false));
        tokio::spawn({
            let stopped = Arc::clone(&stopped);
            async move {
                let _ = asked.changed().await;
                stopped.store(*asked.borrow(), Ordering::SeqCst);
                let _ = finished.send(Ok(()));
            }
        });
        let runtime = engine::EngineRuntime {
            commands,
            shutdown,
            done: Some(done),
        };
        (runtime, stopped)
    }

    fn mpris_that_keeps_running() -> MprisTask {
        tokio::spawn(std::future::pending())
    }

    #[tokio::test]
    async fn a_failed_mpris_server_still_stops_the_engine_cleanly() {
        let (mut runtime, stopped) = engine_that_waits_to_be_stopped();
        let state = StateStore::new(BackendState::default());
        let (shutdown_tx, _shutdown_rx) = watch::channel(false);
        let outcome = run_until_stopped(
            &mut runtime,
            tokio::spawn(async { Ok(()) }),
            std::future::pending(),
            &state,
            &shutdown_tx,
        )
        .await;
        assert!(outcome.is_err());
        assert!(stopped.load(Ordering::SeqCst));
        assert_eq!(state.with(|current| current.lifecycle), Lifecycle::Stopped);
        assert!(*shutdown_tx.borrow());
    }

    #[tokio::test]
    async fn a_requested_stop_is_a_clean_exit() {
        let (mut runtime, stopped) = engine_that_waits_to_be_stopped();
        let state = StateStore::new(BackendState::default());
        let (shutdown_tx, _shutdown_rx) = watch::channel(false);
        let outcome = run_until_stopped(
            &mut runtime,
            mpris_that_keeps_running(),
            std::future::ready(Ok(())),
            &state,
            &shutdown_tx,
        )
        .await;
        assert!(outcome.is_ok());
        assert!(stopped.load(Ordering::SeqCst));
    }

    #[tokio::test]
    async fn an_engine_that_ends_by_itself_says_why_and_is_not_waited_for_again() {
        let (commands, _) = mpsc::channel(1);
        let (shutdown, _asked) = watch::channel(false);
        let (finished, done) = oneshot::channel();
        finished
            .send(Err(failure::Failure::SoloistExpired.into()))
            .unwrap();
        let mut runtime = engine::EngineRuntime {
            commands,
            shutdown,
            done: Some(done),
        };
        let state = StateStore::new(BackendState::default());
        let (shutdown_tx, _shutdown_rx) = watch::channel(false);
        let error = run_until_stopped(
            &mut runtime,
            mpris_that_keeps_running(),
            std::future::pending(),
            &state,
            &shutdown_tx,
        )
        .await
        .unwrap_err();
        let failure = error.downcast_ref::<failure::Failure>().unwrap();
        assert_eq!(failure.exit_code(), 75);
        assert!(runtime.wait_done().await.is_ok());
    }
}
