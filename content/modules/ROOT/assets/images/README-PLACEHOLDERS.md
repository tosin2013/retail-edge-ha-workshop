# Module 0 Placeholder Images

This document describes the placeholder images needed for Module 0: Fleet Management Overview.

## Required Images

### 1. fleet-overview-map.png
**Purpose:** Show retail edge fleet distribution across the United States

**Content:**
- Map of the United States
- 500 store location markers (dots or pins)
- Color-coded by region:
  - West Coast (blue): 150 stores
  - Central (green): 200 stores
  - East Coast (red): 150 stores
- 3 regional data center markers (larger icons)
- Legend showing store count per region

**Dimensions:** 1200x800 px

**Tools:** Can be created with:
- Draw.io / diagrams.net
- Canva
- PowerPoint with map background
- Mermaid diagram (map chart)

---

### 2. rhacm-hub-spoke.png
**Purpose:** Illustrate RHACM hub-and-spoke architecture

**Content:**
- Central "Hub Cluster" (large box at top)
  - Label: "RHACM Hub Cluster (Regional Data Center)"
  - Icons: Dashboard, policy engine, observability
- Multiple "Spoke Clusters" below (smaller boxes)
  - Labels: "Store 1", "Store 2", "Store 3", "... Store N"
  - Arrows connecting each spoke to hub
- Callouts showing:
  - Hub → Spokes: "Deploy policies, apps, updates"
  - Spokes → Hub: "Send metrics, alerts, status"

**Dimensions:** 1200x600 px

**Style:** Simple architecture diagram with boxes and arrows

---

### 3. fleet-dashboard-inventory.png
**Purpose:** Simulated RHACM inventory dashboard

**Content:**
- Screenshot-style dashboard mockup
- Top metrics bar:
  - Total Clusters: 1,003 (1,000 devices + 3 regional)
  - Status: 953 Ready, 50 Offline
  - Compliance: 95% (980/1,003)
- Table showing clusters:
  ```
  NAME                      STATUS  VERSION   NODES  REGION    LAST SEEN
  store-0001-chicago-il     Ready   4.21.6    2      central   30s ago
  store-0002-boston-ma      Ready   4.21.6    2      east      45s ago
  store-0234-dallas-tx      Offline 4.21.2    2      central   5m ago
  ...
  ```
