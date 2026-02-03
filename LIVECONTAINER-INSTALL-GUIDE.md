# Installation Guide (LiveContainer)

| Supported on | Requires Computer? | Mod Support | Price |
|--------------|--------------------|-------------------|-------|
| iOS 15 and above | Yes | *Partial* to *Full* (*Partial* on JIT-Less) | Free |

This tutorial is for people that use LiveContainer to bypass Apple's 3 active app and 10 app ID limit.

> [!NOTE]
> This guide assumes you have installed LiveContainer **through SideStore**. If you didn't, make sure to follow the [SideStore guide](/MODERN-IOS-INSTALL.md), then come back to this guide. Make sure to **also have StikDebug set up** by following the instructions on the **SideStore guide** if you want to have **full mod support**.

# With JIT (Full Mod Support)
## Prerequisites
- Nightly version of [LiveContainer](https://github.com/LiveContainer/LiveContainer/releases/tag/nightly)
- [StikDebug](https://github.com/StephenDev0/StikDebug/releases) (has to be installed through **SideStore**)
- [LocalDevVPN](https://apps.apple.com/us/app/localdevvpn/id6755608044) for **StikDebug** (you probably have it if you installed SideStore)
- An internet connection
- IPA file of Geode launcher from [Releases](https://github.com/geode-sdk/ios-launcher/releases/latest)

## Set Up LiveContainer for Geode (JIT)
1. Install Geode using LiveContainer
2. Hold on the app and go to the Geode app settings in LiveContainer, then **enable these settings:**

- **Launch with JIT**
- **Don't Inject TweakLoader**
- **Don't Load TweakLoader**

### Required Extra Steps for iOS 26
> [!WARNING]
> On iOS 26, you will see a black picture in picture box on your screen. Do not close it, as it will most likely cause Geode to crash. It is required for it to be open for JIT to work properly.

1. Download the [TuliphookJIT.js](https://github.com/geode-sdk/ios-launcher/blob/main/TuliphookJIT.js) script (click on the script name, then press the download button on the redirected page to download it)
2. On the Geode **app settings** in **LiveContainer**, find the **JIT Launch Script** option and select the **TuliphookJIT.js** script that you have downloaded
3. Open **StikDebug**
4. Go to **Settings**
5. Enable **Picture in Picture**, scroll down and see if your device is reported as **TXM** or **Non TXM**. If your device is reported as **Non TXM**, enable **Always Run Scripts**

![](./screenshots/livecontainer.png)

After these steps:

3. Open Geode
4. Press **Verify Geometry Dash**
5. Press **Download**
6. Press **Launch**

# With JIT-Less (Partial Mod Support)
## Prerequisites
- Nightly version of [LiveContainer](https://github.com/LiveContainer/LiveContainer/releases/tag/nightly)
- An internet connection
- IPA file of Geode launcher from [Releases](https://github.com/geode-sdk/ios-launcher/releases/latest)

## Set Up LiveContainer for Geode (JIT-Less)
> [!WARNING]
> If you have set Geode as a **shared app** in LiveContainer, convert it to a **private app**. Otherwise, Geode **will not be able to detect the certificate**.

1. Install Geode using LiveContainer
2. Hold on the app and go to the Geode app settings in LiveContainer, then **enable these settings:**

- **Fix File Picker**
- **Fix Local Notification**
- **Use LiveContainer's Bundle ID**
- **Don't Inject TweakLoader**
- **Don't Load TweakLoader**

After these steps:

3. Tap on **Settings** on the bottom right
4. Tap **Import Certificate from SideStore**
5. On the popup in **SideStore**, hit **Export**
6. Get back to LiveContainer and scroll down until you see the **version of LiveContainer**
7. Tap on the **version text** 5 times
8. Scroll down and tap **Export Cert** then return to **Apps** in the bottom left

![](./screenshots/livecontainer-jitless.png)

Finally, the last steps are:

9. Open Geode.
10. Press **Verify Geometry Dash**
11. Press **Download**
12. Open Settings
13. Make sure **Enable JIT-Less** is on.
14. Press **Test JIT-Less Mode** to test if JIT-less mode works properly.
15. Exit settings & press **Launch**