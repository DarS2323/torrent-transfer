# Torrent Transfer Script

Automate the process of downloading torrents to your fast local SSD, then transferring them to the NAS when Plex is idle.

## Overview

This script solves the problem of downloading large torrents on a Mac with limited internal storage by:

1. **Downloading** torrents to the external SSD (`/Volumes/WD_BLACK_SN770_1TB/torrents`)
2. **Monitoring** Plex activity via Tautulli to wait for idle time
3. **Transferring** completed torrents to the NAS (`/Volumes/media/torrents/complete`)
4. **Updating** qBittorrent to point to the new NAS location
5. **Verifying** the torrent files at the new location
6. **Cleaning up** by deleting the local SSD copy

## Prerequisites

### 1. qBittorrent Web UI Configuration

Enable the Web UI in qBittorrent:

1. Open qBittorrent
2. Go to **Preferences** → **Web UI**
3. Check **Enable Web User Interface (Remote control)**
4. Set authentication:
   - Username: `admin` (or your choice)
   - Password: (set a strong password)
5. Port: `8080` (default, or your choice)
6. Click **Save**

### 2. Tautulli API Key

Get your Tautulli API key:

1. Open Tautulli web interface
2. Go to **Settings** → **Web Interface**
3. Copy your **API Key**

### 3. Directory Setup

Create the local download directory on your SSD:

```bash
mkdir -p /Volumes/WD_BLACK_SN770_1TB/torrents
```

Verify the NAS mount is active:

```bash
mount | grep tower.local
ls -la /Volumes/media/torrents/complete
```

If the NAS is not mounted, run:

```bash
cd /Volumes/WD_BLACK_SN770_1TB/code_claude
sudo ./mount-unraid-nfs.sh
```

## Installation

### 1. Install the Script

The script is already located at:
```
/Volumes/WD_BLACK_SN770_1TB/code_claude/scripts/torrent-transfer.sh
```

### 2. Create Configuration File

On first run, the script will create a template configuration file. Run:

```bash
cd /Volumes/WD_BLACK_SN770_1TB/code_claude/scripts
./torrent-transfer.sh --check-all
```

This will create `torrent-transfer.conf`. Edit it with your credentials:

```bash
nano torrent-transfer.conf
```

Update these values:

```bash
# qBittorrent credentials
QBITTORRENT_USERNAME="admin"
QBITTORRENT_PASSWORD="your-qbittorrent-password"

# Tautulli API key
TAUTULLI_API_KEY="your-tautulli-api-key"
```

**Important:** The config file is automatically set to `chmod 600` (owner-only read/write) for security.

### 3. Configure qBittorrent Download Location

In qBittorrent, set your default save path to the SSD:

1. Go to **Preferences** → **Downloads**
2. Set **Default Save Path** to: `/Volumes/WD_BLACK_SN770_1TB/torrents`
3. Click **Save**

## Automatic Mode (qBittorrent Integration)

### Setup qBittorrent Auto-Transfer

The recommended way to use this script is to have qBittorrent automatically trigger it when torrents complete:

1. **Enable "Run on Completion" in qBittorrent:**
   - Go to **Settings** → **Downloads**
   - Find **"Run external program on torrent completion"**
   - Check the box to enable it
   - Enter the following command (use absolute path):
     ```
     /Volumes/WD_BLACK_SN770_1TB/code_claude/scripts/torrent-transfer/qbittorrent-completion.sh "%I" "%N"
     ```

2. **How It Works:**
   - When a torrent completes, qBittorrent calls `qbittorrent-completion.sh`
   - The wrapper script launches `torrent-transfer.sh` in the background
   - qBittorrent continues immediately without waiting
   - Transfer happens when Plex streams ≤ 1 (configurable)
   - Files move to NAS automatically
   - Local SSD copy is cleaned up

3. **Monitor Automatic Transfers:**
   ```bash
   # Watch completion triggers
   tail -f /Volumes/WD_BLACK_SN770_1TB/code_claude/scripts/torrent-transfer/qbittorrent-completion.log

   # Watch transfer progress
   tail -f /Volumes/WD_BLACK_SN770_1TB/code_claude/scripts/torrent-transfer/torrent-transfer.log
   ```

### qBittorrent Parameters

The script uses these parameters from qBittorrent:
- `%I` - Info hash (torrent hash) - Required
- `%N` - Torrent name - For logging

**Important Notes:**
- Always use the full absolute path to `qbittorrent-completion.sh`
- The script runs in the background so qBittorrent doesn't wait
- Transfers wait for Plex to have ≤1 active stream (configurable in `torrent-transfer.conf`)

## Manual Usage

### Check All Torrents Ready for Transfer

See which completed torrents are on the SSD:

```bash
./torrent-transfer.sh --check-all
```

This will list all torrents in the local directory and their status.

### Transfer a Specific Torrent

Transfer a single torrent by its hash:

```bash
./torrent-transfer.sh <torrent-hash>
```

