# Quick Start Guide - Torrent Transfer Script

## 5-Minute Setup

### Step 1: Enable qBittorrent Web UI

1. Open **qBittorrent** → **Preferences** → **Web UI**
2. Check **"Enable Web User Interface (Remote control)"**
3. Set Username: `admin`
4. Set Password: (choose a password)
5. Port: `8080`
6. Click **Save**

### Step 2: Get Tautulli API Key

1. Open **Tautulli** web interface
2. **Settings** → **Web Interface**
3. Copy your **API Key**

### Step 3: Create Local Download Directory

```bash
mkdir -p /Volumes/WD_BLACK_SN770_1TB/torrents
```

### Step 4: Set qBittorrent Default Save Path

1. **qBittorrent** → **Preferences** → **Downloads**
2. **Default Save Path**: `/Volumes/WD_BLACK_SN770_1TB/torrents`
3. Click **Save**

### Step 5: Configure the Script

```bash
cd /Volumes/WD_BLACK_SN770_1TB/code_claude/scripts

# Run once to create config file
./torrent-transfer.sh --check-all

# Edit config file
nano torrent-transfer.conf
```

Update these two lines:
```bash
QBITTORRENT_PASSWORD="your-password-from-step-1"
TAUTULLI_API_KEY="your-api-key-from-step-2"
```

Save and exit (Ctrl+O, Enter, Ctrl+X)

## Daily Usage

### Add and Download a Torrent

1. Add torrent to qBittorrent (downloads to SSD automatically)
2. Wait for it to complete

### Transfer to NAS

```bash
cd /Volumes/WD_BLACK_SN770_1TB/code_claude/scripts

# See what's ready to transfer
./torrent-transfer.sh --check-all

# Copy the torrent hash from qBittorrent (right-click → Copy → Hash)
# Then transfer it
./torrent-transfer.sh <paste-hash-here>
```

### What Happens Next

The script will:
- ✅ Check if Plex is streaming
- ⏳ Wait if Plex is busy (checks every 5 minutes)
- 📦 Transfer files to NAS when Plex is idle
- 🔄 Update qBittorrent to point to NAS location
- ✔️ Verify files transferred correctly
- 🗑️ Delete SSD copy (only after successful verification)

### Monitor Progress

```bash
# Watch logs in real-time
tail -f torrent-transfer.log
```

## Example

```bash
# 1. Check what's ready
./torrent-transfer.sh --check-all

# Output shows:
# [INFO] Found torrent: My.Movie.2024.1080p.BluRay (state: uploading, hash: abc123...)
# [INFO] This torrent is ready for transfer

# 2. Transfer it
./torrent-transfer.sh abc123...

# Output shows:
# [INFO] Current Plex streams: 1
# [INFO] Plex is busy, checking again in 300 seconds...
# (waits...)
# [INFO] Current Plex streams: 0
# [SUCCESS] Plex is idle
# [INFO] Transferring files...
# [SUCCESS] Transfer complete
# [SUCCESS] Updated qBittorrent location
# [INFO] Initiating verification...
# [SUCCESS] Verification complete!
# [INFO] Deleting local copy...
# [SUCCESS] Transfer process completed successfully
```

## Troubleshooting

**Can't login to qBittorrent?**
- Make sure Web UI is enabled in qBittorrent preferences
- Check username/password in `torrent-transfer.conf`

**NAS not found?**
- Check if NFS is mounted: `mount | grep tower.local`
- If not, run: `cd .. && sudo ./mount-unraid-nfs.sh`

**Tautulli error?**
- Verify Tautulli is running
- Check API key in config file

## Tips

- The script is safe - it verifies files before deleting the SSD copy
- If verification fails, local files are preserved
- You can set `MAX_ACTIVE_STREAMS=1` in config to allow transfers during single-stream playback
- All actions are logged to `torrent-transfer.log`

## Need More Help?

See the full documentation: `README-TORRENT-TRANSFER.md`
