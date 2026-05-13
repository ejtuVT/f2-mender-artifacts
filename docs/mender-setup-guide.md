# Mender Client and Workstation Setup

**Targets**:

| Role        | Platform                             |
|-------------|--------------------------------------|
| Device      | Ubuntu-based embedded device (arm64) |
| Workstation | Ubuntu 22.04 (amd64)                 |

**Backend:** Mender Cloud  
**Mode:** single-rootfs (no A/B partitioning)

## Part A. Workstation Setup

Set up the workstation tools used to generate and upload artifacts.

### A.1 Add the Mender Workstation-Tools Repository

```bash
curl -fsSL https://downloads.mender.io/repos/debian/gpg \
 | sudo tee /etc/apt/trusted.gpg.d/mender.asc
```

```bash
echo "deb [arch=amd64] https://downloads.mender.io/repos/workstation-tools ubuntu/jammy/stable main" \
 | sudo tee /etc/apt/sources.list.d/mender.list
```

```bash
sudo apt update
```

### A.2 Install Tools

```bash
sudo apt install -y mender-artifact mender-cli
```

| Tool              | Purpose                                            |
|-------------------|----------------------------------------------------|
| `mender-artifact` | Builds OTA artifact files                          |
| `mender-cli`      | Interacts with Mender Cloud (upload, list, deploy) |

Verify installation:

```bash
mender-artifact --version
mender-cli --version
```

### A.3 Authenticate with Mender Cloud

Before uploading artifacts or managing deployments, authenticate the workstation.

```bash
mender-cli login
```

You will be prompted for your Mender Cloud username (email) and password.

Verify authentication:

```bash
mender-cli artifacts list
```

If no authentication error appears, the login was successful.

## Part B. Device Setup

Set up the Mender client on the target device (Ubuntu 20.04).

### B.1 Install Mender Client

Use the official installer script, which detects the OS version and architecture, adds the correct Mender repository, installs `mender-client`, and enables the systemd service.

```bash
curl -fLsS https://get.mender.io -o get-mender.sh
sudo bash get-mender.sh mender-client
```

Verify installation:

```bash
dpkg -l | grep mender
```

### B.2 Stop the Client Before Configuration

Stop the OTA service before modifying configuration or identity files.

```bash
sudo systemctl stop mender-client
```

### B.3 Configure the Mender Client

```bash
sudo nano /etc/mender/mender.conf
```

Set the contents to:

```json
{
  "ServerURL": "https://hosted.mender.io",
  "TenantToken": "MENDER-TOKEN",
  "InventoryPollIntervalSeconds": 300,
  "UpdatePollIntervalSeconds": 900,
  "RetryPollIntervalSeconds": 300
}
```

Parameters:

| Field                          | Description                                    |
|--------------------------------|------------------------------------------------|
| `ServerURL`                    | Backend endpoint used by the device            |
| `TenantToken`                  | Authenticates the device to your Mender tenant |
| `InventoryPollIntervalSeconds` | Interval for sending inventory data            |
| `UpdatePollIntervalSeconds`    | Interval for checking for deployments          |
| `RetryPollIntervalSeconds`     | Retry interval after transient errors          |

### B.4 Configure Single-Rootfs Mode

Create a drop-in config that disables A/B partition logic and enables single-rootfs operation.

```bash
sudo mkdir -p /etc/mender/mender.conf.d
sudo nano /etc/mender/mender.conf.d/single-rootfs.conf
```

Set the contents to:

```json
{
  "RootfsPartA": "",
  "RootfsPartB": "",
  "BootUtilitiesSetActive": "",
  "BootUtilitiesGetNextActive": ""
}
```

### B.5 Define the Device Type

Check whether the device type file exists:

```bash
cat /var/lib/mender/device_type
```

If missing, create it:

```bash
echo "device_type=f2-jetson-orin-nx" | sudo tee /var/lib/mender/device_type
```

This value must match the `-t` device type argument used when generating artifacts.

### B.6 Configure Custom Device Identity

By default, Mender selects the Ethernet interface with the lowest `ifindex`, typically `eth0`. If your devices use `eth1`, `eth2`, or another interface for connectivity, override the identity script.

```bash
sudo mkdir -p /etc/mender/identity
sudo nano /etc/mender/identity/mender-device-identity
```

