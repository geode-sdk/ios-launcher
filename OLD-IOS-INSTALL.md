# Installation Guide (TrollStore / Jailbreak)

**TrollStore Compatibility**
| Supported on | Requires Computer? | Mod Support | Price |
|--------------|--------------------|-------------------|-------|
| iOS 14 - 16.6.1, 16.7 RC and 17.0.0 | On iOS 16.7 RC - 17.0.0 | *Full* | Free |

**Jailbreak Compatibility**
| Supported on | Requires Computer? | Mod Support | Price |
|--------------|--------------------|-------------------|-------|
| iOS 14 - 18 | On 17.0.1+ | *Full* | Free |


> [!NOTE]
> Jailbreaking on iOS 17.0.1 - 18.x is only supported on **older iPads**
>
> Please read [this guide](https://ios.cfw.guide/getting-started) first and ensure you're jailbroken before following the Jailbreak steps.

> [!TIP]
> If you are able to [install TrollStore](https://ios.cfw.guide/installing-trollstore/), it is **strongly advised to install Geode using that instead.**

> [!WARNING]
> If you're using iOS 15.8.7+ you will need to use [TrollInstallerDark](https://github.com/rockylabs-dev/TrollInstallerDark/) instead.

# Prerequisites

- TrollStore or [TrollStore Lite](https://havoc.app/package/trollstorelite) (Jailbreak users only!)  installed
- Full version of Geometry Dash installed
- .ipa / .tipa from [Releases](https://github.com/geode-sdk/ios-launcher/releases/latest) (.tipa is for Jailbreak users only!)


## Configure TrollStore and Geode for JIT 
> [!NOTE]
> You may skip this section if you installed the .tipa.

1. Open TrollStore.
2. Go to Settings.
3. Enable **URL Scheme Enabled** and tap **Rebuild Icon Cache**.
4. Open Geode.
5. Go to Settings and make sure TrollStore is set in the **JIT enabler** setting.

Now you can launch Geode with TrollStore's built in JIT feature by pressing Launch!

![](screenshots/install-trollstore.png)

## Installing the Jailbreak Tweak

> [!WARNING]
> Only follow this if you're jailbroken and have the .tipa version installed!
> 
> If you follow this and your jailbreak goes away (whether from a reboot, battery dying and etc.), Geode will not work. You will have to re-jailbreak your device for Geode to work again.

1. Add [this repo](https://ios-repo.geode-sdk.org) to your package manager (Sileo, Zebra, Cydia, etc.).
2. Install the **Geode Inject** tweak.
3. Complete setup inside the Geode app
5. Click Download, then Launch

You should now see the Geode icon on the title screen! Additionally, you can launch Geode **without** the Launcher now! 

## Conclusion
You should now be able to run Geometry Dash with Geode! You can install mods by tapping the **Geode** button on the bottom of the menu, and browse for mods to install!
