extern crate tokio;

extern crate anyhow;
extern crate lazy_static;
extern crate libc;
extern crate regex;
extern crate serde;

use std::path::{ Path };

use tokio::fs::{ self };
use tokio::process::{ Command };

use anyhow::{ Error };
use regex::{ Regex };

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct Pci ( pub String );

impl Pci {
    /// Rebinds a PCI device from its current driver to the VFIO driver.
    pub async fn rebind_vfio(&self) -> Result<(), Error> {
        let device_id = {
            lazy_static! {
                static ref REGEX: Regex = Regex::new(r#"(?im)^([a-z0-9][a-z0-9]:[a-z0-9][a-z0-9]\.[a-z0-9]).*\[([a-z0-9]{4}):([a-z0-9]{4})\].*$"#).unwrap();
            }
            let output = String::from_utf8(
                Command::new("/usr/bin/lspci")
                    .arg("-nns")
                    .arg(&self.0)
                    .output()
                    .await?
                    .stdout)?;
            match REGEX.captures(&output) {
                Some(caps) => format!("{} {}",
                    caps.get(2).unwrap().as_str(),
                    caps.get(3).unwrap().as_str()),
                None => Err(anyhow!("Regex didn't match {:?}.", output))?,
            }
        };

        let new_id_file = Path::new("/sys/bus/pci/drivers/vfio-pci/new_id");
        let unbind_file = Path::new("/sys/bus/pci/devices/")
            .join(&self.0)
            .join("driver/unbind");
        let bind_file = Path::new("/sys/bus/pci/drivers/vfio-pci/bind");
        let remove_id_file = Path::new("/sys/bus/pci/drivers/vfio-pci/remove_id");

        fs::write(new_id_file, &device_id).await?;
        fs::write(unbind_file, &self.0).await?;
        fs::write(bind_file, &self.0).await?;
        fs::write(remove_id_file, &device_id).await?;

        Ok(())
    }

    /// Removes a PCI device, allowing it to be rebound by its default driver.
    pub async fn remove(&self) -> Result<(), Error> {
        let remove_file = Path::new("/sys/bus/pci/devices/")
            .join(&self.0)
            .join("remove");
        fs::write(remove_file, "1").await?;
        Ok(())
    }
}