Set the contents to:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Interface priority (can override with IF_ORDER)
IFS_DEFAULT=("eth1" "eth2" "eth0")
read -r -a IF_ORDER <<< "${IF_ORDER:-${IFS_DEFAULT[*]}}"

is_valid_mac() {
  local mac="$1"
  local iface="$2"

  [[ "$mac" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]] || return 1
  mac="${mac,,}"

  [[ "$mac" != "00:00:00:00:00:00" ]] || return 1
  [[ "$mac" != "00:00:00:00:00:01" ]] || return 1
  [[ "$mac" != "ff:ff:ff:ff:ff:ff" ]] || return 1

  # Skip virtual interfaces
  [[ -e "/sys/class/net/$iface/device" ]] || return 1

  return 0
}

for IF in "${IF_ORDER[@]}"; do
  addr_file="/sys/class/net/$IF/address"
  [[ -r "$addr_file" ]] || continue

  mac=$(<"$addr_file")

  if is_valid_mac "$mac" "$IF"; then
    echo "mac=${mac,,}"
    exit 0
  fi
done

echo "No valid MAC found on ${IF_ORDER[*]}" >&2
exit 1
```

Make it executable:

```bash
sudo chmod +x /etc/mender/identity/mender-device-identity
```

Test it manually:

```bash
sudo /etc/mender/identity/mender-device-identity
```

Expected output:

```text
mac=aa:bb:cc:dd:ee:ff
```

> **Note:** Changing the identity will cause the device to appear as a new device in Mender Cloud and require re-acceptance if it was previously accepted.

### B.7 Start the Client

```bash
sudo systemctl start mender-client
```

Monitor logs:

```bash
journalctl -u mender-client -f
```

### B.8 Accept Device in Mender Cloud

In the web UI:

1. Go to **Devices → Pending**.
2. Accept the device.
3. Assign it to a static group.

## Part C. Mender Connect Installation

Install and configure Mender Connect to enable secure remote terminal access through Mender Cloud.

**Prerequisites:**

- Mender Client 3.5 installed and running
- Device accepted in Mender Cloud
- Device connected to the internet
- Device status shown as **Connected** in the Cloud UI

### C.1 Install Mender Connect

```bash
sudo apt update
sudo apt install mender-connect
```

Verify installation:

```bash
dpkg -l | grep mender-connect
```

Expected output:

```text
ii  mender-connect  <version>  arm64  Mender Connect service
```

### C.2 Enable and Start the Service

```bash
sudo systemctl enable mender-connect
sudo systemctl start mender-connect
```

Verify status:

```bash
systemctl status mender-connect
```

The service must show `active (running)`.

### C.3 Configure the Session User

By default, Mender Connect starts shell sessions as user `nobody`. To start sessions as `nvidia`, edit the configuration file:

```bash
sudo nano /etc/mender/mender-connect.conf
```

Set the contents to:

```json
{
  "ShellCommand": "/bin/bash",
  "User": "nvidia"
}
```

Restart the service to apply the change:

```bash
sudo systemctl restart mender-connect
```

Reconnect from the Mender Cloud UI to verify the new user takes effect.

### C.4 Test Remote Terminal

In the web interface:

```text
Devices → Select device → Troubleshoot → Remote terminal
```

If configured correctly, the shell prompt should appear as:

```bash
nvidia@device:~$
```

### C.5 Troubleshooting

If the terminal does not appear, check the service logs:

```bash
journalctl -u mender-connect -f
```

```bash
journalctl -u mender-client -f
```

## Part E. General Artifact Creation Template

A reusable pattern for Script Update Module artifacts. Replace the placeholders with values for your specific artifact.

### E.1 Naming Conventions

**Format:**

```text
<function>[-<scope>]-v<N>
```

| Segment    | Purpose                                   | Example                                        |
|------------|-------------------------------------------|------------------------------------------------|
| `function` | What the artifact does                    | `inventory-standardization`, `install-connect` |
| `scope`    | Optional device variant or project prefix | `f2`, omit if fleet-wide                       |
| `v<N>`     | Monotonically incrementing integer        | `v1`, `v2`, `v3`                               |

**Always increment the version number.** Mender will not redeploy an artifact to a device that already reports that exact artifact name as installed. Reusing the same name without incrementing silently skips all devices that ran the prior version.

**Never reuse a name for a different purpose.** Once `install-connect-v1` means "install Mender Connect", that name is fixed to that meaning in the Cloud release history.

**Use lowercase and hyphens only.** Avoid underscores, spaces, and uppercase to ensure consistent behavior across the CLI and web UI.

| Current                        | Next Version                   |
|--------------------------------|--------------------------------|
| `inventory-standardization-v1` | `inventory-standardization-v2` |
| `install-mender-connect-v1`    | `install-mender-connect-v2`    |
| `hello-test`                   | `hello-test-v2`                |
| `f2-diagnostic-snapshot-v1`    | `f2-diagnostic-snapshot-v2`    |

### E.2 Placeholders

| Placeholder     | Description                                                  | Example                                    |
|-----------------|--------------------------------------------------------------|--------------------------------------------|
| `ARTIFACT_NAME` | Unique release name visible in Mender Cloud                  | `install-tool-v1`                          |
| `DEVICE_TYPE`   | Target device type. Must match `/var/lib/mender/device_type` | `f2-jetson-orin-nx`                        |
| `SCRIPT_PATH`   | Absolute path to the payload script on the workstation       | `~/tools/mender-test/scripts/my-script.sh` |
| `OUTPUT_FILE`   | Output `.mender` file name                                   | `install-tool-v1.mender`                   |

### E.3 Script Requirements

The payload script runs as root on the device. Requirements for Mender Client 3.5 on Ubuntu 20.04 (arm64):

- Use `#!/bin/sh` instead of `#!/bin/bash`. The Script Update Module on this version invokes `sh`
- Exit `0` on success, non-zero to fail the deployment
- Be idempotent where possible, as deployments can be retried or re-run
- Do not write persistent state to `/var/lib/mender/` or modify `/etc/mender/mender.conf` directly

