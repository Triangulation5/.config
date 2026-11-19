mod alpine;
mod arch;
mod bsd;
mod darwin;
mod debian;
mod distro;
mod fedora;
mod gentoo;
mod suse;
mod void;

use serde_json::{json, Value};
use std::{
    collections::HashSet,
    env, fs,
    os::unix::fs::PermissionsExt,
    process::{Command, Output},
};

pub(crate) fn run(operation: &str) -> Value {
    match operation {
        "check" => check(),
        "apply" => apply(false),
        "apply-minimal" => apply(true),
        _ => json!({
            "status": "error",
            "error": format!("unknown package update operation: {operation}")
        }),
    }
}

pub(super) struct CommandSpec {
    program: &'static str,
    args: &'static [&'static str],
    privileged: bool,
    env: &'static [(&'static str, &'static str)],
}

impl CommandSpec {
    pub(super) const fn new(
        program: &'static str,
        args: &'static [&'static str],
        privileged: bool,
    ) -> Self {
        Self {
            program,
            args,
            privileged,
            env: &[],
        }
    }

    pub(super) const fn with_env(mut self, env: &'static [(&'static str, &'static str)]) -> Self {
        self.env = env;
        self
    }

    fn display(&self) -> String {
        let mut parts = Vec::new();
        if self.privileged {
            parts.push(privilege_helper().unwrap_or("pkexec").to_owned());
            if !self.env.is_empty() {
                parts.push("env".to_owned());
                parts.extend(self.env.iter().map(|(key, value)| format!("{key}={value}")));
            }
        }
        parts.push(self.program.to_owned());
        parts.extend(self.args.iter().map(|arg| (*arg).to_owned()));
        parts.join(" ")
    }
}

pub(super) struct Backend {
    check: CommandSpec,
    parse: fn(&str) -> Result<Vec<String>, String>,
    check_success_codes: &'static [i32],
    apply: Vec<CommandSpec>,
    minimal_apply: Option<Vec<CommandSpec>>,
    note: Option<&'static str>,
    reboot_check: Option<CommandSpec>,
}

impl Backend {
    pub(super) fn new(
        check: CommandSpec,
        parse: fn(&str) -> Result<Vec<String>, String>,
        apply: Vec<CommandSpec>,
        minimal_apply: Option<Vec<CommandSpec>>,
    ) -> Self {
        Self {
            check,
            parse,
            check_success_codes: &[0],
            apply,
            minimal_apply,
            note: None,
            reboot_check: None,
        }
    }

    pub(super) fn check_success_codes(mut self, codes: &'static [i32]) -> Self {
        self.check_success_codes = codes;
        self
    }

    pub(super) fn note(mut self, note: &'static str) -> Self {
        self.note = Some(note);
        self
    }

    pub(super) fn reboot_check(mut self, command: CommandSpec) -> Self {
        self.reboot_check = Some(command);
        self
    }
}

fn backend() -> Option<Backend> {
    match distro::detect() {
        distro::Distro::Fedora => Some(fedora::backend()),
        distro::Distro::Alpine => Some(alpine::backend()),
        distro::Distro::Arch => Some(arch::backend()),
        distro::Distro::Debian => Some(debian::backend()),
        distro::Distro::Suse => Some(suse::backend()),
        distro::Distro::Gentoo => Some(gentoo::backend()),
        distro::Distro::Void => Some(void::backend()),
        distro::Distro::FreeBsd | distro::Distro::DragonFly => Some(bsd::pkg_backend()),
        distro::Distro::OpenBsd => Some(bsd::openbsd_backend()),
        distro::Distro::NetBsd => Some(bsd::netbsd_backend()),
        distro::Distro::Darwin => Some(darwin::backend()),
        distro::Distro::Unknown => None,
    }
}

fn check() -> Value {
    let Some(backend) = backend() else {
        return json!({
            "status": "error",
            "error": "Package updates are not supported for this distribution."
        });
    };
    let output = execute(&backend.check);
    if !backend.check_success_codes.contains(&output.code) {
        return json!({
            "status": "error",
            "error": command_error(&backend.check, &output)
        });
    }

    let packages = match (backend.parse)(&output.text) {
        Ok(packages) => {
            let mut seen = HashSet::new();
            packages
                .into_iter()
                .filter(|package| !package.is_empty() && seen.insert(package.clone()))
                .collect::<Vec<_>>()
        }
        Err(error) => {
            return json!({
                "status": "error",
                "error": format!("could not parse update list: {error}")
            });
        }
    };
    let mut result = json!({
        "status": "ok",
        "updates": packages.len(),
        "packages": packages,
        "supportsMinimal": backend.minimal_apply.is_some()
    });
    if let Some(note) = backend.note {
        result["note"] = json!(note);
    }
    result
}

