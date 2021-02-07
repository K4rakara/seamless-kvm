extern crate tokio;

extern crate anyhow;
extern crate serde;
extern crate serde_json;

use crate::pci;

use std::collections::{ HashMap };

use tokio::fs::{ self };

use anyhow::{ Error };

use pci::{ Pci };

#[serde(rename_all = "kebab-case")]
#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct ConfigTakeoverGroup {
    pub processes: Option<Vec<String>>,
    pub services: Option<Vec<String>>,
    pub pci: Option<Vec<Pci>>,
}

#[serde(rename_all = "kebab-case")]
#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct ConfigTakeover {
    pub take: ConfigTakeoverGroup,
    pub r#return: ConfigTakeoverGroup,
}

#[serde(rename_all = "kebab-case")]
#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct ConfigVm {
    pub user: Option<String>,
    pub exec: Option<String>,
    pub takeover: Option<bool>,
}

#[serde(rename_all = "kebab-case")]
#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct Config {
    pub takeover: Option<ConfigTakeover>,
    pub vms: HashMap<String, ConfigVm>,
    pub default_vm: Option<String>,
}

pub async fn load() -> Result<Config, Error> {
    Ok(serde_json::from_str::<'_, Config>(
        &fs::read_to_string("/etc/seamless-kvm").await?)?)
}
