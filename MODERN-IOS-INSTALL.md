# Installation Guide (SideStore)
> [!WARNING]
> For this installation guide, it is **required** to have a computer with Administrator access (if you are on Windows), as this guide will require installing software on your computer to sideload Geode, and to obtain a pairing file for **SideStore**.
> \
> This guide assumes you will be installing SideStore. Using enterprise (aka free) certificates to install SideStore **will not work**, as the use of a computer is required to install SideStore.

> [!NOTE]
> Support for iOS 26.4 is experimental for SideStore. Geode will work on this version, but expect some bugs for SideStore.

| Supported on | Requires Computer? | Mod Support | Price |
|--------------|--------------------|-------------------|-------|
| iOS 16 to 17.4 and above | Yes | *Partial* to *Full* (*Partial* on JIT-Less, only 5% not supported) | Free |

## Prerequisites
- A computer running Windows, macOS or Linux
- [iTunes](https://apps.microsoft.com/detail/9pb2mz1zmb1s) **For windows only**
- **usbmuxd** on **devices running Linux or Chromebooks only** (search how to get it for your distro.)
- [LocalDevVPN](https://apps.apple.com/us/app/localdevvpn/id6755608044) from the App Store
- [iloader](https://github.com/nab138/iloader/releases) to install SideStore
- An Apple ID (A secondary Apple ID is recommended, though it's not necessarily required)
- USB Cable to connect your device (Lightning / USB C)
- Full version of Geometry Dash installed
- An internet connection
- A passcode on your device (required for pairing file)
- IPA file of Geode launcher from [Releases](https://github.com/geode-sdk/ios-launcher/releases/latest) (If you don't want to use this, follow the **AltSource** method below)

## Install SideStore
1. Connect your iDevice (phone) to your computer via cable and trust the computer on your iDevice when prompted (trusting the computer is an important step!).
2. Download iloader on your computer and LocalDevVPN on your iDevice as mentioned in the **Prerequisites** section.
3. Sign in with your Apple ID in iloader.
4. In the **Installers** section of iloader, click "SideStore (Stable)" if you are below **iOS 26.4**. If not, click "SideStore (Nightly)."
5. You will most likely get an **Untrusted Developer** error. To fix this, go to Settings > General > VPN and Device Management > Your Apple ID and press Trust. After doing this, move to the **Enabling Developer Mode** section below.
> [!NOTE]
> The Developer Mode option will not show up if you do not install SideStore! It will only appear when you install SideStore. So make sure to follow the **Install SideStore** section first, then try to enable Developer Mode.

### Enabling Developer Mode
- You will need to enable **Developer Mode** in order to launch third party apps like SideStore **after you install them**, otherwise you will encounter this error when attempting to launch SideStore or any sideloaded app:
- ![](screenshots/install-1.png)
- To enable **Developer Mode** on your iOS device, navigate to `Settings -> Privacy & Security -> Developer Mode`. Do note that this will require restarting your device.
- ![](https://faq.altstore.io/~gitbook/image?url=https%3A%2F%2F2606795771-files.gitbook.io%2F%7E%2Ffiles%2Fv0%2Fb%2Fgitbook-x-prod.appspot.com%2Fo%2Fspaces%252FAfe8qEztjcTjsjjaMBY2%252Fuploads%252FWSvXhUTj8UZyGd1ex652%252FFcejvMRXgAE8k3R.jpg%3Falt%3Dmedia%26token%3D5e380cd0-be4e-406a-914b-8fa0519e1196&width=768&dpr=2&quality=100&sign=8860eb96&sv=2)
- After your device restarts, you will be prompted to "Turn on Developer Mode", press "Turn On", and **Developer Mode** should be enabled!

### Installing Geode through SideStore
> [!NOTE]
> You will need to **refresh** both SideStore and Geode every week. Otherwise, you will not be able to run the app.
> Find how to do this in the Conclusion.

1: Navigate to the **My Apps** tab, and tap the `+` button to add an app. Select the IPA for the Geode app, and the Geode app should appear on your home screen!
![](screenshots/install-sidestore.png)

2: Navigate to the **Sources** tab, and tap the `+` button to add the Geode AltSource, then simply select it in the recommended sources (it will be labeled Geode). Now go to the **Browse** tab, then **Games**, and you will find Geode. Press `Free` to install it.
![](screenshots/altsource-install.png)
> [!NOTE]
> The AltSource method may recieve updates *later*, and should only be used if you are okay with this.

# Launch Geode
## JIT-Less
1. Press **"Enable JIT-Less"**.
2. Press **"Import SideStore Certificate"**.
3. Press **"Test JIT-Less Mode"** to test if JIT-less mode works properly.
4. Press **"Launch"**.

![](screenshots/jitless-sidestore.png)

## JIT
> [!TIP]
> Skip this **if you're on iOS 16**. SideStore lets you enable JIT **directly from it**. To do so, go to the **My Apps** section in SideStore, hold Geode, and press **"Enable JIT"** (you need to have LocalDevVPN enabled for this).
> If you are on iOS **17.0.1 - 17.3.1** scroll down to the bottom for your JIT guide.

> [!NOTE]
> For the first time setup, you will need a computer to get a pairing file. You will use iloader to get it.
> Also, StikDebug will not give you any update notification unless you are tracking the Github. It's recommended to use the AltSource so SideStore will notify you about an update.
### Installing StikDebug
1. Get the latest StikDebug IPA file from [Releases](https://github.com/StephenDev0/StikDebug/releases) and install it via SideStore, or via AltSource. Follow the same guide for Geode altsource, only this time picking **Stikdebug Repository** Install by going to **Browse** then **Other** then **StikDebug** and then pressing **Free**
2. Connect your iDevice back to your computer via cable and then open iloader. In iloader, find **Manage Pairing File**. Click on it and click **Place** near StikDebug. This will place the pairing file to StikDebug, which is essential for StikDebug to function.
3. Connect to LocalDevVPN
4. Launch StikDebug.
5. Check for any extra steps and follow them if needed below.
6. Now you should be set! Simply tap **Launch** in the Geode launcher to use Geode with JIT.

### Required Extra Steps for iOS 26
1. Go to StikDebug settings
2. Enable **Silent Audio** and **Background Location**. Scroll down to see if your device is reported as **TXM** or **Non TXM**. If it is reported as Non TXM, turn on **Always Run Scripts**.
3. Import a certifcate in settings (follow step 2 Jit-less)
4. When running for the first time, allow StikDebug to use your location.

### Launching on cellular
1. Turn on **LocalDevVPN**
2. Turn on **Airplane mode**
3. Press **Launch** like normal
4. Once Geode has started, turn off **Airplane mode** and **LocalDevVPN**

## Installing SideJITServer (17.0.1 - 17.3.1)

Follow the instructions as listed here
https://github.com/nythepegasus/SideJITServer

You will need to be nearby your computer to use this, StikDebug does not and will never work on 17.0.1 - 17.3.1


## Conclusion
You should now be able to run Geometry Dash with Geode! You can install mods by tapping the **Geode** button on the bottom of the menu, and browse for mods to install!
> [!TIP]
> To refresh Geode, connect to LocalDevVPN, then tap Refresh All.
