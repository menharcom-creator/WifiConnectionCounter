# WiFi Counter (iOS)

Scans the Wi-Fi network your iPhone is connected to and lists every device that answers, with its IP address (and name, when the router shares it).

## How the count works
1. Reads the phone's Wi-Fi address and subnet.
2. Pings every address in the subnet (2 rounds).
3. For addresses that stayed silent, tries common TCP ports. A device that accepts or refuses the connection is counted.

Only real replies are counted. The result is "at least N devices", never a made-up total.

## Limits (iOS)
- No MAC addresses and no router client list (Apple blocks both).
- Sleeping phones, devices that block pings, and Wi-Fi with client isolation (common on Piso WiFi) may not show up.
- Allow **Local Network** access when iOS asks, or the scan finds nothing.

## Build the IPA on GitHub
1. Upload all files to a GitHub repo (branch `main`).
2. Make sure `.github/workflows/build.yml` exists. If your upload skipped it: Add file > Create new file, type `.github/workflows/build.yml` as the name, paste the contents.
3. Open the **Actions** tab. The build runs on every push (or press **Run workflow**). It takes about 5 minutes.
4. Download `WiFiConnectionCounter.ipa` from the new **Release** (right side of the repo page), or from the run's Artifacts.
5. The IPA is **unsigned**. Sign and install it with ESign.

Bundle ID: `com.menhar.wificonnectioncounter` (change it in `project.yml` if you like).
