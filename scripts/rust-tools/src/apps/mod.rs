mod appimage;
mod archive;
mod desktop;
mod extract;
mod files;
mod icons;
mod registry;
mod slug;

use std::ffi::OsString;

pub(crate) fn app_install(operation: &str, args: &[OsString]) -> Result<(), String> {
    archive::app_install(operation, args)
}

pub(crate) fn appimage_install(operation: &str, args: &[OsString]) -> Result<(), String> {
    appimage::appimage_install(operation, args)
}
