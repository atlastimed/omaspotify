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
            }
            if daemon {
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
        let device_name = device_name.trim();
        if device_name.is_empty()
            || device_name.len() > 64
            || device_name.chars().any(char::is_control)
        {
            anyhow::bail!("device name override must contain 1 to 64 printable characters");
        }
        config.device_name = device_name.to_string();
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

async fn run(config: BackendConfig, socket_path: PathBuf, use_soloist: bool) -> Result<()> {
    let state = StateStore::new(BackendState::default());
    let (shutdown_tx, shutdown_rx) = watch::channel(false);
    let started = if use_soloist {
        soloist::start(config, state.clone()).await
    } else {
        engine::start(config, state.clone()).await
    };
    let mut runtime = match started {
        Ok(runtime) => runtime,
        Err(error) => {
            state.update(|current| {
                current.lifecycle = Lifecycle::Error;
                current.error = error.to_string();
                true
            });
            return Err(error);
        }
    };

    let _socket_guard = socket::serve(
        socket_path.clone(),
        state.clone(),
        runtime.commands.clone(),
        shutdown_rx.clone(),
    )
    .await?;
    failure::clear(&socket_path);
    let mut mpris_task = tokio::spawn(mpris::serve(
        state.clone(),
        runtime.commands.clone(),
        shutdown_tx.clone(),
    ));

    let mut requested_shutdown = shutdown_rx.clone();
    // systemd stops services with SIGTERM, so without this nothing below would run.
    let mut terminate =
        signal(SignalKind::terminate()).context("failed to wait for termination signal")?;
    tokio::select! {
        signal = tokio::signal::ctrl_c() => {
            signal.context("failed to wait for termination signal")?;
        }
        _ = terminate.recv() => {}
        _ = requested_shutdown.changed() => {}
        result = runtime.wait_done() => {
            result.context("playback engine stopped")?;
            anyhow::bail!("playback engine stopped unexpectedly");
        }
        result = &mut mpris_task => {
            match result {
                Ok(Ok(())) => anyhow::bail!("MPRIS server ended unexpectedly"),
                Ok(Err(error)) => return Err(error).context("MPRIS server failed"),
                Err(error) => return Err(error).context("MPRIS task failed"),
            }
        }
    }

    let _ = shutdown_tx.send(true);
    runtime.shutdown();
    state.update(|current| {
        current.lifecycle = Lifecycle::Stopped;
        current.playback = crate::protocol::PlaybackStatus::Stopped;
        true
    });
    // Both must finish inside the unit's TimeoutStopSec of 5 seconds.
    let _ = tokio::time::timeout(ENGINE_STOP_TIMEOUT, runtime.wait_done()).await;
    // Long enough to tell MPRIS clients about the stop, then there is nothing left to serve.
    let _ = tokio::time::timeout(MPRIS_STOP_GRACE, &mut mpris_task).await;
    mpris_task.abort();
    Ok(())
}
