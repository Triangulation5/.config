use super::{Backend, CommandSpec};

pub(super) fn backend() -> Backend {
    Backend::new(
        CommandSpec::new("brew", &["outdated", "--json=v2"], false),
        parse_check,
        vec![CommandSpec::new("brew", &["upgrade"], false)],
        None,
    )
}

fn parse_check(output: &str) -> Result<Vec<String>, String> {
    let value = serde_json::from_str::<serde_json::Value>(output)
        .map_err(|error| format!("invalid Homebrew JSON: {error}"))?;
    Ok(["formulae", "casks"]
        .into_iter()
        .flat_map(|key| {
            value
                .get(key)
                .and_then(|items| items.as_array())
                .into_iter()
                .flatten()
        })
        .filter_map(|item| {
            item.get("name")
                .or_else(|| item.get("token"))
                .and_then(|name| name.as_str())
                .map(str::to_owned)
        })
        .collect())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn brew_check_reads_formulae_and_casks() {
        assert_eq!(
            parse_check(r#"{"formulae":[{"name":"foo"}],"casks":[{"token":"bar"}]}"#).unwrap(),
            ["foo", "bar"]
        );
    }
}
