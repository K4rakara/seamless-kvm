extern crate anyhow;

use std::fs::{ self };
use std::env::{ args };
use std::process::{ Command, Stdio };

use anyhow::{ Error };

fn main() -> Result<(), Error> {
    if let Some(vm) = args().next() {
        fs::write("/tmp/seamless-kvm:specified-vm", vm)?;
    }
    Command::new("/usr/bin/systemctl")
        .arg("start")
        .arg("seamless-kvm.service")
        .stdin(Stdio::inherit())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .output()?;
    Ok(())
}
