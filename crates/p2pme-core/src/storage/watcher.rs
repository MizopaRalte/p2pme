use anyhow::Result;
use notify::{Config, Event, RecommendedWatcher, RecursiveMode, Watcher};
use std::path::{Path, PathBuf};
use std::sync::mpsc::channel;
use std::time::Duration;
use tracing::info;

pub struct FolderWatcher {
    _watcher: RecommendedWatcher,
    pub path: PathBuf,
}

impl FolderWatcher {
    /// Start watching a folder for changes (creates, modifications, deletions)
    pub fn watch<P: AsRef<Path>, F>(path: P, on_change: F) -> Result<Self>
    where
        F: Fn() + Send + 'static,
    {
        let path = path.as_ref().to_path_buf();
        let (tx, rx) = channel();

        let mut watcher = RecommendedWatcher::new(
            move |res: Result<Event, notify::Error>| {
                if let Ok(event) = res {
                    if event.kind.is_create() || event.kind.is_modify() || event.kind.is_remove() {
                        tx.send(()).ok();
                    }
                }
            },
            Config::default().with_poll_interval(Duration::from_secs(1)),
        )?;

        watcher.watch(&path, RecursiveMode::Recursive)?;
        info!("FolderWatcher started on {:?}", path);

        // Spawn background debouncer thread
        std::thread::spawn(move || {
            while rx.recv().is_ok() {
                // Drain any immediate follow-up events during debounce window (500ms)
                std::thread::sleep(Duration::from_millis(500));
                while rx.try_recv().is_ok() {}

                on_change();
            }
        });

        Ok(Self {
            _watcher: watcher,
            path,
        })
    }
}

