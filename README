# Seamless KVM

This tool provides a script and systemd service that allows you to seamlessly
transition between a Linux desktop and a KVM with GPU passthrough.

### Why?

I recently (2021) got my brother to start using Linux (Arch, btw), but
some of the multiplayer games he likes to play with his friends require EAC or 
some other anticheat engine that prevents the game from being run under Linux
using Proton or Lutris.

If he had 2 GPUs, I could simply pass one of them to a Windows KVM and one to
Linux.

Of course, it isn't that simple. He only has one GPU, meaning I can't do
passthrough unless I'm not using it (IE X11 isn't running).

So, my solution was to create a systemd service that runs as root, stops
the session manager service (and thereby killing X11), starts the VM with GPU
passthrough, waits for the VM to exit, and then finally restarts the session
manager service.

I decided to also allow this to be somewhat configurable, which you can see in 
the config section.

### Usage

Simply start the service normally to start the service with the default VM:

```sh
sudo systemctl start seamless-kvm.service
```

Alternatively, `seamless-kvm-start` can be ran to start the service with a
specific VM:

```sh
sudo seamless-kvm-start some-vm
```

### Config

`seamless-kvm` can be configured using a JSON file in
`/etc/seamless-kvm/config.json`:

```jsonc
{
    "takeover": {
        "take": {
            // A list of processes to kill when the VM "takes over".
            "process": [
                "htop" // For example
            ],
            // A list of services to stop when the VM "takes over".
            "service": [
                "sddm" // For example
            ]
        },
        "return": {
            // A list of processes to run when the VM stops "taking over".
            // Unsupported as of now, but still recognized.
            "process": [
                "htop" // For example
            ],
            // A list of services to start when the VM stops "taking over".
            "service": [
                "sddm" // For example
            ]
        }
    },
    "vms": {
        // The name of the VM to use when no VM is specified.
        "default": "windows",
        "windows": {
            // The user to execute the VM as. In 99.99% of cases THIS SHOULD
            // NOT BE ROOT.
            "user": "user",
            // The absolute path to a script that can be used to start the VM.
            "exec": "/home/user/vms/boot.sh",
            // If true, the VM will "take over", stopping the services and
            // processes specified by `.takeover` when it is ran.
            "takeover": true
        }
    }
}
```
