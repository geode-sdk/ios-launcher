# Installation Guide (LiveContainer)

| Supported on | Requires Computer? | Mod Compatibility | Price |
|--------------|--------------------|-------------------|-------|
| iOS 14.0 and above | Yes | *Medium* to *High* (*Medium* on JIT-Less) | Free |

This tutorial is for people that use LiveContainer to bypass Apple's 3 active app and 10 app ID limit.

> [!TIP]
> If you have never installed SideStore before, follow the [iOS 17.4+ (SideStore)](./MODERN-IOS-INSTALL.md) guide, excluding the **Geode** sideloading, then come back to this guide.

# JIT Only
## Prerequisites
- LiveContainer
- A **JIT enabler** (e.g. [StikDebug](https://apps.apple.com/us/app/stikdebug/id6744045754))
- An internet connection
- IPA file of Geode launcher from [Releases](https://github.com/geode-sdk/ios-launcher/releases/latest)

## Set Up LiveContainer for Geode
- Sideload Geode using LiveContainer
- Hold on the app and go to the Geode app settings in LiveContainer, then **enable these settings:**

- **Launch with JIT**
- **Don't Inject TweakLoader**
- **Don't Load TweakLoader**

![](./screenshots/livecontainer.png)

After these steps:

- Open Geode
- Press **"Verify Geometry Dash"**
- Press **"Download"**
- Press **"Launch"**

# JIT-Less
## Prerequisites
- LiveContainer (Latest)
- Confirming JIT-less works on LiveContainer
- An internet connection
- IPA file of Geode launcher from [Releases](https://github.com/geode-sdk/ios-launcher/releases/latest)

## Set Up LiveContainer for Geode
- Sideload Geode using LiveContainer
- Hold on the app and go to the Geode app settings in LiveContainer, then **enable these settings:**

- **Fix File Picker & Local Notification**
- **Use LiveContainer's Bundle ID** (If on new version of LiveContainer)
- **Don't Inject TweakLoader**
- **Don't Load TweakLoader**

After these steps:
- Tap on **"Settings"** on the bottom right
- Scroll down until you see the version of LiveContainer
- Tap on the version text 5 times.
- Scroll down and tap **"Export Cert"** then return to **"Apps"** in the bottom left.

![](./screenshots/livecontainer-jitless.png)

Finally, the last steps are:

- Open Geode
- Press **"Verify Geometry Dash"**
- Press **"Download"**
- Open Settings
- Make sure **Enable JIT-Less** is on
- Press **"Test JIT-Less Mode"** to test if JIT-less mode works properly
- Exit settings & press **"Launch"**
