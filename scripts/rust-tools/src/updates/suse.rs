use super::{Backend, CommandSpec};

pub(super) fn backend() -> Backend {
    Backend::new(
        CommandSpec::new("zypper", &["--non-interactive", "list-updates"], false),
        parse_check,
        vec![
            CommandSpec::new("zypper", &["--non-interactive", "update", "-y"], true),
            CommandSpec::new("zypper", &["--non-interactive", "clean", "--all"], true),
        ],
        Some(vec![CommandSpec::new(
            "zypper",
            &["--non-interactive", "patch", "--category", "security", "-y"],
            true,
        )]),
    )
}

pub(super) fn parse_check(output: &str) -> Result<Vec<String>, String> {
    Ok(output
        .lines()
        .filter_map(|line| {
            let fields = line.split('|').map(str::trim).collect::<Vec<_>>();
            (fields.len() >= 6 && fields[0] == "v" && fields[1] != "Name")
                .then(|| fields[1].to_owned())
        })
        .collect())
}
