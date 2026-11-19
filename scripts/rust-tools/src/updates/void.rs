use super::{Backend, CommandSpec};

pub(super) fn backend() -> Backend {
    Backend::new(
        CommandSpec::new("xbps-install", &["-M", "-u", "-n"], false),
        parse_check,
        vec![CommandSpec::new("xbps-install", &["-S", "-u", "-y"], true)],
        None,
    )
}

pub(super) fn parse_check(output: &str) -> Result<Vec<String>, String> {
    Ok(output
        .lines()
        .filter_map(|line| {
            let mut fields = line.split_whitespace();
            let package = fields.next()?;
            let action = fields.next()?;
            matches!(action, "update" | "install" | "reinstall").then(|| package.to_owned())
        })
        .collect())
}
