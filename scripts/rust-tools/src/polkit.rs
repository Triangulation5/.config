use std::{
    collections::HashMap,
    env, fs,
    io::{BufRead, BufReader, Write},
    os::unix::process::CommandExt,
    path::{Path, PathBuf},
    process::{Child, Command, Stdio},
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex,
    },
    thread,
    time::{Duration, Instant},
};
use zbus::{
    connection::Builder,
    interface,
    zvariant::{OwnedValue, Value},
    DBusError,
};

const AGENT_PATH: &str = "/org/silhouette/PolkitAgent";
const AUTHORITY_NAME: &str = "org.freedesktop.PolicyKit1";
const AUTHORITY_PATH: &str = "/org/freedesktop/PolicyKit1/Authority";
const AUTHORITY_IFACE: &str = "org.freedesktop.PolicyKit1.Authority";
const HELPER_PATH: &str = "/usr/lib/polkit-1/polkit-agent-helper-1";
const POLL_MS: u64 = 50;
const IDLE_TIMEOUT_SECS: u64 = 5 * 60;
const PR_SET_PDEATHSIG: i32 = 1;
const SIGTERM: i32 = 15;

extern "C" {
    fn prctl(option: i32, arg2: usize, arg3: usize, arg4: usize, arg5: usize) -> i32;
}

#[derive(DBusError, Debug)]
#[zbus(prefix = "org.freedesktop.PolicyKit1.Error")]
enum PolkitError {
    #[zbus(error)]
    ZBus(zbus::Error),
    Cancelled(String),
}

struct ActiveSession {
    cookie: String,
    cancelled: Arc<AtomicBool>,
    child: Arc<Mutex<Option<Child>>>,
}

struct PolkitAgent {
    config_dir: PathBuf,
    resp_file: PathBuf,
    active: Arc<Mutex<Option<ActiveSession>>>,
}

impl PolkitAgent {
    fn poke(&self, args: Vec<String>) {
        let config = self.config_dir.clone();
        thread::spawn(move || {
            let _ = Command::new("quickshell")
                .arg("-p")
                .arg(config)
                .args(["ipc", "call", "polkit"])
                .args(&args)
                .stdin(Stdio::null())
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status();
        });
    }

    fn kill_child(child_slot: &Arc<Mutex<Option<Child>>>) {
        if let Ok(mut guard) = child_slot.lock() {
            if let Some(mut child) = guard.take() {
                let _ = child.kill();
                let _ = child.wait();
            }
        }
    }

    fn run_conversation(
        &self,
        action_id: String,
        message: String,
        cookie: String,
        identities: Vec<(String, HashMap<String, OwnedValue>)>,
    ) -> Result<(), PolkitError> {
        let user = identity_name(&identities).unwrap_or_else(current_username);
        let cancelled = Arc::new(AtomicBool::new(false));
        let child_slot: Arc<Mutex<Option<Child>>> = Arc::new(Mutex::new(None));

        if let Ok(mut guard) = self.active.lock() {
            if let Some(prev) = guard.take() {
                prev.cancelled.store(true, Ordering::SeqCst);
                Self::kill_child(&prev.child);
            }
            *guard = Some(ActiveSession {
                cookie: cookie.clone(),
                cancelled: Arc::clone(&cancelled),
                child: Arc::clone(&child_slot),
            });
        }

        // Remove any stale response file before starting.
        let _ = fs::remove_file(&self.resp_file);

        self.poke(vec![
            "prompt".to_string(),
            message,
            action_id,
            user.clone(),
        ]);

        let mut helper_cmd = Command::new(HELPER_PATH);
        helper_cmd
            .arg(&user)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null());
        // SAFETY: `prctl(PR_SET_PDEATHSIG, SIGTERM)` is async-signal-safe and ensures
        // the helper is terminated if the polkit agent dies unexpectedly.
        unsafe {
            helper_cmd.pre_exec(|| {
                prctl(PR_SET_PDEATHSIG, SIGTERM as usize, 0, 0, 0);
                Ok(())
            });
        }
        let mut child = match helper_cmd.spawn()
        {
            Ok(child) => child,
            Err(error) => {
                eprintln!("polkit-agent: cannot start helper: {error}");
                self.cleanup_session(&cookie, &child_slot);
                self.poke(vec!["clear".to_string()]);
                return Ok(());
            }
        };

