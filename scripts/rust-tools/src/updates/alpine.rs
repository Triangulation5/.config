use super::{Backend, CommandSpec};

pub(super) fn backend() -> Backend {
    Backend::new(
        CommandSpec::new("apk", &["list", "--upgradable"], false),
        parse_check,
        vec![CommandSpec::new("apk", &["upgrade"], true)],
        None,
    )
}

pub(super) fn parse_check(output: &str) -> Result<Vec<String>, String> {
    Ok(output
        .lines()
        .filter(|line| line.contains("[upgradable from:"))
        .filter_map(|line| line.split_whitespace().next())
        .map(str::to_owned)
        .collect())
}
