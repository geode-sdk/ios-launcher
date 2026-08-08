# Getting the Certificate File from Signulous

> [!WARNING]
> If the site that helps you get the Signulous certificate file tells you to not download it directly to your device, and you're using a different browser, **temporarily switch to Safari**.

By default, Signulous does not give you the **.p12** file of your certificate. Here is how you can get it:

- Go to [this page](https://www.udidregistrations.com/check-order)
- Paste **your device's UDID or PayPal transaction ID** (You can go to [this page](https://udid.tech/) and follow the instructions to get your device's UDID)
- Press **"Check Order"**
- Press **"Explicit & Ad Hoc Provisioning"**
- Download the certificate file and follow the instructions in the **"Import Apple Developer Certificate"** section in the [JIT-less guide](/JITLESS-INSTALL-GUIDE.md) to import them
- The **password for Signulous certificates** by default is `123456`