        let mut stdin = match child.stdin.take() {
            Some(stdin) => stdin,
            None => {
                let _ = child.kill();
                let _ = child.wait();
                self.cleanup_session(&cookie, &child_slot);
                self.poke(vec!["clear".to_string()]);
                return Ok(());
            }
        };

        let stdout = match child.stdout.take() {
            Some(stdout) => stdout,
            None => {
                let _ = child.kill();
                let _ = child.wait();
                self.cleanup_session(&cookie, &child_slot);
                self.poke(vec!["clear".to_string()]);
                return Ok(());
            }
        };

        if writeln!(stdin, "{cookie}").is_err() || stdin.flush().is_err() {
            let _ = child.kill();
            let _ = child.wait();
            self.cleanup_session(&cookie, &child_slot);
            self.poke(vec!["clear".to_string()]);
            return Ok(());
        }

        if let Ok(mut guard) = child_slot.lock() {
            *guard = Some(child);
        }

        let reader = BufReader::new(stdout);
        let mut was_cancelled = false;

        for line in reader.lines() {
            if cancelled.load(Ordering::SeqCst) {
                was_cancelled = true;
                break;
            }
            let Ok(line) = line else {
                break;
            };
            let line = line.trim_end_matches(&['\r', '\n'][..]);
            if line.starts_with("PAM_PROMPT_ECHO_OFF ") || line.starts_with("PAM_PROMPT_ECHO_ON ") {
                let start = Instant::now();
                let answer = loop {
                    if cancelled.load(Ordering::SeqCst) {
                        break None;
                    }
                    if start.elapsed() >= Duration::from_secs(IDLE_TIMEOUT_SECS) {
                        cancelled.store(true, Ordering::SeqCst);
                        break None;
                    }
                    if let Ok(content) = fs::read_to_string(&self.resp_file) {
                        let _ = fs::remove_file(&self.resp_file);
                        break Some(content);
                    }
                    thread::sleep(Duration::from_millis(POLL_MS));
                };

                match answer {
                    None => {
                        was_cancelled = true;
                        break;
                    }
                    Some(content) if content.trim() == "CANCEL" => {
                        was_cancelled = true;
                        break;
                    }
                    Some(content) => {
                        if writeln!(stdin, "{content}").is_err() || stdin.flush().is_err() {
                            break;
                        }
                    }
                }
            } else if line.starts_with("SUCCESS") || line.starts_with("FAILURE") {
                break;
            }
        }

        if cancelled.load(Ordering::SeqCst) {
            was_cancelled = true;
        }

        drop(stdin);
        self.cleanup_session(&cookie, &child_slot);
        self.poke(vec!["clear".to_string()]);

        if was_cancelled {
            Err(PolkitError::Cancelled("Authentication cancelled".to_string()))
        } else {
            Ok(())
        }
    }

    fn cleanup_session(&self, cookie: &str, child_slot: &Arc<Mutex<Option<Child>>>) {
        Self::kill_child(child_slot);
        if let Ok(mut guard) = self.active.lock() {
            if guard.as_ref().is_some_and(|s| s.cookie == cookie) {
                *guard = None;
            }
        }
    }
}

struct ThreadResult<T> {
    state: Arc<Mutex<(Option<T>, Option<std::task::Waker>)>>,
}

impl<T> std::future::Future for ThreadResult<T> {
    type Output = T;

    fn poll(
        self: std::pin::Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
    ) -> std::task::Poll<Self::Output> {
        let mut guard = self.state.lock().unwrap();
        if let Some(val) = guard.0.take() {
            std::task::Poll::Ready(val)
        } else {
            guard.1 = Some(cx.waker().clone());
            std::task::Poll::Pending
        }
    }
}

#[interface(name = "org.freedesktop.PolicyKit1.AuthenticationAgent")]
impl PolkitAgent {
    async fn begin_authentication(
        &self,
        action_id: String,
        message: String,
        _icon_name: String,
        _details: HashMap<String, String>,
        cookie: String,
        identities: Vec<(String, HashMap<String, OwnedValue>)>,
    ) -> Result<(), PolkitError> {
        let agent = PolkitAgent {
            config_dir: self.config_dir.clone(),
            resp_file: self.resp_file.clone(),
            active: Arc::clone(&self.active),
        };
        let state: Arc<Mutex<(Option<Result<(), PolkitError>>, Option<std::task::Waker>)>> =
            Arc::new(Mutex::new((None, None)));
        let tx_state = Arc::clone(&state);
        thread::spawn(move || {
            let res = agent.run_conversation(action_id, message, cookie, identities);
            if let Ok(mut guard) = tx_state.lock() {
                guard.0 = Some(res);
                if let Some(waker) = guard.1.take() {
                    waker.wake();
                }
            }
        });
        ThreadResult { state }.await
    }