To get a torrent's hash:
- Right-click the torrent in qBittorrent → **Copy** → **Hash**

### Example Workflow

1. Add a torrent to qBittorrent (it downloads to the SSD)
2. Wait for it to complete
3. Check what's ready: `./torrent-transfer.sh --check-all`
4. Transfer it: `./torrent-transfer.sh abc123def456...`
5. The script will:
   - Check Plex activity via Tautulli
   - Wait if Plex is streaming
   - Transfer files when idle
   - Update qBittorrent location
   - Verify the files
   - Delete the SSD copy

## Configuration Options

Edit `torrent-transfer.conf` to customize:

| Option | Description | Default |
|--------|-------------|---------|
| `LOCAL_DOWNLOAD_DIR` | SSD directory for downloads | `/Volumes/WD_BLACK_SN770_1TB/torrents` |
| `NAS_DESTINATION` | NAS destination directory | `/Volumes/media/torrents/complete` |
| `QBITTORRENT_HOST` | qBittorrent host | `localhost` |
| `QBITTORRENT_PORT` | qBittorrent Web UI port | `8080` |
| `QBITTORRENT_USERNAME` | qBittorrent username | `admin` |
| `QBITTORRENT_PASSWORD` | qBittorrent password | (required) |
| `TAUTULLI_HOST` | Tautulli host | `localhost` |
| `TAUTULLI_PORT` | Tautulli port | `8181` |
| `TAUTULLI_API_KEY` | Tautulli API key | (required) |
| `MAX_ACTIVE_STREAMS` | Max Plex streams before waiting | `1` (wait for ≤1 stream) |
| `CHECK_INTERVAL` | Seconds between Plex checks | `300` (5 minutes) |
| `VERIFY_AFTER_TRANSFER` | Verify torrent after transfer | `true` |

## How It Works

### Step-by-Step Process

1. **Validation:**
   - Checks that local and NAS directories exist
   - Verifies NFS mount is active
   - Validates configuration

2. **Torrent Information:**
   - Logs into qBittorrent Web API
   - Retrieves torrent details (name, location, state)
   - Verifies torrent is complete and on the SSD

3. **Plex Activity Monitoring:**
   - Queries Tautulli for active stream count
   - If streams > `MAX_ACTIVE_STREAMS`, waits and rechecks
   - Continues when Plex is idle

4. **File Transfer:**
   - Uses `rsync` for reliable transfer with progress
   - Handles both single files and directories
   - Preserves permissions and timestamps

5. **qBittorrent Update:**
   - Updates torrent location to NAS path
   - Initiates recheck/verification
   - Waits for verification to complete

6. **Cleanup:**
   - Deletes original files from SSD
   - Logs all actions to `torrent-transfer.log`

## Logs

All operations are logged to:
```
/Volumes/WD_BLACK_SN770_1TB/code_claude/scripts/torrent-transfer.log
```

View logs in real-time:
```bash
tail -f torrent-transfer.log
```

View recent activity:
```bash
tail -50 torrent-transfer.log
```

## Troubleshooting

### "NFS mount not found"

Check if the NFS mount is active:
```bash
mount | grep tower.local
```

If not mounted, mount it:
```bash
cd /Volumes/WD_BLACK_SN770_1TB/code_claude
sudo ./mount-unraid-nfs.sh
```

### "Failed to login to qBittorrent"

1. Verify qBittorrent Web UI is enabled:
   - Open qBittorrent → Preferences → Web UI
   - Check "Enable Web User Interface"

2. Verify credentials in `torrent-transfer.conf`

3. Test manually:
   ```bash
   curl -i --data "username=admin&password=yourpass" http://localhost:8080/api/v2/auth/login
   ```

### "Failed to get Plex activity from Tautulli"

1. Verify Tautulli is running
2. Check API key in `torrent-transfer.conf`
3. Test manually:
   ```bash
   curl "http://localhost:8181/api/v2?apikey=YOUR_API_KEY&cmd=get_activity"
   ```

### "Torrent not found"

Make sure you're using the correct torrent hash. Get it from qBittorrent:
- Right-click torrent → Copy → Hash

### Verification Fails

If verification fails after transfer:

1. Check that files transferred correctly:
   ```bash
   ls -la /Volumes/media/torrents/complete/
   ```

2. The script will NOT delete local files if verification fails
3. Manually recheck in qBittorrent if needed

### Permission Issues

If you get permission errors:

1. Check directory permissions:
   ```bash
   ls -la /Volumes/WD_BLACK_SN770_1TB/torrents
   ls -la /Volumes/media/torrents/complete
   ```

2. Ensure qBittorrent has permission to access both locations

## Advanced Usage

### Automatic Transfer with Cron

Set up a cron job to automatically check and transfer completed torrents:

```bash
# Edit crontab
crontab -e

# Add this line to check every hour
0 * * * * /Volumes/WD_BLACK_SN770_1TB/code_claude/scripts/torrent-transfer.sh --check-all
```

### Custom Transfer Script

Create a wrapper script for specific torrents:

