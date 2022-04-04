# Swizzin installer for Appbox on the Ubuntu 20.04 app!
Finally you can install Swizzin on appbox! I decided to depreciate the appbox_installer as Swizzin seems to cover almost everything and is constantly updated.

## How to run
1. Install the [Ubuntu 20.04 app](https://www.appbox.co/appstore/app/210)

2. Connect to your Ubuntu either through SSH or by the No VNC WebUI (and clicking the "Applications" menu, then "Terminal Emulator")

3. Enter the following `sudo bash -c "bash <(curl -Ls https://raw.githubusercontent.com/coder8338/appbox_swizzin_installer/Ubuntu_20.04/swizzin_installer.sh)"`

## Pre-installed apps
The script will pre-install sonarr, radarr & panel apps.

## Requesting additional apps
You can request new apps & features here: https://feathub.com/liaralabs/swizzin

## How to manage apps
Apps can be managed through the Swizzin panel or Swizzin's built-in CLI app.

### Using Swizzin's built-in CLI app called box
The box app is really cool, as it allows you to install and remove apps really quickly and easily.

**Note:** I have added overseer to the install options.

To enter the box app interactively simply type the following into your terminal:

`sudo box`

You can read about how to use box to do even more things here: https://docs.swizzin.net/getting-started/box-basics/

For example to start an app use:

`sudo box start <app name>`

to stop an app:

`sudo box stop <app name>`

to disable an app:

`sudo box disable <app name>`

### Installing/uninstalling apps

You can either use the interactive CLI with `sudo box` or;

To list all available apps:
`sudo box list`

To install a new app:
`sudo box install <app name>`
  
To uninstall an app:
`sudo box uninstall <app name>`
