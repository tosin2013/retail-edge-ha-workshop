#!/bin/bash
# =============================================================================
# Generate Module 0 Diagrams from Mermaid Source
# =============================================================================
# This script converts Mermaid diagram source files (.mmd) to PNG images
# for use in Module 0: Fleet Management Overview.
#
# Prerequisites:
#   - Node.js and npm installed
#   - Mermaid CLI: npx @mermaid-js/mermaid-cli
#   OR
#   - Docker installed (alternative method)
#
# Usage:
#   ./scripts/generate-module0-diagrams.sh
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"&& pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEMP_DIR="${REPO_ROOT}/content/modules/ROOT/assets/images/temp-diagrams"
OUTPUT_DIR="${REPO_ROOT}/content/modules/ROOT/assets/images"

echo "=========================================="
echo "Module 0 Diagram Generation"
echo "=========================================="
echo "Input:  ${TEMP_DIR}"
echo "Output: ${OUTPUT_DIR}"
echo ""

# Check if Podman or Docker is available (preferred method)
if command -v podman &> /dev/null; then
    CONTAINER_CMD="podman"
    echo "✓ Using Podman method (recommended)"
    echo ""
elif command -v docker &> /dev/null; then
    CONTAINER_CMD="docker"
    echo "✓ Using Docker method (recommended)"
    echo ""
fi

if [ -n "${CONTAINER_CMD}" ]; then
    # Use Mermaid container
    for mmd_file in "${TEMP_DIR}"/*.mmd; do
        filename=$(basename "$mmd_file" .mmd)
        echo "Converting ${filename}.mmd → ${filename}.png"

        ${CONTAINER_CMD} run --rm -v "${TEMP_DIR}:/data:Z" docker.io/minlag/mermaid-cli \
            -i "/data/${filename}.mmd" \
            -o "/data/${filename}.png" \
            -b transparent \
            -w 1200 \
            -H 800

        # Move to output directory
        mv "${TEMP_DIR}/${filename}.png" "${OUTPUT_DIR}/${filename}.png"
        echo "✓ Created ${OUTPUT_DIR}/${filename}.png"
    done

elif command -v npx &> /dev/null; then
    echo "✓ Using npx method (requires Chrome dependencies)"
    echo ""

    cd "${TEMP_DIR}"

    for mmd_file in *.mmd; do
        filename=$(basename "$mmd_file" .mmd)
        echo "Converting ${filename}.mmd → ${filename}.png"

        npx -y @mermaid-js/mermaid-cli \
            -i "${filename}.mmd" \
            -o "${filename}.png" \
            -b transparent \
            2>&1 | grep -v "warn deprecated" || true

        # Move to output directory
        mv "${filename}.png" "${OUTPUT_DIR}/${filename}.png"
        echo "✓ Created ${OUTPUT_DIR}/${filename}.png"
    done

else
    echo "❌ ERROR: Neither Podman/Docker nor npx is available"
    echo ""
    echo "Please install one of the following:"
    echo ""
    echo "Option 1: Podman (recommended for RHEL)"
    echo "  sudo dnf install podman"
    echo ""
    echo "Option 2: Docker"
    echo "  sudo dnf install docker"
    echo "  sudo systemctl start docker"
    echo ""
    echo "Option 3: Node.js/npm"
    echo "  sudo dnf install nodejs npm"
    echo ""
    echo "Then re-run this script."
    exit 1
fi

# Create additional placeholder images for non-Mermaid diagrams
echo ""
echo "Creating additional placeholder images..."

# Fleet overview map (will be replaced with actual map)
convert -size 1200x800 xc:lightgray \
    -pointsize 48 -fill black -gravity North \
    -annotate +0+100 "Fleet Distribution Map" \
    -pointsize 24 -fill gray \
    -annotate +0+160 "(Replace with US map showing 500 store locations)" \
    "${OUTPUT_DIR}/fleet-overview-map.png" 2>/dev/null || \
    echo "⚠️  ImageMagick not available - fleet-overview-map.png not created"

echo ""
echo "=========================================="
echo "✅ Diagram Generation Complete!"
echo "=========================================="
echo ""
echo "Generated images:"
ls -1 "${OUTPUT_DIR}"/*.png 2>/dev/null || echo "No PNG files found"
echo ""
echo "Next steps:"
echo "1. Review generated images in ${OUTPUT_DIR}"
echo "2. Replace placeholders with high-quality screenshots if needed"
echo "3. Commit images to Git:"
echo "   git add content/modules/ROOT/assets/images/*.png"
echo "   git commit -m 'Add Module 0 diagram images'"
echo ""