fn apply(minimal: bool) -> Value {
    let Some(backend) = backend() else {
        return apply_error(
            "package manager",
            "Package updates are not supported for this distribution.",
        );
    };
    let commands = if minimal {
        let Some(commands) = backend.minimal_apply.as_ref() else {
            return apply_error(
                "package manager",
                "This distribution does not provide a generic security-only update.",
            );
        };
        commands
    } else {
        &backend.apply
    };

    let mut results = Vec::new();
    for spec in commands {
        let output = execute(spec);
        let success = output.code == 0;
        results.push(json!({
            "command": spec.display(),
            "success": success,
            "output": output.text
        }));
        if !success {
            break;
        }
    }
    let applied = !results.is_empty() && results.iter().all(|result| result["success"] == true);
    let reboot_needed = backend
        .reboot_check
        .as_ref()
        .is_some_and(|command| command_exists(command.program) && execute(command).code == 1);
    json!({
        "status": if applied { "ok" } else { "error" },
        "applied": applied,
        "rebootNeeded": reboot_needed,
        "results": results
    })
}

fn apply_error(command: &str, message: &str) -> Value {
    json!({
        "status": "error",
        "applied": false,
        "rebootNeeded": false,
        "results": [{
            "command": command,
            "success": false,
            "output": message
        }]
    })
}

struct CommandOutput {
    code: i32,
    text: String,
}

fn execute(spec: &CommandSpec) -> CommandOutput {
    let mut command;
    if spec.privileged {
        let Some(helper) = privilege_helper() else {
            return CommandOutput {
                code: 127,
                text: "No supported privilege helper found (pkexec, doas, or sudo).".to_owned(),
            };
        };
        command = Command::new(helper);
        if !spec.env.is_empty() {
            command.arg("env");
            command.args(spec.env.iter().map(|(key, value)| format!("{key}={value}")));
        }
        command.arg(spec.program);
    } else {
        command = Command::new(spec.program);
        command.envs(spec.env.iter().copied());
    }
    let output = command.args(spec.args).output();
    match output {
        Ok(output) => command_output(output),
        Err(error) => CommandOutput {
            code: 127,
            text: format!("cannot start {}: {error}", spec.program),
        },
    }
}

fn command_output(output: Output) -> CommandOutput {
    let mut text = String::from_utf8_lossy(&output.stdout).into_owned();
    let stderr = String::from_utf8_lossy(&output.stderr);
    if !stderr.is_empty() {
        if !text.is_empty() && !text.ends_with('\n') {
            text.push('\n');
        }
        text.push_str(&stderr);
    }
    CommandOutput {
        code: output.status.code().unwrap_or(1),
        text,
    }
}

fn command_error(spec: &CommandSpec, output: &CommandOutput) -> String {
    let detail = output.text.trim();
    if detail.is_empty() {
        format!("{} exited with status {}", spec.display(), output.code)
    } else {
        detail.to_owned()
    }
}

fn privilege_helper() -> Option<&'static str> {
    ["pkexec", "doas", "sudo"]
        .into_iter()
        .find(|program| command_exists(program))
}

fn command_exists(program: &str) -> bool {
    env::var_os("PATH").is_some_and(|paths| {
        env::split_paths(&paths).any(|directory| {
            let path = directory.join(program);
            fs::metadata(path).is_ok_and(|metadata| {
                metadata.is_file() && metadata.permissions().mode() & 0o111 != 0
            })
        })
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn manager_modules_parse_their_native_update_formats() {
        assert_eq!(
            (fedora::parse_check)("Last metadata check\nfoo.x86_64 1.0 repo\n").unwrap(),
            ["foo.x86_64"]
        );
        assert_eq!((arch::parse_check)("foo 1.0 -> 2.0\n").unwrap(), ["foo"]);
        assert_eq!(
            (debian::parse_check)("Inst foo [1.0] (2.0 repo)\n").unwrap(),
            ["foo"]
        );
        assert_eq!(
            (suse::parse_check)("v | foo | package | 2.0 | x86_64 | repo\n").unwrap(),
            ["foo"]
        );
        assert_eq!(
            (alpine::parse_check)("foo-2.0 x86_64 {repo} [upgradable from: 1.0]\n").unwrap(),
            ["foo-2.0"]
        );
        assert_eq!(
            (void::parse_check)("foo-2.0 update x86_64 repo 10 5\n").unwrap(),
            ["foo-2.0"]
        );
        assert_eq!(
            (bsd::parse_pkg_check)("Upgrading foo from 1.0 to 2.0\n").unwrap(),
            ["foo"]
        );
        assert_eq!(
            (gentoo::parse_check)("[ebuild U ] app-misc/foo-2.0 [1.0]\n").unwrap(),
            ["app-misc/foo-2.0"]
        );
    }

    #[test]
    fn every_installer_package_family_has_a_backend() {
        assert_eq!(fedora::backend().check.program, "dnf");
        assert_eq!(alpine::backend().check.program, "apk");
        assert!(matches!(
            arch::backend().check.program,
            "checkupdates" | "pacman"
        ));
        assert_eq!(debian::backend().check.program, "apt-get");
        assert_eq!(suse::backend().check.program, "zypper");
        assert_eq!(gentoo::backend().check.program, "emerge");
        assert_eq!(void::backend().check.program, "xbps-install");
        assert_eq!(bsd::pkg_backend().check.program, "pkg");
        assert_eq!(bsd::openbsd_backend().check.program, "pkg_add");
        assert_eq!(bsd::netbsd_backend().check.program, "pkgin");
        assert_eq!(darwin::backend().check.program, "brew");
    }
}
