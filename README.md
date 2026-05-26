# F2 Mender Artifacts

Mender update artifacts for F2 devices. Each subdirectory contains a `.mender` artifact and the shell scrip bundled inside it.

For workstation setup, device configuration, artifact creation, and deployment procedures, see [Mender Setup Guide](docs/mender-setup-guide.md).

## Creating and Uploading Artifacts

All artifacts in this repo target device type `f2-jetson-orin-nx` and use the Script Update Module.

**1. Generate the artifact**:

```bash
mender-artifact write module-image \
  -n ARTIFACT_NAME \
  -t f2-jetson-orin-nx \
  -T script \
  -f path/to/script.sh \
  -o ARTIFACT_NAME.mender
```

Replace `ARTIFACT_NAME` with a unique release name following the `<function>-v<N>` convention (e.g. `restart-mender-connect-v3`). Always increment the version — Mender will not redeploy an artifact a device already reports as installed.

**2. Validate**:

```bash
mender-artifact read ARTIFACT_NAME.mender
```

Confirm `Compatible devices` shows `f2-jetson-orin-nx` and `Type: script` is listed.

**3. Upload**:

```bash
mender-cli artifacts upload ARTIFACT_NAME.mender
```

Then deploy from the Mender Cloud UI under Releases. See the [Mender Setup Guide](docs/mender-setup-guide.md) for multi-file artifacts, the full flag reference, and worked examples.

## Artifacts

### `f2-power-status/`

Collects and publishes a diagnostic snapshot to AWS IoT over MQTT.

| Script                | Purpose                                                                                                                                                     |
|-----------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `get-fan-status.sh`   | Reads fan PWM % and RPM via `jtop`, reads motor RPM and temperature from the CAN bus (`can0`), then publishes both logs as JSON to `tele/<device-id>/logs`. |
| `get-power-status.sh` | Queries the Jetson power mode via `nvpmodel -q` and publishes the mode name and ID to `tele/<device-id>/logs/power`.                                        |

Both scripts use the F2-App virtualenv (`/home/nvidia/projects/F2-App/.venv`) and the device certificates in `/home/nvidia/projects/F2-App/certs`.

### `install-mender-connect/`

**Script** `install-connect.sh`

Installs `mender-connect` (via `apt`) if not already present, writes a minimal config (`/etc/mender/mender-connect.conf`) that sets the shell to `/bin/bash` and the user to `nvidia`, then enables and restarts the service.

**Artifact** `install-mender-connect-v1.mender`

### `inventory-config-standarization/`

**Script** `inventory-config-standarized.sh`

Standardizes Mender inventory scripts on the device.

- Installs `mender-inventory-active-network`, reports the active routing interface and its type (ethernet / wifi / cellular), plus the preferred physical Ethernet interface (`eth1` → `eth2` → `eth0`).
- Installs `mender-inventory-device-info`, reads key=value pairs from `/etc/mender/device-info` and exposes them as inventory attributes.
- Installs `mender-inventory-check-in-time`, reports current UTC time as `device_utc_time`.
- Disables the geo inventory script.
- Migrates the device-info file, renames `device_name` → `device_location_name` if not already done.
- Creates symlinks from `/etc/mender/inventory/` into `/usr/share/mender/inventory/`.

**Artifact** `inventory-standardization-v1.mender`

### `inventory-memory-usage/`

**Script** `inventory-memory-usage.sh`

Installs `mender-inventory-memory-usage` into `/etc/mender/inventory/` (with a symlink in `/usr/share/mender/inventory/`). The installed script reports the following.

- `mem_used_kB`, memory in use (`MemTotal` − `MemAvailable` from `/proc/meminfo`)
- `disk_total_kB` / `disk_used_kB`, root filesystem usage via `df`

**Artifact** `inventory-memory-usage-v1.mender`

### `restart-mender-connect/`

**Script** `restart-mender-connect.sh`

Runs `systemctl restart mender-connect`. Failures are suppressed so the artifact always reports success.

**Artifacts**:

- `restart-mender-connect-v1.mender`
- `restart-mender-connect-v2.mender`

### `update-sn-f2-alias/`

**Script** `update-sn-f2-alias.sh`

Updates the `sn-board-f2` alias in `/home/nvidia/.bashrc` to the correct `i2ctransfer` form:

```bash
alias sn-board-f2="sudo i2ctransfer -f -y 1 w1@0x58 0x80 r16 | sed 's/0x//g'"
```

The script is idempotent — if the alias is already at the target definition it exits immediately. Otherwise it rewrites the existing `alias sn-board-f2=` line in place (dropping any trailing continuation line) and restores the original file ownership. If `.bashrc` does not exist the script exits without error.

**Artifact** `update-sn-f2-alias-v1.mender`

### `send-cert-name/`

**Script** `send-cert-name.sh`

Looks up the device's AWS IoT certificate filename (the `-certificate.pem.crt` file in `/home/nvidia/projects/F2-App/certs`) and publishes it to `tele/<device-id>/logs/cert` over MQTT. Useful for auditing which certificate is active on a device.

**Artifact** `send-cert-name-v1.mender`

## Common dependencies

| Dependency                                            | Used by                                  |
|-------------------------------------------------------|------------------------------------------|
| F2-App virtualenv (`aiomqtt`, `jtop`)                 | `f2-power-status`, `send-cert-name`      |
| AWS IoT certs in `/home/nvidia/projects/F2-App/certs` | `f2-power-status`, `send-cert-name`      |
| `get-device-id-f2.sh` (`f2-maintenance-tools`)        | `f2-power-status`, `send-cert-name`      |
| `candump` (can-utils)                                 | `get-fan-status.sh` (CAN log collection) |
| `nvpmodel` (Jetson)                                   | `get-power-status.sh`                    |
| `mender-connect` package                              | `install-mender-connect`                 |
