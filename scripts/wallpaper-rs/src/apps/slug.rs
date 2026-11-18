pub(super) fn strip_tokens(value: &str) -> String {
    let value = value
        .strip_suffix(".AppImage")
        .or_else(|| value.strip_suffix(".appimage"))
        .unwrap_or(value);
    value
        .split(['.', '_', '-'])
        .filter(|token| !token.is_empty())
        .filter(|token| {
            !matches!(
                token.to_ascii_lowercase().as_str(),
                "x86_64"
                    | "amd64"
                    | "x86"
                    | "i386"
                    | "i686"
                    | "aarch64"
                    | "arm64"
                    | "armhf"
                    | "arm"
                    | "linux"
                    | "gnu"
                    | "glibc"
                    | "musl"
                    | "static"
                    | "portable"
            ) && !is_version_token(token)
        })
        .collect::<Vec<_>>()
        .join(" ")
}

fn is_version_token(token: &str) -> bool {
    let token = token.strip_prefix(['v', 'V']).unwrap_or(token);
    !token.is_empty()
        && token
            .split('.')
            .all(|part| !part.is_empty() && part.bytes().all(|byte| byte.is_ascii_digit()))
}

pub(super) fn slugify(value: &str) -> String {
    let mut slug = String::new();
    let mut separator = false;
    for character in strip_tokens(value).chars() {
        if character.is_ascii_alphanumeric() {
            if separator && !slug.is_empty() {
                slug.push('-');
            }
            slug.push(character.to_ascii_lowercase());
            separator = false;
        } else {
            separator = true;
        }
    }
    if slug.is_empty() {
        "app".to_owned()
    } else {
        slug
    }
}

pub(super) fn prettify(value: &str) -> String {
    let stripped = strip_tokens(value);
    if stripped.is_empty() {
        value
            .strip_suffix(".AppImage")
            .or_else(|| value.strip_suffix(".appimage"))
            .unwrap_or(value)
            .to_owned()
    } else {
        stripped
    }
}

pub(super) fn channelless(value: &str) -> String {
    value
        .split('-')
        .filter(|token| {
            !matches!(
                *token,
                "nightly" | "beta" | "alpha" | "canary" | "preview" | "insiders" | "dev" | "stable"
            ) && !token.strip_prefix("rc").is_some_and(|suffix| {
                suffix.is_empty() || suffix.bytes().all(|b| b.is_ascii_digit())
            })
        })
        .collect::<Vec<_>>()
        .join("-")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn slug_rules_drop_version_and_architecture_tokens() {
        assert_eq!(slugify("Krita-5.2.0-x86_64.AppImage"), "krita");
        assert_eq!(slugify("1Password-v2-linux.AppImage"), "1password");
        assert_eq!(prettify("v2ray-linux.AppImage"), "v2ray");
    }

    #[test]
    fn channel_matching_removes_release_channels_only() {
        assert_eq!(channelless("app-nightly-x86"), "app-x86");
        assert_eq!(channelless("app-rc2"), "app");
        assert_eq!(channelless("app-v2"), "app-v2");
    }
}
