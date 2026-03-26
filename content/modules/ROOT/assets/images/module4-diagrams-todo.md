# Module 4 Architecture Diagrams - TODO

These diagrams need to be created to match the format of Modules 1-3.

## module4-lab-chaos.png

**Content:**
- Diagram showing chaos testing in workshop environment
- 7 VMs in student namespace
- Chaos injection points (stop, network partition, CPU stress, process kill)
- Monitoring/observation tools (oc, virtctl, logs)
- Recovery mechanisms

**Style:** Similar to module1-lab-architecture.png

**Dimensions:** 1200x800

---

## module4-real-chaos.png

**Content:**
- Diagram showing production GameDay across retail fleet
- 100+ stores with edge servers
- Regional chaos coordination (RHACM)
- Automated recovery systems
- Incident response team
- Stakeholder communication flows

**Style:** Similar to module1-real-architecture.png  

**Dimensions:** 1200x800

---

## How to Create

**Option 1: Use existing module diagrams as templates**
```bash
# Copy and modify existing diagrams
cp content/modules/ROOT/assets/images/module1-lab-architecture.png \
   content/modules/ROOT/assets/images/module4-lab-chaos.png

# Edit with draw.io or similar tool
```

**Option 2: Create new diagrams with draw.io**
1. Visit https://app.diagrams.net
2. Use retail edge workshop template
3. Add chaos injection elements
4. Export as PNG (1200x800)

**Option 3: Use Mermaid (temporary solution)**
Create inline diagram in module4-chaos.adoc if images not available.

---

**For now:** Module 4 references these images but they don't exist yet.
The module will still render, just without the comparison diagrams.

**Priority:** Medium (Module 4 is functional without them, but they improve clarity)