### E.4 Workflow

**Step 1: Write the script**:

```bash
mkdir -p ~/tools/mender-test/scripts
nano ~/tools/mender-test/scripts/SCRIPT_NAME.sh
chmod +x ~/tools/mender-test/scripts/SCRIPT_NAME.sh
```

**Step 2: Generate the artifact**:

```bash
mender-artifact write module-image \
  -n ARTIFACT_NAME \
  -t DEVICE_TYPE \
  -T script \
  -f SCRIPT_PATH \
  -o OUTPUT_FILE
```

**Step 3: Validate**:

```bash
mender-artifact read OUTPUT_FILE
```

Confirm `Compatible devices` matches `DEVICE_TYPE` and `Type: script` is listed.

**Step 4: Upload**:

```bash
mender-cli artifacts upload OUTPUT_FILE
```

**Step 5: Deploy** (Mender Cloud UI)

1. **Releases → ARTIFACT_NAME → Create deployment**
2. Select target group
3. Start deployment

**Step 6: Verify**:

```bash
journalctl -u mender-client -f
```

Check the side effect specific to your script (log file created, service restarted, config updated).

### E.5 Worked Example: Hello Test

A minimal script that writes a timestamped log file. Use this to confirm the OTA pipeline is working before deploying real artifacts.

**Step 1: Write the script**:

```bash
mkdir -p ~/tools/mender-test/scripts
```

```sh
#!/bin/sh
echo "Hello World $(date -u)" > /home/nvidia/tools/hello-test.log
```

```bash
chmod +x ~/tools/mender-test/scripts/hello-test.sh
```

**Step 2: Generate the artifact**:

```bash
mender-artifact write module-image \
  -n hello-test-v1 \
  -t f2-jetson-orin-nx \
  -T script \
  -f ~/tools/mender-test/scripts/hello-test.sh \
  -o hello-test-v1.mender
```

**Step 3: Validate**:

```bash
mender-artifact read hello-test-v1.mender
```

Expected output:

```text
Compatible devices: [f2-jetson-orin-nx]

Updates:
  - Type: script
```

**Step 4: Upload**:

```bash
mender-cli artifacts upload hello-test-v1.mender
```

**Step 5: Deploy** (Mender Cloud UI)

1. **Releases → hello-test-v1 → Create deployment**
2. Select target group
3. Start deployment

**Step 6: Verify**:

```bash
cat /home/nvidia/tools/hello-test.log
```

Expected output:

```text
Hello World Tue May 13 18:00:00 UTC 2026
```

### E.6 mender-artifact Flag Reference

Applies to `mender-artifact write module-image` as used with Mender Client 3.5 on Ubuntu 20.04 (arm64) via the Script Update Module.

