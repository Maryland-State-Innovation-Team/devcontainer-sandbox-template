# Claude Code Secure Devcontainer
### Maryland State Innovation Team

A standardized, sandboxed Claude Code environment for government staff. Built on WSL2 + Docker + VS Code Dev Containers.

> **Policy Compliance:** This sandbox is designed to align with the [State of Maryland's Responsible AI Policy](https://doit.maryland.gov/policies/ai/Pages/maryland-responsible-ai-policy.aspx) (DoIT, May 2025). See the [AI Governance & Compliance](#ai-governance--compliance-it-and-ai-leads) section for required agency steps before deploying any AI system to production.

> **Two audiences, two sections:**
> - **[Team Members →](#-for-team-members-using-claude)** How to open a project and start a Claude session (no technical knowledge needed).
> - **[IT Staff →](#️-for-it-staff-setup--maintenance)** One-time machine setup, security architecture, and maintenance commands.

---

## For Team Members: Using Claude

### What this is

This tool gives you a safe, pre-configured environment to use Claude Code — Anthropic's AI coding assistant. You describe what you want to build in plain English, and Claude builds it. Your Windows files and the rest of your laptop are never at risk; Claude can only touch files inside its own workspace folder.

---

### Starting a New Project

**Step 1 — Open VS Code**
Click the VS Code icon on your Windows desktop.

**Step 2 — Open your project folder in WSL**
Press `Ctrl+Shift+P`, type **WSL: Open Folder in WSL**, and press Enter. Navigate to your project folder under `/home/your-username/` and open it.

> **Important:** Your project folder must be under `/home/your-username/` in WSL — not under `C:\Users\...` on Windows. If you're not sure where to put it, ask IT to create a folder for you.

**Step 3 — Open in the container**
VS Code will show a blue pop-up in the bottom-right corner asking **"Reopen in Container"** — click it. The first time you do this for a project, it takes about 2 minutes to build. After that, it opens instantly.

**Step 4 — Open the terminal**
Click **Terminal** in the top menu bar, then **New Terminal**. A panel will appear at the bottom of the screen.

**Step 5 — Start Claude**
In the terminal, type:
```
claude
```
...and press Enter. Claude is now running and waiting for your instructions.

**Step 6 — Describe what you want**
Type your request in plain English and press Enter. For example:
> *"Build a simple data dashboard that shows child poverty rates by county on an interactive web map."*

Claude will ask clarifying questions if needed and then build it.

---

### Viewing Apps Claude Builds

When Claude builds and runs a web application, look for the **Ports** tab at the bottom of VS Code (it's next to the Terminal tab). You'll see a line appear with a port number and a globe icon — click it to open the app in your browser. No commands needed.

---

### Stopping Claude Mid-Task

If Claude does something unexpected or you want it to stop:
- Type **`stop`** in the terminal, or
- Press `Ctrl+C`

Claude will stop what it's doing immediately. Your files won't be lost.

---

### Ending Your Session

Close VS Code normally. All your work is saved in your WSL project folder. The next time you open the same project folder in VS Code and reopen it in the container, everything will be exactly as you left it.

---

### If Something Goes Wrong

| Problem | What to do |
|---|---|
| Claude does something unexpected | Type `stop` or press `Ctrl+C` |
| The container won't start | Restart Docker Desktop, then try again |
| You see an "API key" error | Contact IT — your key may need to be re-set |
| Something looks broken | Contact IT — they can reset your container without losing your project files |

**Your Windows files and your laptop are never at risk.** Claude can only read and write files inside the container's `/workspace` folder. If the container is deleted entirely, your project files in WSL remain safe.

---

## For IT Staff: Setup & Maintenance

### One-Time Machine Setup (Do This on All 8 Laptops)

#### 1. Install WSL2

Open PowerShell as Administrator and run:

```powershell
wsl --install -d Ubuntu-24.04
wsl --set-default-version 2
```

Restart the machine when prompted.

#### 2. Install Docker Desktop

- Download from https://www.docker.com/products/docker-desktop/
- During install, select **"Use WSL2 instead of Hyper-V"**
- After install: Docker Desktop → Settings → Resources → WSL Integration → enable for **Ubuntu-24.04**

#### 3. Install VS Code + Extensions

- Download from https://code.visualstudio.com/
- Install these two extensions:
  - **WSL** (`ms-vscode-remote.remote-wsl`)
  - **Dev Containers** (`ms-vscode-remote.remote-containers`)

#### 4. Set the Anthropic API Key in WSL

Open an Ubuntu terminal for the user's account and run:

```bash
echo 'export ANTHROPIC_API_KEY="sk-ant-YOUR-KEY-HERE"' >> ~/.bashrc
source ~/.bashrc
```

> **Best practice:** Provision individual API keys per user from the [Anthropic Console](https://console.anthropic.com) so you have per-user audit trails. Replace `sk-ant-YOUR-KEY-HERE` with each user's actual key.

#### 5. Keep All Project Files in WSL

All user work must live under `/home/username/` in WSL — **never** under `/mnt/c/`. Mounting Windows paths into Docker causes severe performance issues and breaks hot reload. Create starter project folders for users if needed:

```bash
mkdir -p /home/username/projects/my-first-project
```

---

### Repository Structure

```
.
├── .devcontainer/
│   ├── devcontainer.json   ← Container config (ports, extensions, env vars)
│   ├── Dockerfile          ← Container image definition
│   └── init-firewall.sh    ← Network allowlist (runs on every container start)
├── CLAUDE.md               ← Standing instructions Claude reads at startup
├── .gitignore              ← Pre-configured to block secrets and build artifacts
└── README.md               ← This file
```

Users clone this repo as a starting point for every new project. They should never need to touch the `.devcontainer/` folder.

---

### Security Architecture

| Control | Setting | Rationale |
|---|---|---|
| `--dangerously-skip-permissions` | Enabled | Safe inside the container; eliminates constant approval prompts for users |
| Outbound network | Allowlist only | Blocks data exfiltration and unintended calls to external services |
| Docker socket | Never mounted | Mounting `/var/run/docker.sock` would allow full host escape |
| Filesystem writes | `/workspace` only | Prevents Claude from modifying shell configs or system paths |
| Container user | `devuser` (non-root) | Limits blast radius of any unexpected behavior |
| API keys | Via env var only | Never hardcoded; never committed to git |

---

### Adding Domains to the Network Allowlist

The firewall script (`.devcontainer/init-firewall.sh`) blocks all outbound traffic except a short allowlist. To add an internal server (e.g., your agency's git host or an internal API):

1. Open `.devcontainer/init-firewall.sh`
2. Find the section labeled `ADD YOUR INTERNAL GIT SERVER HERE`
3. Add a line following this pattern:
   ```bash
   iptables -A OUTPUT -p tcp --dport 443 -d git.your-agency.gov -j ACCEPT
   ```
4. Commit the change to this repository
5. Users rebuild their containers: `Ctrl+Shift+P` → **"Dev Containers: Rebuild Container"**

---

### IT Reference Commands

```bash
# List all running devcontainers on a user's machine
docker ps

# Stop a specific container
docker stop <container-name>

# Remove a container entirely (safe — workspace files in WSL are not affected)
docker rm <container-name>

# View Claude's activity log inside a running container
docker logs <container-name>

# Rotate a user's API key
nano ~/.bashrc
# Update the ANTHROPIC_API_KEY line, save, then:
source ~/.bashrc
# The user will need to rebuild their container for the new key to take effect.
```

---

### How Users Start a New Project (Quick Reference for IT)

When setting up a new project for a user:

1. Clone this repo into their WSL home directory:
   ```bash
   git clone <this-repo-url> /home/username/projects/project-name
   ```
2. Open VS Code, connect to WSL, open that folder, and let it build the container once.
3. Hand off to the user with the **[Team Members](#-for-team-members-using-claude)** section above.

---

## AI Governance & Compliance (IT and AI Leads)

This sandbox is operated in alignment with the **State of Maryland's Responsible AI Policy** (DoIT, May 2025). The technical controls in this repo (network firewall, filesystem restrictions, standing instructions in `CLAUDE.md`) satisfy the policy's Security & Safety and Privacy principles. However, **technical controls alone are not sufficient** — the policy also places obligations on agencies and their designated AI Leads. This section describes those obligations.

---

### Step 1 — Appoint an Agency AI Lead

Each executive agency must designate an **AI Lead** responsible for ensuring all AI use cases comply with DoIT policies and guidance. The AI Lead coordinates with the agency's Portfolio Officer, Data Officer, and Privacy Officer. If your office has not yet appointed an AI Lead, this must happen before any AI system goes to production.

---

### Step 2 — Run Every New Use Case Through the DoIT AI Intake Process

Before any AI-powered tool or application is deployed for real use (not just internal testing), it must be submitted through the **DoIT AI Intake Process**. This applies to anything Claude builds that will be used in an ongoing, production capacity.

Contact DoIT or visit the [Maryland AI portal](https://doit.maryland.gov/policies/ai/) to initiate intake.

---

### Step 3 — Classify the Risk Level

During intake, the agency classifies the use case into one of four tiers:

| Tier | Description | What's required |
|---|---|---|
| **Unacceptable Risk** | Violates fundamental rights (e.g., unlawful surveillance, unchecked social scoring) | **Banned. Cannot be deployed.** |
| **High-Risk** | Affects health, safety, law enforcement, eligibility, financial/legal rights, or uses Level 3/4 data | Comprehensive AI Risk Assessment + ongoing monitoring required before deployment |
| **Limited Risk** | Moderate/low impact; improves internal efficiency without autonomous decisions affecting constituents | Allowed after DoIT intake; uses Level 1/2 data |
| **Minimal Risk** | Negligible risk; internal tooling with no impact on individual safety or rights | Standard DoIT intake; uses Level 1/2 data |

> **Data classification alignment:** Systems using Level 3 (Confidential) or Level 4 (Restricted) data are automatically classified as **High-Risk**. Claude's `CLAUDE.md` instructions prompt it to flag this when relevant. See the [State Data Classification Policy](https://doit.maryland.gov) for the full data classification definitions.

---

### Step 4 — Submit Live Use Cases to the AI Inventory

Once a use case is in active production use, it must be submitted to the **State AI Inventory**. DoIT aggregates submissions annually and publishes the inventory publicly. The AI Lead is responsible for keeping the agency's inventory entries up to date.

Claude is instructed to provide a plain-English summary at the end of every project (what it built, what data it handles, who it serves) to make these submissions easier.

---

### Prohibited Uses (Technical Summary)

The following are **banned** under the policy and are also blocked by Claude's standing instructions in `CLAUDE.md`:

- Real-time or covert biometric identification (facial recognition, iris scanning, etc.)
- Emotion analysis from facial expressions, body language, or speech
- Social scoring — tracking or classifying individuals by behavior or personal characteristics
- Cognitive behavioral manipulation, especially targeting vulnerable groups
- Fully automated agentic AI decisions that fall into the Unacceptable Risk category

---

### Incident Reporting

If a security incident, data exposure, or unexpected AI behavior affecting constituents occurs, follow the agency's Incident Response Plan and report to:

**Maryland Security Operations Center:** soc@Maryland.gov

---

### What This Sandbox Does and Does Not Cover

| Policy Requirement | Covered by this sandbox? | Notes |
|---|---|---|
| Network egress restrictions | Yes — technical control | `init-firewall.sh` allowlist |
| No credentials in git | Yes — technical control | `.gitignore` + `CLAUDE.md` instructions |
| Data sensitivity labeling | Yes — technical control | `CLAUDE.md` requires inline classification comments |
| Prohibited use enforcement | Yes — technical control | `CLAUDE.md` explicitly bans prohibited categories |
| Human oversight for constituent decisions | Yes — technical control | `CLAUDE.md` requires human review before outputs affect individuals |
| Filesystem isolation | Yes — technical control | Container writes limited to `/workspace` |
| Appoint an AI Lead | Agency action required | Must be done at the agency level |
| DoIT AI Intake process | Agency action required | Required before production deployment |
| AI Risk Assessment (High-Risk systems) | Agency action required | Required for Level 3/4 data systems |
| AI Inventory submission | Agency action required | Required for all live use cases |
| Incident reporting | Partial | `CLAUDE.md` reminds Claude; humans must file the actual report |

---

*Maintained by the Maryland State Innovation Team.*