```bash
#!/bin/bash
# transfer-specific.sh

# Array of torrent hashes to transfer
TORRENTS=(
    "abc123def456..."
    "xyz789uvw012..."
)

for hash in "${TORRENTS[@]}"; do
    /Volumes/WD_BLACK_SN770_1TB/code_claude/scripts/torrent-transfer.sh "$hash"
done
```

### Skip Plex Check for Urgent Transfers

Temporarily set `MAX_ACTIVE_STREAMS` to a high number in the config:

```bash
MAX_ACTIVE_STREAMS=999
```

This will transfer immediately regardless of Plex activity.

## Safety Features

- **Verification:** Torrents are rechecked after transfer to ensure integrity
- **No Auto-Delete on Failure:** Local files are preserved if verification fails
- **Atomic Operations:** Uses rsync for reliable file transfers
- **Logging:** All operations logged for audit trail
- **Pre-flight Checks:** Validates directories and mounts before transfer
- **Plex-Aware:** Waits for idle time to avoid impacting streaming

## Integration with Sonarr/Radarr

After transfer, Sonarr/Radarr will automatically detect the completed download in `/Volumes/media/torrents/complete` and:

1. Import the media
2. Rename and organize it
3. Update Plex library
4. Mark the download as complete

The torrent continues seeding from the NAS location.

## Files

- `qbittorrent-completion.sh` - qBittorrent completion hook wrapper (for automatic mode)
- `torrent-transfer.sh` - Main transfer script
- `torrent-transfer.conf` - Configuration file (auto-generated on first run)
- `qbittorrent-completion.log` - Log of qBittorrent completion triggers
- `torrent-transfer.log` - Detailed transfer activity log
- `README.md` - This documentation

## Security Notes

- Configuration file (`torrent-transfer.conf`) is automatically set to `chmod 600` (owner-only access)
- Contains sensitive credentials (qBittorrent password, Tautulli API key)
- Never commit the config file to git
- Keep API keys secure

## Support

For issues or questions:
1. Check the log file: `torrent-transfer.log`
2. Verify configuration in `torrent-transfer.conf`
3. Test individual components (qBittorrent API, Tautulli API, NFS mount)

## Cross-Seed Setup (Ultra.cc Seedbox)

Cross-seed finds matching torrents across trackers to improve your ratio. This runs on the Ultra.cc seedbox alongside qBittorrent.

### Prerequisites

- Ultra.cc seedbox with SSH access
- qBittorrent running on Ultra.cc

### Prowlarr Setup

Cross-seed needs Prowlarr running on the seedbox to search your trackers via Torznab API.

1. In the Ultra.cc control panel (UCP), go to **Installers** → find **Prowlarr** → click **Install**
2. Note the URL and port assigned after installation
3. Open Prowlarr's web UI and go to **Indexers** → **Add Indexer**
4. Search for your tracker, enter your credentials/passkey, test and save
5. Back on the **Indexers** page, copy the **Torznab Feed** URL for the indexer you added — it looks like:
   ```
   http://localhost:<prowlarr-port>/1/api?apikey=<prowlarr-api-key>
   ```
   The indexer ID (`1`) may differ if you have multiple indexers.

### Cross-Seed Installation

SSH into your seedbox and run the following:

```bash
# 1. Install Node.js 22 LTS
bash <(wget -qO- https://scripts.ultra.cc/util-v2/LanguageInstaller/Node-Installer/main.sh)

# 2. Install Python 3.10+
bash <(wget -qO- https://scripts.ultra.cc/util-v2/LanguageInstaller/Python-Installer/main.sh)
```

**Log out and back in** to update your PATH, then:

```bash
# 3. Install cross-seed
bash <(wget -qO- https://raw.githubusercontent.com/zakkarry/cross-seed-source-build/refs/heads/master/install_shared_env_xs.sh)

# 4. Generate config and API key
cross-seed gen-config
cross-seed api-key
```

### Configuration

Edit `~/.cross-seed/config.js`:

```js
module.exports = {
  qbittorrentUrl: "http://localhost:<qbit-port>",
  torrentDir: "/home/<username>/.local/share/qBittorrent/BT_backup",
  dataDirs: ["/home/<username>/downloads"],
  torznab: [
    "http://localhost:<prowlarr-port>/1/api?apikey=<prowlarr-api-key>",
  ],
  matchMode: "flexible",
  action: "inject",
};
```

Replace `<username>`, `<qbit-port>`, `<prowlarr-port>`, and `<prowlarr-api-key>` with your Ultra.cc values.

### Usage

```bash
# Run a search manually
cross-seed search
```

> **Note:** Ultra.cc recommends against running cross-seed in daemon mode on shared infrastructure due to the unauthenticated API. Use manual searches or cron instead.

### References

- [Ultra.cc cross-seed docs](https://docs.ultra.cc/community/cross-seed)
- [cross-seed official docs](https://www.cross-seed.org/)

## License

Part of the code_claude media server automation ecosystem.
