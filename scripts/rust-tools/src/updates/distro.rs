use std::{env, fs, path::Path};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(super) enum Distro {
    Fedora,
    Alpine,
    Arch,
    Debian,
    Suse,
    Gentoo,
    Void,
    FreeBsd,
    OpenBsd,
    NetBsd,
    DragonFly,
    Darwin,
    Unknown,
}

pub(super) fn detect() -> Distro {
    let release_path = env::var_os("SILHOUETTE_OS_RELEASE")
        .map_or_else(|| Path::new("/etc/os-release").to_path_buf(), Into::into);
    let release = fs::read_to_string(release_path).unwrap_or_default();
    detect_from(&release, env::consts::OS)
}

fn detect_from(release: &str, os: &str) -> Distro {
    let mut id = String::new();
    let mut id_like = String::new();
    for line in release.lines() {
        let Some((key, raw_value)) = line.split_once('=') else {
            continue;
        };
        let value = raw_value
            .trim()
            .trim_matches('"')
            .trim_matches('\'')
            .to_ascii_lowercase();
        match key {
            "ID" => id = value,
            "ID_LIKE" => id_like = value,
            _ => {}
        }
    }
    let identity = format!(" {id} {id_like} ");
    if ["fedora", "rhel", "centos"]
        .iter()
        .any(|token| identity.split_whitespace().any(|value| value == *token))
    {
        Distro::Fedora
    } else if identity.split_whitespace().any(|value| value == "alpine") {
        Distro::Alpine
    } else if identity.split_whitespace().any(|value| value == "artix")
        || identity.split_whitespace().any(|value| value == "arch")
    {
        Distro::Arch
    } else if ["debian", "ubuntu"]
        .iter()
        .any(|token| identity.split_whitespace().any(|value| value == *token))
    {
        Distro::Debian
    } else if identity.split_whitespace().any(|value| value == "suse")
        || identity
            .split_whitespace()
            .any(|value| value.starts_with("opensuse"))
    {
        Distro::Suse
    } else if identity.split_whitespace().any(|value| value == "gentoo") {
        Distro::Gentoo
    } else if identity.split_whitespace().any(|value| value == "void") {
        Distro::Void
    } else {
        match os {
            "freebsd" => Distro::FreeBsd,
            "openbsd" => Distro::OpenBsd,
            "netbsd" => Distro::NetBsd,
            "dragonfly" => Distro::DragonFly,
            "macos" => Distro::Darwin,
            _ => Distro::Unknown,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn distro_detection_matches_installer_families_and_aliases() {
        assert_eq!(
            detect_from("ID=artix\nID_LIKE=arch\n", "linux"),
            Distro::Arch
        );
        assert_eq!(detect_from("ID=arch\n", "linux"), Distro::Arch);
        assert_eq!(
            detect_from("ID=rocky\nID_LIKE=\"rhel fedora\"\n", "linux"),
            Distro::Fedora
        );
        assert_eq!(detect_from("ID=ubuntu\n", "linux"), Distro::Debian);
        assert_eq!(detect_from("", "freebsd"), Distro::FreeBsd);
        assert_eq!(detect_from("", "macos"), Distro::Darwin);
        assert_eq!(detect_from("ID=unknown\n", "linux"), Distro::Unknown);
    }
}
