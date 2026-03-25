# Workshop Diagrams

This directory contains Mermaid source files for workshop diagrams.

## Converting Mermaid to PNG

Since the workshop uses Showroom which requires PNG images, you'll need to convert these Mermaid diagrams to PNG format.

### Option 1: Mermaid Live Editor (Recommended)

1. Go to https://mermaid.live
2. Paste the contents of the `.mmd` file
3. Click "Actions" → "Export as PNG"
4. Save to `content/modules/ROOT/assets/images/`

### Option 2: Using mermaid-cli (Local)

If you have Node.js installed:

```bash
# Install mermaid-cli globally
npm install -g @mermaid-js/mermaid-cli

# Convert diagrams
mmdc -i module2-storage-architecture.mmd -o ../content/modules/ROOT/assets/images/module2-storage-architecture.png -b transparent
mmdc -i module3-storage-design.mmd -o ../content/modules/ROOT/assets/images/module3-storage-design.png -b transparent
```

### Option 3: Using Docker

```bash
docker run --rm -v $(pwd):/data minlag/mermaid-cli -i /data/module2-storage-architecture.mmd -o /data/module2-storage-architecture.png -b transparent
docker run --rm -v $(pwd):/data minlag/mermaid-cli -i /data/module3-storage-design.mmd -o /data/module3-storage-design.png -b transparent

# Move to assets directory
mv *.png ../content/modules/ROOT/assets/images/
```

## Required Diagrams

### New Storage Diagrams (Need PNG Conversion)
- [ ] `module2-storage-architecture.mmd` → `module2-storage-architecture.png`
- [ ] `module3-storage-design.mmd` → `module3-storage-design.png`

### Existing Diagrams (Already PNG)
- [x] `module1-lab-architecture.png`
- [x] `module1-real-architecture.png`
- [x] `module1-failover-flow.png`
- [x] `module1-fleet-manager.png`
- [x] `module2-lab-architecture.png`
- [x] `module2-real-architecture.png`
- [x] `module3-lab-architecture.png`
- [x] `module3-real-architecture.png`
- [x] `module3-cost-comparison.png`
- [x] `workshop-architecture.png`

## After Conversion

Once you've converted the Mermaid files to PNG:

1. Save PNGs to `content/modules/ROOT/assets/images/`
2. Verify they render in the workshop:
   ```bash
   antora site.yml --to-dir build/site
   ```
3. Commit the PNG files:
   ```bash
   git add content/modules/ROOT/assets/images/module2-storage-architecture.png
   git add content/modules/ROOT/assets/images/module3-storage-design.png
   git commit -m "Add storage architecture diagrams (PNG)"
   git push
   ```
