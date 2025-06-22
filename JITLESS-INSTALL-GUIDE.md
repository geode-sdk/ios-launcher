# Installation Guide (JIT-Less, iOS 26 or below)

This tutorial is mainly for iOS 26 as Apple broke enabling JIT on iOS 26, but it should theoretically work for any iOS version.

# Prerequisites
## SideStore Method
> [!WARNING]
> Only SideStore is supported for JIT-less as it is the only sideloader that exposes the certificate. 

- **PC** (Windows, Linux and Mac OS)
- **USB Cable** to connect your device (Lightning / USB C)
- **SideStore** (if you have SideStore 0.6.0 or above, install the nightly version of SideStore by going to the app settings. If you are on a version below 0.6.0, get [this version](https://nightly.link/SideStore/SideStore/actions/artifacts/2973103965.zip))

## Apple Developer Certificate Method
> [!WARNING]
> Only use this method **if you're willing to pay** for an Apple developer certificate.

> [!WARNING]
> When you get an Apple developer certificate, **make sure to ask your provider to give your certificate the `get-task-allow` entitlement.**

- An **Apple developer certificate** (you can get one from services like [KravaSign](https://kravasign.com) or [Signulous](https://www.signulous.com))

# Enable JIT-Less
A new section has been added to the Geode launcher's settings for JIT-less. Here's how to use it:

## Import Apple Developer Certificate
- Press **"Enable JIT-Less"**
- Press **"Import Certificate Manually"**
- Choose the **.p12** and **.mobileprovision** file of the certificate you used to sign the Geode launcher
- Input the password of your certificate **(make sure to input the password correctly, or Geode will fail to do the signing process)**
- Press **"Test JIT-Less Mode"** to test if JIT-less mode works properly 

## Import SideStore Certificate
> [!WARNING]
> Before this step, **make sure to get the correct version of SideStore.** Not doing so will cause the button to do absolutely nothing. (the correct version is mentioned in the Prerequisites section)

- Press **"Enable JIT-Less"**
- Press **"Import SideStore Certificate"**
- Press **"Test JIT-Less Mode"** to test if JIT-less mode works properly

# Post Install
Simply verify Geometry Dash, download Geode, then launch the game with Geode.