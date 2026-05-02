# Installation Guide (LiveContainer)

| Supported on | Requires Computer? | Mod Support | Price |
|--------------|--------------------|-------------------|-------|
| iOS 15 and above | Yes | *Partial* to *Full* (*Partial* on JIT-Less, only 5% not supported) | Free |

This tutorial is for people that use LiveContainer to bypass Apple's 3 active app and 10 app ID limit.

> [!NOTE]
> You will have to refresh LiveContainer in SideStore weekly.
## Prerequisites
- A computer running Windows, macOS or Linux
- [iTunes](https://apps.microsoft.com/detail/9pb2mz1zmb1s) **For windows only**
- **usbmuxd** on **devices running Linux or Chromebooks only** (search how to get it for your distro.)
- [LocalDevVPN](https://apps.apple.com/us/app/localdevvpn/id6755608044) from the App Store
- [iLoader](https://github.com/nab138/iloader/releases) to install SideStore
- An Apple ID (A secondary Apple ID is recommended, though it's not necessarily required)
- USB Cable to connect your device (Lightning / USB C)
- Full version of Geometry Dash installed
- An internet connection
- A passcode on your device (required for pairing file)
- IPA file of Geode launcher from [Releases](https://github.com/geode-sdk/ios-launcher/releases/latest) (If you don't want to use this, follow the **AltSource** method below)

## Install LiveContainer
1. Connect your phone to your computer via cable and trust the computer on your phone when prompted (trusting the computer is an important step!)
2. Download iLoader on your computer and LocalDevVPN on your iDevice as mentioned in the **Prerequisites** section
3. Sign in with your Apple ID in iLoader
4. In the **Installers** section in iLoader, click "LiveContainer+SideStore (Stable)" if you are below **iOS 26.4**, if not, click, otherwise click "LiveContainer+SideStore (Nightly).
5. You will most likely get an **Untrusted Developer** error. To fix this, go to Settings > General > VPN and Device Management > Your Apple ID and press Trust. After doing this, move to the **Enabling Developer Mode** section below.
> [!NOTE]
> The Developer Mode option will not show up if you do not install SideStore! It will only appear when you install SideStore. So make sure to follow the **Install SideStore** section first, then try to enable Developer Mode.

### Enabling Developer Mode
- You will need to enable **Developer Mode** in order to launch third party apps like SideStore **after you install them**, otherwise you will encounter this error when attempting to launch SideStore or any sideloaded app:
- ![](screenshots/install-1.png)
- To enable **Developer Mode** on your iOS device, navigate to `Settings -> Privacy & Security -> Developer Mode`. Do note that this will require restarting your device.
- ![](https://faq.altstore.io/~gitbook/image?url=https%3A%2F%2F2606795771-files.gitbook.io%2F%7E%2Ffiles%2Fv0%2Fb%2Fgitbook-x-prod.appspot.com%2Fo%2Fspaces%252FAfe8qEztjcTjsjjaMBY2%252Fuploads%252FWSvXhUTj8UZyGd1ex652%252FFcejvMRXgAE8k3R.jpg%3Falt%3Dmedia%26token%3D5e380cd0-be4e-406a-914b-8fa0519e1196&width=768&dpr=2&quality=100&sign=8860eb96&sv=2)
- After your device restarts, you will be prompted to "Turn on Developer Mode", press "Turn On", and **Developer Mode** should be enabled!

## Setup LiveContainer
![](https://livecontainer.github.io/img/lc_sidestore/4.jpg)
![](https://livecontainer.github.io/img/lc_sidestore/5.jpg)
![](https://livecontainer.github.io/img/lc_sidestore/6.jpg)
![](https://livecontainer.github.io/img/lc_sidestore/7.jpg)

## Add Geode AltSource
1. Go to LiveContainer's **Sources** tab.
2. Tap `+`.
3. Copy and paste `https://ios-repo.geode-sdk.org/altsource/main.json` then add it.

## Set Up LiveContainer for Geode (JIT-Less)
> [!WARNING]
> If you have set Geode as a **shared app** in LiveContainer, convert it to a **private app**. Otherwise, Geode **will not be able to detect the certificate**.

1. Install Geode using LiveContainer either by IPA or Altsource (Sources -> Geode -> Install)
2. Hold on the app and go to the Geode app settings in LiveContainer, then **enable these settings:**

- **Fix File Picker**
- **Fix Local Notification**
- **Use LiveContainer's Bundle ID**
- **Don't Inject TweakLoader**
- **Don't Load TweakLoader**

After these steps:

3. Tap on **Settings** on the bottom right
4. Tap **Import Certificate from SideStore**
5. Get back to LiveContainer and scroll down until you see the **version of LiveContainer**
6. Tap on the **version text** 5 times
7. Scroll down and tap **Export Cert** then return to **Apps** in the bottom left

![](./screenshots/livecontainer-jitless.png)

Finally, the last steps are:

9. Open Geode.
10. Press **Verify Geometry Dash**
11. Press **Download**
12. Open Settings
13. Make sure **Enable JIT-Less** is on.
14. Press **Test JIT-Less Mode** to test if JIT-less mode works properly.
15. Exit settings & press **Launch**


## Set Up LiveContainer for Geode (JIT)
> [!TIP]
> If you are on iOS 16 or below, do steps 3 and 4 below, but this time, select SideStore.
> If you are on iOS 17.0.1 - 17.3.1 follow the guide at the very bottom
1. Install Geode using LiveContainer
2. Install and configure **StikDebug** (steps below)
3. Hold down **Geode**, press Settings and turn these on:
- **Launch with JIT**
- **Don't Inject TweakLoader**
- **Don't Load TweakLoader**
![](./screenshots/livecontainer.png)
4. Go to LiveContainer settings, and select **StikDebug** (not `StikDebug (Another LiveContainer)`)
### Get StikDebug
1. Get the latest StikDebug IPA file from [Releases](https://github.com/StephenDev0/StikDebug/releases) and install it via **Sidestore** (not LiveContainer) or via AltSource. Go to **Sources** in Sidestore, tap "+" then tap **Stikdebug Repository** Install by going to **Browse** then **Other** then **StikDebug** and then pressing **Free**.
> [!NOTE]
> StikDebug will not give you any update notification unless you are tracking the Github. It's recommended to use the AltSource so SideStore will notify you about an update.
2. Connect your phone back to your computer via cable and then open iLoader. In iLoader, find **Manage Pairing File**. Click on it and click **Place** near StikDebug. This will place the pairing file to StikDebug, which is essential for StikDebug to function.
3. Connect to LocalDevVPN
3. Launch StikDebug.
4. Check for any extra steps and follow them if needed below.
### Required Extra Steps for iOS 26
> [!WARNING]
> You will also need to enable **Use LiveContainer's Bundle ID** as iOS 26 requires a certificate for JIT, otherwise you will be stuck at a black screen.

1. Download the [TuliphookJIT.js](https://github.com/geode-sdk/ios-launcher/blob/main/TuliphookJIT.js) script (click on the script name, then press the download button on the redirected page to download it)
2. On the Geode **app settings** in **LiveContainer**, find the **JIT Launch Script** option and select the **Geode.js** script that you have downloaded
3. Go to StikDebug settings
4. Enable **Silent Audio** and **Background Location**. Scroll down to see if your device is reported as **TXM** or **Non TXM**. If it is reported as Non TXM, turn on **Always Run Scripts**.
5. Import a certifcate in settings (follow steps 3-7 Jit-less)

## Installing SideJITServer (17.0.1 - 17.3.1)

Follow the instructions as listed here
https://github.com/nythepegasus/SideJITServer

You will need to be nearby your computer to use this, StikDebug does not and will never work on 17.0.1 - 17.3.1
Once done, set the JIT enabler in settings to **SideJITServer**
(If you don't know what to do, ask for support in the discord.)
## Last Step
1. Open Geode
2. Tap **Verify Geometry Dash**
3. Tap **Download**
4. Tap **Launch**

## Launching on Cellular
1. Turn on **LocalDevVPN**
2. Turn on **Airplane mode**
3. Tap **Launch** like normal
4. Once Geode has started, turn off **Airplane mode** and **LocalDevVPN**

## Conclusion
You should now be able to run Geometry Dash with Geode! You can install mods by tapping the **Geode** button on the bottom of the menu, and browse for mods to install!
> [!TIP]
> To refresh Geode, connect to LocalDevVPN, open SideStore (in LiveContainer), then tap refresh all.
