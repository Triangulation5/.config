use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
pub(crate) struct Entry {
    #[serde(default)]
    pub(crate) image: String,
    #[serde(default)]
    pub(crate) thumb: String,
    #[serde(default)]
    pub(crate) file: String,
    #[serde(default)]
    pub(crate) preview: String,
    #[serde(default)]
    pub(crate) source: String,
    #[serde(default)]
    pub(crate) w: u32,
    #[serde(default)]
    pub(crate) h: u32,
}
