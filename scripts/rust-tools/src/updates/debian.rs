use super::{Backend, CommandSpec};

const NONINTERACTIVE: &[(&str, &str)] = &[("DEBIAN_FRONTEND", "noninteractive")];

pub(super) fn backend() -> Backend {
    Backend::new(
        CommandSpec::new("apt-get", &["--just-print", "upgrade"], false),
        parse_check,
        vec![
            CommandSpec::new(
                "apt-get",
                &["upgrade", "-y", "-o", "Dpkg::Options::=--force-confold"],
                true,
            )
            .with_env(NONINTERACTIVE),
            CommandSpec::new("apt-get", &["autoremove", "-y"], true).with_env(NONINTERACTIVE),
            CommandSpec::new("apt-get", &["clean"], true).with_env(NONINTERACTIVE),
        ],
        None,
    )
}

pub(super) fn parse_check(output: &str) -> Result<Vec<String>, String> {
    Ok(output
        .lines()
        .filter_map(|line| {
            let mut fields = line.split_whitespace();
            (fields.next()? == "Inst").then(|| fields.next().map(str::to_owned))?
        })
        .collect())
}
