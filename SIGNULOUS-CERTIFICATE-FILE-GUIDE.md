# Getting Certificate Files from Signulous

By default, Signulous does not give you the **.p12** and **.mobileprovision** file of your certificate. Here is how you can get them:

- Go to [this page](https://www.udidregistrations.com/check-order)
- Paste **your device's UDID or PayPal transaction ID** (You can go to [this page](https://udid.tech/) and follow the instructions to get your device's UDID)
- Press **"Check Order"**
- Press **"Explicit & Ad Hoc Provisioning"**
- If the site says that the files should not be downloaded directly to the device and you use a different browser, **temporarily switch to Safari**
- Download the certificate files and follow the instructions in the **"Import Apple Developer Certificate"** section in the [JIT-less guide](/JITLESS-INSTALL-GUIDE.md) to import them
- The **password for Signulous certificates** by default is `123456`