use super::{Backend, CommandSpec};

pub(super) fn backend() -> Backend {
    Backend::new(
        CommandSpec::new("dnf", &["check-update"], false),
        parse_check,
        vec![
            CommandSpec::new("dnf", &["upgrade", "-y"], true),
            CommandSpec::new("dnf", &["autoremove", "-y"], true),
            CommandSpec::new("dnf", &["clean", "all"], true),
        ],
        Some(vec![
            CommandSpec::new("dnf", &["upgrade-minimal", "-y"], true),
            CommandSpec::new("dnf", &["autoremove", "-y"], true),
            CommandSpec::new("dnf", &["clean", "all"], true),
        ]),
    )
    .check_success_codes(&[0, 100])
    .reboot_check(CommandSpec::new("needs-restarting", &["-r"], false))
}

pub(super) fn parse_check(output: &str) -> Result<Vec<String>, String> {
    Ok(output
        .lines()
        .filter_map(|line| {
            let line = line.trim();
            if line.is_empty()
                || line.starts_with("Last metadata")
                || line.starts_with("Obsoleting")
            {
                return None;
            }
            let mut fields = line.split_whitespace();
            let package = fields.next()?;
            (fields.next().is_some() && fields.next().is_some()).then(|| package.to_owned())
        })
        .collect())
}
