# How to Generate PNG Diagrams from Mermaid Source

Module 0 currently uses inline Mermaid/Ditaa diagrams that render directly in Showroom/Antora. This document explains how to convert them to PNG images if screenshots are preferred.

## Current Status

✅ **Working inline diagrams** - Module 0 renders properly with:
- Mermaid graphs (hub-spoke, fleet context, VM layout)
- Mermaid charts (pie, gantt)
- AsciiDoc tables (inventory, compliance)
- Ditaa ASCII art (map)

## Why Convert to PNG?

Convert to PNG if you need:
- Screenshots for presentations
- Faster loading (pre-rendered vs client-side rendering)
- Consistent appearance across all browsers
- Print-friendly materials

## Option 1: Mermaid Live Editor (Easiest)

### Steps:

1. **Open Mermaid Live Editor**
   - Visit: https://mermaid.live

2. **Load diagram source**
   ```bash
   # Copy content from:
   content/modules/ROOT/assets/images/temp-diagrams/rhacm-hub-spoke.mmd
   ```

3. **Paste into editor**
   - Mermaid Live Editor renders it automatically

4. **Export as PNG**
   - Click "Actions" → "PNG"
   - Download high-resolution PNG
   - Save to: `content/modules/ROOT/assets/images/rhacm-hub-spoke.png`

5. **Repeat for all 5 Mermaid diagrams:**
   - `rhacm-hub-spoke.mmd` → `rhacm-hub-spoke.png`
   - `fleet-dashboard-compliance.mmd` → `fleet-dashboard-compliance.png`
   - `fleet-dashboard-updates.mmd` → `fleet-dashboard-updates.png`
   - `workshop-fleet-context.mmd` → `workshop-fleet-context.png`
   - `module0-workshop-vms.mmd` → `module0-workshop-vms.png`

## Option 2: Automated Script (Podman/Docker)

### Fix the script issue:

The `generate-module0-diagrams.sh` script has a container permission issue. Fix it:

```bash
# Edit the script to add --privileged or use rootless podman
cd /home/vpcuser/retail-edge-ha-workshop

# Option A: Run container with proper SELinux context
podman run --rm \
  -v $(pwd)/content/modules/ROOT/assets/images/temp-diagrams:/data:z \
  docker.io/minlag/mermaid-cli \
  -i /data/rhacm-hub-spoke.mmd \
  -o /data/rhacm-hub-spoke.png \
  -b transparent

# Option B: Use rootless podman with user namespace
podman run --rm --userns=keep-id \
  -v $(pwd)/content/modules/ROOT/assets/images/temp-diagrams:/data:z \
  docker.io/minlag/mermaid-cli \
  -i /data/rhacm-hub-spoke.mmd \
  -o /data/rhacm-hub-spoke.png \
  -b transparent
```

### Run for all diagrams:

```bash
cd /home/vpcuser/retail-edge-ha-workshop/content/modules/ROOT/assets/images/temp-diagrams

for mmd in *.mmd; do
    filename=$(basename "$mmd" .mmd)
    echo "Converting $mmd..."
    podman run --rm --userns=keep-id \
      -v $(pwd):/data:z \
      docker.io/minlag/mermaid-cli \
      -i "/data/$mmd" \
      -o "/data/$filename.png" \
      -b transparent \
      -w 1400 -H 900
done

# Move PNGs to images directory
mv *.png ../
```

## Option 3: Screenshot RHACM (For Realistic Dashboards)

For `fleet-dashboard-inventory.png`, `fleet-dashboard-compliance.png`, `fleet-dashboard-updates.png`:

### Access Real RHACM Instance:

1. **Login to RHACM hub cluster**
   ```bash
   oc login <hub-cluster-api>
   ```

2. **Get multicloud console URL**
   ```bash
   oc get route multicloud-console -n open-cluster-management -o jsonpath='{.spec.host}'
   # Example: https://multicloud-console.apps.hub.example.com
   ```

