use super::{Backend, CommandSpec};

pub(super) fn backend() -> Backend {
    let check = if super::command_exists("checkupdates") {
        CommandSpec::new("checkupdates", &[], false)
    } else {
        CommandSpec::new("pacman", &["-Qu"], false)
    };
    Backend::new(
        check,
        parse_check,
        vec![CommandSpec::new("pacman", &["-Syu", "--noconfirm"], true)],
        None,
    )
    .check_success_codes(&[0, 2])
}

pub(super) fn parse_check(output: &str) -> Result<Vec<String>, String> {
    Ok(output
        .lines()
        .filter_map(|line| line.split_whitespace().next())
        .filter(|name| !name.starts_with("::"))
        .map(str::to_owned)
        .collect())
}