    async fn cancel_authentication(&self, cookie: String) -> Result<(), PolkitError> {
        if let Ok(guard) = self.active.lock() {
            if let Some(session) = guard.as_ref() {
                if session.cookie == cookie {
                    session.cancelled.store(true, Ordering::SeqCst);
                    Self::kill_child(&session.child);
                }
            }
        }
        Ok(())
    }
}

fn uid_to_username(target_uid: u32) -> Option<String> {
    let contents = fs::read_to_string("/etc/passwd").ok()?;
    for line in contents.lines() {
        let mut parts = line.split(':');
        let name = parts.next()?;
        let _pw = parts.next()?;
        let uid_str = parts.next()?;
        if uid_str.parse::<u32>().ok() == Some(target_uid) {
            return Some(name.to_string());
        }
    }
    None
}

fn identity_name(identities: &[(String, HashMap<String, OwnedValue>)]) -> Option<String> {
    let (kind, details) = identities.first()?;
    if kind != "unix-user" {
        return None;
    }
    let val = details.get("uid")?;
    let uid = u32::try_from(val).ok()?;
    uid_to_username(uid)
}

fn current_username() -> String {
    env::var("USER")
        .or_else(|_| env::var("LOGNAME"))
        .unwrap_or_default()
}

fn resolve_session_id() -> String {
    if let Ok(id) = env::var("XDG_SESSION_ID") {
        let trimmed = id.trim();
        if !trimmed.is_empty() {
            return trimmed.to_string();
        }
    }
    if let Ok(output) = Command::new("loginctl")
        .args(["show-session", "-p", "Id"])
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output()
    {
        if output.status.success() {
            let text = String::from_utf8_lossy(&output.stdout);
            if let Some(val) = text.trim().rsplit('=').next() {
                let trimmed = val.trim();
                if !trimmed.is_empty() {
                    return trimmed.to_string();
                }
            }
        }
    }
    String::new()
}

fn default_config_dir() -> PathBuf {
    let home = env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
    PathBuf::from(home).join(".config/quickshell/silhouette-shell")
}

pub(crate) fn run(config_dir: Option<&Path>) -> bool {
    let runtime = env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/tmp".to_string());
    let base = PathBuf::from(runtime).join("silhouette-polkit");
    if let Err(error) = fs::create_dir_all(&base) {
        eprintln!("polkit-agent: cannot create runtime dir: {error}");
        return false;
    }

    let session_id = resolve_session_id();
    if session_id.is_empty() {
        eprintln!("polkit-agent: no session id, not registering");
        return false;
    }

    let agent = PolkitAgent {
        config_dir: config_dir.map(Path::to_path_buf).unwrap_or_else(default_config_dir),
        resp_file: base.join("response"),
        active: Arc::new(Mutex::new(None)),
    };

    zbus::block_on(async move {
        let conn = match Builder::system()
            .and_then(|b| b.serve_at(AGENT_PATH, agent))
        {
            Ok(builder) => match builder.build().await {
                Ok(conn) => conn,
                Err(error) => {
                    eprintln!("polkit-agent: failed to connect to system bus: {error}");
                    return false;
                }
            },
            Err(error) => {
                eprintln!("polkit-agent: failed to build D-Bus connection: {error}");
                return false;
            }
        };

        let mut subject_details: HashMap<&str, Value<'_>> = HashMap::new();
        subject_details.insert("session-id", Value::from(session_id.as_str()));
        let subject = ("unix-session", subject_details);
        let options: HashMap<&str, Value<'_>> = HashMap::new();

        let reg = conn
            .call_method(
                Some(AUTHORITY_NAME),
                AUTHORITY_PATH,
                Some(AUTHORITY_IFACE),
                "RegisterAuthenticationAgentWithOptions",
                &(subject, "C", AGENT_PATH, options),
            )
            .await;

        if let Err(error) = reg {
            let msg = error.to_string();
            if msg.contains("already exists") {
                eprintln!("polkit-agent: another agent already owns this session; exiting");
                return true;
            }
            eprintln!("polkit-agent: registration failed: {error}");
            return false;
        }

        std::future::pending::<()>().await;
        true
    })
}