- Filters/search bar at top
- Visual indicators (green checkmarks, red X's, yellow warnings)

**Dimensions:** 1400x900 px

**Tools:**
- Figma (mockup tool)
- HTML/CSS (actual table rendering)
- Screenshot from real RHACM demo environment (if available)

---

### 4. fleet-dashboard-compliance.png
**Purpose:** Simulated RHACM compliance dashboard

**Content:**
- Donut chart showing compliance:
  - Green: 980 clusters compliant (98%)
  - Yellow: 15 clusters need updates (1.5%)
  - Red: 5 clusters out of compliance (0.5%)
- Policy violations table:
  ```
  POLICY NAME                    VIOLATED CLUSTERS  SEVERITY
  require-minimum-rhcos-version  5                  High
  enforce-resource-limits        10                 Medium
  network-policy-required        5                  Medium
  ```
- Timeline showing compliance trend (last 30 days)
- Remediation status: "Auto-remediation scheduled: 15 clusters"

**Dimensions:** 1400x700 px

---

### 5. fleet-dashboard-updates.png
**Purpose:** Simulated update orchestration dashboard

**Content:**
- Progressive rollout visualization:
  - Stage 1 (Canary): 5% - 25 clusters ✓ Complete
  - Stage 2: 10% - 50 clusters ⟳ In Progress (35/50)
  - Stage 3: 25% - 125 clusters ⏳ Pending
  - Stage 4: 50% - 250 clusters ⏳ Pending
  - Stage 5: 100% - 500 clusters ⏳ Pending
- Update details box:
  - Image: rhcos-4.21.6
  - Start time: 2026-03-25 02:00 EST
  - Estimated completion: 2026-03-28 05:00 EST
- Rollback button (grayed out unless issues detected)
- Graph showing update progress over time

**Dimensions:** 1400x800 px

---

### 6. workshop-fleet-context.png
**Purpose:** Show how workshop VMs relate to real fleet scale

**Content:**
- Left side: "Your Workshop" (small scale)
  - 2 VMs (Module 1)
  - 2 VMs (Module 2)
  - 3 VMs (Module 3)
- Arrow pointing right with "×200" multiplier
- Right side: "Production Fleet" (large scale)
  - 400 Pacemaker servers
  - 1,000 MicroShift gateways
  - 200 OpenShift nodes
- Visual comparison (small boxes → many small boxes)

**Dimensions:** 1200x600 px

**Style:** Infographic with icons and multiplication arrows

---

### 7. module0-workshop-vms.png
**Purpose:** Diagram showing workshop VM layout and networking

**Content:**
- Tree structure showing:
  ```
  retail-edge-student-XX/
  ├── Module 1 (Pacemaker)
  │   ├── rhel-ha-node1 (10.101.0.20)
  │   └── rhel-ha-node2 (10.101.0.21)
  ├── Module 2 (MicroShift)
  │   ├── microshift-gw-a (10.102.0.20)
  │   └── microshift-gw-b (10.102.0.21)
  └── Module 3 (Two-Node OpenShift)
      ├── twonode-master1 (10.103.0.20)
      ├── twonode-master2 (10.103.0.21)
      └── twonode-arbiter (10.103.0.22)
  ```
- Network isolation indicators (UDNs)
- Color-coding by module

**Dimensions:** 1000x800 px

**Tools:**
- Terminal screenshot with `tree` command
- Mermaid graph diagram
- Draw.io network diagram

---

## Creating Placeholder Images

### Option 1: Use Existing Workshop Images
If similar images exist in other modules (e.g., module1-lab-architecture.png), create placeholders that reference them:

```asciidoc
image::fleet-overview-map.png[Fleet Distribution (Placeholder), align=center]

NOTE: This diagram will show 500 retail store locations across the US. For now, imagine the map from the workshop introduction scaled to 500 locations.
```

### Option 2: Generate Simple Placeholders
Create simple text-based placeholders:

```bash
# Install ImageMagick
sudo dnf install ImageMagick

# Create placeholder
convert -size 1200x800 xc:lightgray \
  -pointsize 48 -fill black \
  -gravity center -annotate +0+0 "Fleet Overview Map\n(Placeholder - 500 stores)" \
  fleet-overview-map.png
```

### Option 3: Use Mermaid Diagrams (Recommended)
For architecture diagrams, use Mermaid within AsciiDoc:

```asciidoc
[mermaid]
----
graph TB
    Hub[RHACM Hub Cluster<br/>Regional Data Center]
    Hub --> Store1[Store 1<br/>Spoke Cluster]
    Hub --> Store2[Store 2<br/>Spoke Cluster]
    Hub --> Store3[Store N<br/>Spoke Cluster]
----
```

### Option 4: Use Actual Screenshots
If you have access to a RHACM demo environment:
1. Login to multicloud-console
2. Navigate to Clusters → Inventory
3. Take screenshot of dashboard
4. Crop and resize to specifications

---

## Priority Order

Create images in this order:

1. **module0-workshop-vms.png** (easy - tree diagram)
2. **workshop-fleet-context.png** (easy - infographic)
3. **rhacm-hub-spoke.png** (medium - architecture diagram)
4. **fleet-overview-map.png** (medium - map with markers)
5. **fleet-dashboard-inventory.png** (hard - dashboard mockup)
6. **fleet-dashboard-compliance.png** (hard - dashboard mockup)
7. **fleet-dashboard-updates.png** (hard - dashboard mockup)

Alternatively, use Mermaid diagrams inline for items 1-4, and text placeholders with notes for items 5-7.

---

## Alternative: Text-Only Module 0

If creating images is not feasible, Module 0 can work without images by:

1. Using ASCII art for diagrams
2. Using detailed text descriptions
3. Adding "NOTE:" callouts explaining what would be shown

Example:
```asciidoc
== Fleet Distribution

NOTE: Imagine a map of the United States with 500 store locations marked:
- West Coast: 150 stores (California, Oregon, Washington)
- Central: 200 stores (Texas, Illinois, Colorado, etc.)
- East Coast: 150 stores (New York, Florida, Massachusetts)
- 3 regional data centers: San Francisco, Chicago, New York
```

This approach keeps the content educational without requiring graphic design work.

---

**Last Updated:** 2026-03-25
**Maintainer:** Workshop Content Team
