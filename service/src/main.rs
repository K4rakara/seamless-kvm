#![feature(async_closure)]

#[macro_use] extern crate anyhow;
#[macro_use] extern crate lazy_static;
#[macro_use] extern crate serde;
extern crate libc;
extern crate regex;
extern crate serde_json;

mod config;
mod pci;

use std::process::{ Stdio };
use std::sync::{ Arc };
use std::sync::atomic::{ AtomicBool, Ordering };

use tokio::fs::{ self };
use tokio::process::{ Command };
use tokio::signal::unix::{ signal, SignalKind };
use tokio::sync::broadcast::{ channel };

use anyhow::{ Error };

#[tokio::main]
async fn main() -> Result<(), Error> {
    let config = config::load().await?;

    let specified_vm = {
        let specified_vm_name = fs::read_to_string("/tmp/seamless-kvm:specified-vm")
            .await
            .ok()
            .map(|string| string.replace("\n", ""))
            .unwrap_or(config.default_vm.clone()
                .ok_or(anyhow!("No VM was specified, and no default VM was configured."))?);
        let specified_vm = config.vms
            .get(&specified_vm_name)
            .ok_or(anyhow!("The specified vm {:?} does not exist!", specified_vm_name))?
            .clone();
        let _ = fs::remove_file("/tmp/seamless-kvm:specified-vm").await;
        specified_vm
    };

    let config_ = config.clone();
    let specified_vm_ = specified_vm.clone();
    let take = async move || -> Result<(), Error> {
        if specified_vm_.takeover.unwrap_or(false) {
            if let Some(takeover) = config_.takeover {
                if let Some(processes) = takeover.take.processes {
                    for process in processes.iter() {
                        Command::new("/usr/bin/pkill")
                            .arg(process)
                            .stdout(Stdio::inherit())
                            .stderr(Stdio::inherit())
                            .stdin(Stdio::inherit())
                            .output()
                            .await?;
                    }
                }

                if let Some(services) = takeover.take.services {
                    for service in services.iter() {
                        Command::new("/usr/bin/systemctl")
                            .arg("stop")
                            .arg(service)
                            .stdout(Stdio::inherit())
                            .stderr(Stdio::inherit())
                            .stdin(Stdio::inherit())
                            .output()
                            .await?;
                    }
                }

                if let Some(pci) = takeover.take.pci {
                    for pci in pci.iter() {
                        pci.rebind_vfio().await?;
                    }
                }
            }
        }

        Ok::<_, Error>(())
    };

    let (vm_kill_sender, mut vm_kill_receiver) = channel::<()>(1);
    let (vm_done_sender, mut vm_done_receiver) = channel::<()>(1);
    let vm_kill_sender_ = vm_kill_sender.clone();
    let vm_kill_sender__ = vm_kill_sender.clone();

    let already_returned = Arc::new(AtomicBool::new(false));

    let already_returned_ = already_returned.clone();
    let ret = async move |config: config::Config, specified_vm: config::ConfigVm| -> Result<(), Error> {
        if !already_returned_.load(Ordering::SeqCst) {
            already_returned_.store(true, Ordering::SeqCst);

            let _ = vm_kill_sender.send(());
            vm_done_receiver.recv().await?;

            if specified_vm.takeover.unwrap_or(false) {
                if let Some(takeover) = config.takeover {
                    if let Some(pci) = takeover.r#return.pci {
                        for pci in pci.iter() {
                            pci.remove().await?;
                        }
                    }

                    fs::write("/sys/bus/pci/rescan", "1").await?;

                    if let Some(services) = takeover.r#return.services {
                        for service in services.iter() {
                            Command::new("/usr/bin/systemctl")
                                .arg("stop")
                                .arg(service)
                                .stdout(Stdio::inherit())
                                .stderr(Stdio::inherit())
                                .stdin(Stdio::inherit())
                                .output()
                                .await?;
                        }
                    }
                }
            }

            Ok::<_, Error>(())
        } else {
            Ok::<_, Error>(())
        }
    };

    tokio::spawn(async move {
        signal(SignalKind::terminate())?.recv().await;
        vm_kill_sender_.send(())?;
        Ok::<_, Error>(())
    });

    tokio::spawn(async move {
        signal(SignalKind::terminate())?.recv().await;
        vm_kill_sender__.send(())?;
        Ok::<_, Error>(())
    });

    take().await?;
    
    let specified_vm_ = specified_vm.clone();
    let vm_task = tokio::spawn(async move {
        let mut child = Command::new("/usr/bin/sudo")
            .arg("-u")
            .arg(specified_vm_.user.unwrap_or("root".to_owned()))
            .arg(specified_vm_.exec.unwrap_or("echo".to_owned()))
            .stdin(Stdio::piped())
            .stdout(Stdio::inherit())
            .stderr(Stdio::inherit())
            .spawn()?;

        tokio::select! {
            _ = child.wait() => {
                let _ = vm_done_sender.send(());
                Ok::<_, Error>(())
            },
            _ = vm_kill_receiver.recv() => {
                child.kill().await?;
                let _ = vm_done_sender.send(());
                Ok::<_, Error>(())
            }
        }
    });

    vm_task.await??;

    ret(config, specified_vm).await?;

    Ok(())
}
