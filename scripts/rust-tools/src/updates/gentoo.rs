use super::{Backend, CommandSpec};

pub(super) fn backend() -> Backend {
    Backend::new(
        CommandSpec::new(
            "emerge",
            &[
                "--pretend",
                "--update",
                "--deep",
                "--with-bdeps=y",
                "@world",
            ],
            false,
        ),
        parse_check,
        vec![CommandSpec::new(
            "emerge",
            &[
                "--ask=n",
                "--update",
                "--deep",
                "--with-bdeps=y",
                "--newuse",
                "@world",
            ],
            true,
        )],
        None,
    )
    .note("Uses local Portage metadata; sync repositories before checking for the latest updates.")
}

pub(super) fn parse_check(output: &str) -> Result<Vec<String>, String> {
    Ok(output
        .lines()
        .filter_map(|line| {
            let line = line.trim();
            if !line.starts_with("[ebuild") && !line.starts_with("[binary") {
                return None;
            }
            line.split_once(']')?
                .1
                .split_whitespace()
                .next()
                .map(str::to_owned)
        })
        .collect())
}
