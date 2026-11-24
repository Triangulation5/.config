use super::{Backend, CommandSpec};

pub(super) fn pkg_backend() -> Backend {
    Backend::new(
        CommandSpec::new("pkg", &["upgrade", "--dry-run"], false),
        parse_pkg_check,
        vec![
            CommandSpec::new("pkg", &["upgrade", "-y"], true),
            CommandSpec::new("pkg", &["autoremove", "-y"], true),
        ],
        None,
    )
}

pub(super) fn openbsd_backend() -> Backend {
    Backend::new(
        CommandSpec::new("pkg_add", &["-u", "-n", "-s", "-v"], false),
        parse_openbsd_check,
        vec![CommandSpec::new("pkg_add", &["-u", "-I"], true)],
        None,
    )
}

pub(super) fn netbsd_backend() -> Backend {
    Backend::new(
        CommandSpec::new("pkgin", &["-p", "-l", "<", "list"], false),
        parse_pkgin_check,
        vec![CommandSpec::new("pkgin", &["-y", "upgrade"], true)],
        None,
    )
}

pub(super) fn parse_pkg_check(output: &str) -> Result<Vec<String>, String> {
    Ok(output
        .lines()
        .filter_map(|line| {
            let trimmed = line.trim();
            if let Some((name, _)) = trimmed.split_once(" -> ") {
                return name
                    .split_once(':')
                    .map_or(name, |(name, _)| name)
                    .split_whitespace()
                    .last()
                    .map(str::to_owned);
            }
            ["Upgrading ", "Installing ", "Reinstalling "]
                .iter()
                .find_map(|prefix| trimmed.strip_prefix(prefix))
                .and_then(|rest| rest.split_whitespace().next())
                .map(str::to_owned)
        })
        .collect())
}

fn parse_openbsd_check(output: &str) -> Result<Vec<String>, String> {
    Ok(output
        .lines()
        .filter_map(|line| {
            let line = line.trim();
            if let Some(package) = line.strip_prefix("Update ") {
                return package.split_whitespace().next().map(str::to_owned);
            }
            line.split_once(" -> ")
                .and_then(|(package, _)| package.split_whitespace().last())
                .map(str::to_owned)
        })
        .collect())
}

fn parse_pkgin_check(output: &str) -> Result<Vec<String>, String> {
    Ok(output
        .lines()
        .filter_map(|line| {
            let line = line.trim();
            if line.is_empty()
                || line.starts_with("calculating")
                || line.starts_with("Packages to be")
                || line.starts_with("Nothing to do")
                || line.starts_with("Package")
            {
                return None;
            }
            let token = line.split_whitespace().next()?;
            if token.contains("->") || token.ends_with(':') {
                return None;
            }
            token
                .chars()
                .any(|character| character.is_ascii_alphanumeric())
                .then(|| token.to_owned())
        })
        .collect())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pkgin_ignores_summary_lines_and_keeps_update_names() {
        assert_eq!(
            parse_pkgin_check("calculating dependencies...\nfoo-1.0\nPackages to be upgraded: 1\n")
                .unwrap(),
            ["foo-1.0"]
        );
    }

    #[test]
    fn pkg_check_reads_upgrade_rows() {
        assert_eq!(parse_pkg_check("    foo: 1.0 -> 2.0\n").unwrap(), ["foo"]);
    }
}
