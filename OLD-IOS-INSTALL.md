# Installation Guide (TrollStore / Jailbreak)

| Supported on | Requires Computer? | Mod Compatibility | Price |
|--------------|--------------------|-------------------|-------|
| iOS 14.0 to 17.0 (Excluding iOS 16.7.x and 17.0.x) | On iOS 17.0 | *Full* | Free |

This guide is for devices that are compatible with TrollStore (and optionally a jailbreak)

> [!TIP]
> On devices below iOS 17.0, you can use enterprise (aka free) certificates to get any installer you will use to install TrollStore. You will not need the free certificates after installing TrollStore, and you should get rid of them after installing TrollStore; as TrollStore permanently signs apps. iOS 17.0 requires the use of a computer to install TrollStore.

## Prerequisites

## iOS 17.0 
- PC (Windows, Mac, Linux)
- USB Cable to connect your device (Lightning / USB C)
- TrollStore
- Full version of Geometry Dash installed
- IPA / TIPA file of Geode launcher from [Releases](https://github.com/geode-sdk/ios-launcher/releases/latest) (only get the TIPA file if you want to use the jailbreak tweak)
- Jailbreak tweak (optional, you need to be jailbroken and have the TIPA version)

## Below iOS 17.0
- TrollStore (or **if you're on an iOS version where TrollStore is not supported** but you're able to jailbreak, **[TrollStore Lite](https://havoc.app/package/trollstorelite))**
- A jailbreak like Dopamine (optional, only if you want to use the jailbreak tweak)
- Full version of Geometry Dash installed
- IPA / TIPA file of Geode launcher from [Releases](https://github.com/geode-sdk/ios-launcher/releases/latest) (only get the TIPA file if you want to use the jailbreak tweak)
- Jailbreak tweak (optional, you need to be jailbroken)

## Installing TrollStore
Check out the table on the [iOS CFW Guide](https://ios.cfw.guide/installing-trollstore/) to find the correct method to install TrollStore based on your iOS version and your device's chipset. Check the table on [this page](https://appledb.dev/device-selection/iPhone.html) to see which chipset your device uses. Click [here](https://appledb.dev/device-selection/iPads.html) if you are using an iPad. The part you want to look on this page is **SoC**.

## Installing Geode through TrollStore
Tap the `+` button and tap either **Install IPA File** or **Install From URL**, depending if you manually downloaded the IPA or the TIPA file. After either selecting the IPA or the TIPA file for the Geode app, or providing the URL, the Geode app should appear on your home screen!

## Configure TrollStore and Geode for JIT
1. Open TrollStore.
2. Go to Settings.
3. Enable **URL Scheme Enabled** and tap **Rebuild Icon Cache**.
4. Open Geode.
5. Go to Settings and make sure TrollStore is set in the **JIT enabler** setting.

Now you can launch Geode with TrollStore's built in JIT feature by pressing Launch!

![](screenshots/install-trollstore.png)

## Installing the Jailbreak Tweak (optional)
Follow [this guide](https://ios.cfw.guide/get-started/) to get started on jailbreaking your device.

> [!WARNING]
> Only follow this if you're jailbroken and have the TIPA version installed!
> \
> If you follow this and your jailbreak goes away (whether from a reboot, battery dying and etc.), Geode will not work. You will have to re-jailbreak your device for Geode to work again.

> [!TIP]
> Once you install the jailbreak tweak, you can launch the game without going to the Geode launcher. However you should keep the launcher if you want to restart the game, enter safe mode and update Geode!

2. Add [this repo](https://ios-repo.geode-sdk.org) to your package manager (Sileo, Zebra, Cydia, etc.).
3. Install the **Geode Inject** tweak.
4. Restart SpringBoard.
5. Open Geode
6. Press Launch.

## Conclusion
You should now be able to run Geometry Dash with Geode! You can install mods by tapping the **Geode** button on the bottom of the menu, and browse for mods to install!