3. **Take screenshots:**
   - Navigate to: **Infrastructure** → **Clusters**
   - Screenshot the inventory table
   - Navigate to: **Governance** → **Policies**
   - Screenshot the compliance dashboard
   - Navigate to: **Applications** → **Advanced configuration** → **Cluster sets**
   - (Mock an update rollout if testing cluster available)

4. **Save screenshots:**
   - `fleet-dashboard-inventory.png` (1400x900)
   - `fleet-dashboard-compliance.png` (1400x700)
   - `fleet-dashboard-updates.png` (1400x800)

## Option 4: Create Fleet Map Image

For `fleet-overview-map.png`:

### Using draw.io (diagrams.net):

1. **Open draw.io**
   - Visit: https://app.diagrams.net

2. **Insert US map background**
   - File → Import → Search for "USA map"
   - Or use blank canvas

3. **Add store markers**
   - Use circle/pin shapes
   - Add 500 dots across regions:
     - West: 150 (California, Oregon, Washington)
     - Central: 200 (Texas, Illinois, Colorado, etc.)
     - East: 150 (New York, Florida, Massachusetts)

4. **Add data center icons**
   - Larger icons for 3 regional DCs
   - Labels: "West DC", "Central DC", "East DC"

5. **Export as PNG**
   - File → Export as → PNG
   - Resolution: 1200x800
   - Save as: `fleet-overview-map.png`

### Using PowerPoint/Keynote:

1. Insert US map image (free from Wikipedia)
2. Add scatter plot overlay with 500 points
3. Color-code by region
4. Export as PNG (1200x800)

### Using Python (if matplotlib available):

```python
import matplotlib.pyplot as plt
import geopandas as gpd

# Load US map
usa = gpd.read_file('path/to/usa-states.geojson')

# Plot stores
fig, ax = plt.subplots(figsize=(12, 8))
usa.plot(ax=ax, color='lightgray', edgecolor='black')

# Add store locations (sample coordinates)
west_stores = [(x, y) for x, y in west_coords]  # 150 points
central_stores = [(x, y) for x, y in central_coords]  # 200 points
east_stores = [(x, y) for x, y in east_coords]  # 150 points

ax.scatter(*zip(*west_stores), c='blue', s=20, label='West (150)')
ax.scatter(*zip(*central_stores), c='green', s=20, label='Central (200)')
ax.scatter(*zip(*east_stores), c='red', s=20, label='East (150)')

plt.legend()
plt.title('Retail Edge Fleet Distribution - 500 Stores')
plt.savefig('fleet-overview-map.png', dpi=150)
```

## After Generating PNGs

### Update module0-fleet-overview.adoc:

Replace inline diagrams with image references:

```asciidoc
# Before (inline Mermaid):
[mermaid]
....
graph TB
    Hub["RHACM Hub"]
....

# After (PNG image):
image::rhacm-hub-spoke.png[RHACM Hub-Spoke Architecture, align=center]
```

### Commit images to Git:

```bash
cd /home/vpcuser/retail-edge-ha-workshop

# Add all PNG images
git add content/modules/ROOT/assets/images/*.png

# Commit
git commit -m "Add Module 0 diagram images (PNG)

- rhacm-hub-spoke.png: Hub-spoke architecture
- fleet-dashboard-inventory.png: Cluster inventory dashboard
- fleet-dashboard-compliance.png: Compliance pie chart
- fleet-dashboard-updates.png: Progressive rollout gantt chart
- workshop-fleet-context.png: Workshop vs production scale
- module0-workshop-vms.png: VM namespace layout
- fleet-overview-map.png: US map with store distribution"

# Push to GitHub
git push origin main
```

## Current Recommendation

**Keep inline diagrams for now** because:
- ✅ They render properly in Showroom/Antora
- ✅ No broken image links
- ✅ Easy to update (edit text, not regenerate images)
- ✅ Version control friendly (text diffs)
- ✅ Can replace with screenshots later without breaking content

**Add PNG screenshots later** when:
- You have access to real RHACM instance
- You want higher-quality graphics for presentations
- You need offline/print materials

---

**Last Updated:** 2026-03-25
**Status:** Inline diagrams working, PNG conversion optional