| Flag                 | Long Form            | Required | Description                                                                                                    |
|----------------------|----------------------|----------|----------------------------------------------------------------------------------------------------------------|
| `-n`                 | `--artifact-name`    | Yes      | Artifact name as it appears in Mender Cloud Releases. Must be unique per release.                              |
| `-t`                 | `--device-type`      | Yes      | Compatible device type. Repeatable for multiple types. Must match `/var/lib/mender/device_type` on the device. |
| `-T`                 | `--type`             | Yes      | Update module type. Use `script` for the Script Update Module.                                                 |
| `-f`                 | `--file`             | Yes      | Payload file. Repeatable. Each `-f` adds one file to the artifact. Files execute in lexicographic order.       |
| `-o`                 | `--output-path`      | Yes      | Output `.mender` file path.                                                                                    |
| `-v`                 | `--artifact-version` | No       | Artifact format version. Defaults to `3`. Required for Mender Client 3.x. Do not set to a lower value.         |
| `--software-name`    |                      | No       | Overrides the software name in `artifact_provides`. Defaults to the artifact name.                             |
| `--software-version` |                      | No       | Overrides the software version string in `artifact_provides`.                                                  |
| `--depends`          |                      | No       | Declares a dependency on a prior artifact (for chained or ordered deployments).                                |
| `--provides`         |                      | No       | Declares a `key=value` pair in `artifact_provides` (used for dependency tracking between artifacts).           |

### E.7 Multi-File Artifacts

The Script Update Module accepts multiple payload files via repeated `-f` flags. All files are deployed together and available in the module's working directory on the device at execution time.

Use multiple files when:

- A main entry script depends on a helper script or data file
- A Python script needs to be deployed alongside a launcher script
- A diagnostic tool bundles a shell entry point and a Python collector

Add each file with a separate `-f` flag:

```bash
mender-artifact write module-image \
  -n ARTIFACT_NAME \
  -t DEVICE_TYPE \
  -T script \
  -f path/to/entry-script.sh \
  -f path/to/helper.py \
  -o OUTPUT_FILE
```

Files execute in lexicographic name order. Use a numeric prefix to make the order explicit:

```text
ArtifactInstall_Enter_00   (runs first)
ArtifactInstall_Enter_01   (runs second)
```

This naming convention matches the Mender state machine lifecycle. The prefix `ArtifactInstall_Enter_` ties the file to the Install state entry hook.

**Example**: Diagnostic Snapshot Artifact

```bash
mender-artifact write module-image \
  -n f2-diagnostic-snapshot-v1 \
  -t f2-jetson-orin-nx \
  -T script \
  -f f2-diagnostic-artifact/ArtifactInstall_Enter_00 \
  -f f2-diagnostic-artifact/f2_diagnostic_snapshot.py \
  -o f2-diagnostic-snapshot-v1.mender
```

`ArtifactInstall_Enter_00` is the entry script that invokes `f2_diagnostic_snapshot.py`. Both files land in the same working directory on the device, so the entry script can reference the Python file by name.

## Part F. Deleting an Artifact

Remove an artifact from Mender Cloud and optionally clean up local files.

> **Note:** Deleting an artifact does not affect devices that already installed it. It only prevents future deployments of that release. If a deployment using the artifact is still active, stop or finish it before deletion.

### F.1 Delete via the Web UI

1. Log in to Mender Cloud.
2. Go to **Releases**.
3. Select the artifact to remove.
4. Click **Delete** and confirm.

If deletion is blocked, verify that no active deployment is using the artifact.

### F.2 Delete via CLI

Authenticate if needed:

```bash
mender-cli login
```

List artifacts to find the ID:

```bash
mender-cli artifacts list
```

Delete by ID:

```bash
mender-cli artifacts delete <artifact-ID>
```

### F.3 Delete the Local Artifact File

Deleting from Mender Cloud does not remove the local `.mender` file.

Remove a specific file:

```bash
rm hello-test.mender
```

Or clean all local test artifacts:

```bash
rm ~/tools/mender-test/*.mender
```

### F.4 Re-deploying the Same Script

Mender will not redeploy an artifact version that a device already reports as installed. When testing repeatedly, increment the artifact name rather than reusing it:

```text
hello-test-v1
hello-test-v2
hello-test-v3
```

### F.5 Verify Removal

```bash
mender-cli artifacts list
```

Or check the **Releases** page in the web interface.
