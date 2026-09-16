# Installation Guide (Free / Distribution Certificates)

> [!IMPORTANT]
> Installing Geode via this method is **not recommended** due to the limitations of such Certificates.
> 
> Using this method **WILL** require you install a Helper app to install, update, enable and disable mods. As well as updating Geode itself and entering Safe Mode.

> [!CAUTION]
> The Geode Helper stores a seperate save data for Geometry Dash. Uninstalling the Helper will cause your ***__SAVE DATA, MODS AND MOD SETTINGS in the Helper, to be PERMANENTLY DELETED!!!__*** Keep the Helper installed and just install the IPA the iOS launcher generates for you. Think of it like updating the Helper.

> [!WARNING]
> Free Certificates violate [Apple's Terms of Service](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/#ADPLA5), and may get your iDevice blacklisted. As such we will not assist you in accquiring them.
They may also stop working at any time. We **cannot** prevent this as it isn't Geode related.
> 
> If you are fine with this, and acknowledge the warning, you can proceed to follow this guide.

| Supported on | Requires Computer? | Mod Support | Price |
|--------------|--------------------|-------------------|-------|
| iOS 14.0 and above | No | *Partial* | Free (Paid if using a Dist. cert) |


## Prerequisites
- **Full version of Geometry Dash installed**
- An internet connection
- A signer/installer of your choice with a certificate (such as [Ksign](https://github.com/Nyasami/Ksign) or [Feather](https://github.com/CLARATION/Feather))
- **IPA file** of Geode launcher from [Releases](https://github.com/geode-sdk/ios-launcher/releases/latest)
- At least 400 MB of storage available

## Setting up Enterprise Mode
After setting up Geode, verifying you own Geometry Dash, and downloaded the libraries, you will need to enable **Enterprise Mode** in settings.

After enabling, you will notice a dot on the top right after exiting settings. This is the patch indicator, which tells you whether or not the Geode Helper (patched Geometry Dash) requires patching.

![](./screenshots/enterprise-s1.png)

### What each indicator means:
- 🟢 **Green** - No patching required, can launch the Helper immediately.
- 🟡 **Yellow** - A patch is required. (Mod enabled, disabled, downloaded, etc)
- 🟠 **Orange** - IPA is currently being compressed, or you exited the app before it finished patching.
- 🔴 **Red** - A patch was forced and required. (A Geode update, forced by User, etc)

After confirming the dot is on the top right, tap launch. It will show a popup giving you instructions on what to do. These instructions can be viewed anytime in settings.

When the patching is complete, an **IPA file** named "Helper.ipa" will be shown in the share view. You will open the **IPA file** with the signer/installer of your choice, such as **Feather** for example. The installation process may take a while, as it is installing a patched Geometry Dash.
![](./screenshots/enterprise-s2.png)

## Post Setup Steps
After installing the Helper, you **must** open it with the launcher. Otherwise an error like this will show up:
<img src="./screenshots/enterprise-s3.png" alt="Launch Error" width="300"/>

This is because it is a **requirement** to use the launcher to open the Helper. Otherwise it won't be able to properly know if you want to launch in safe mode, and assume you are running it with JIT, which is not what you have.

Once you launch the **Helper** with Geode by opening Geode and tapping launch, you will notice that it's asking to open the app in Geode. You will tap Open, and it should bring you back to the launcher, then back to the helper.

After that, you should be in the game!
