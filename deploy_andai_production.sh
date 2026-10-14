#!/usr/bin/env bash
# ==============================================================================
# AndAI Open edX Production Automated Deployment Script
# 
# This script performs a complete, turnkey production setup of AndAI Open edX
# on a fresh Ubuntu/Debian VM using Tutor.
#
# It automatically handles:
# 1. System packages, Docker, Docker Compose, and Tutor installation
# 2. Domain and platform configuration (AndAI branding)
# 3. Pulling the custom AndAI codebase, theme, and logo assets
# 4. Running 'tutor local launch'
# 5. Applying all branding fixes (removing "Runs on Tutor" and Open edX trademarks)
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}================================================================${NC}"
echo -e "${BLUE}        AndAI Open edX Turnkey Production Deployment           ${NC}"
echo -e "${BLUE}================================================================${NC}"

# 1. Check Root / Sudo
if [ "$EUID" -eq 0 ]; then
  echo -e "${RED}[ERROR] Please run this script as a normal sudo user (e.g., azureuser), NOT as root.${NC}"
  exit 1
fi

# 2. Gather Configuration
echo -e "\n${YELLOW}[Step 1/6] Configuration Parameters${NC}"
DEFAULT_IP=$(curl -s -4 ifconfig.me || hostname -I | awk '{print $1}')
read -rp "Enter your LMS domain [Default: ${DEFAULT_IP}.nip.io]: " LMS_HOST
LMS_HOST=${LMS_HOST:-"${DEFAULT_IP}.nip.io"}

read -rp "Enter contact email for SSL/admin [Default: admin@${LMS_HOST}]: " ADMIN_EMAIL
ADMIN_EMAIL=${ADMIN_EMAIL:-"admin@${LMS_HOST}"}

PLATFORM_NAME="AndAI"
REPO_URL="https://github.com/BhargavBhalodiya04/openedx.git"
REPO_DIR="${HOME}/openedx"

echo -e "LMS Domain     : ${GREEN}${LMS_HOST}${NC}"
echo -e "Studio Domain  : ${GREEN}studio.${LMS_HOST}${NC}"
echo -e "MFE Apps Domain: ${GREEN}apps.${LMS_HOST}${NC}"
echo -e "Platform Name  : ${GREEN}${PLATFORM_NAME}${NC}"
echo -e "Admin Email    : ${GREEN}${ADMIN_EMAIL}${NC}"

# 3. Install System Dependencies & Docker
echo -e "\n${YELLOW}[Step 2/6] Installing System Packages and Docker...${NC}"
sudo apt update -y
sudo apt install -y python3 python3-pip python3-venv git curl ca-certificates

if ! command -v docker &> /dev/null; then
  echo "Installing Docker..."
  curl -fsSL https://get.docker.com -o get-docker.sh
  sudo sh get-docker.sh
  rm get-docker.sh
  sudo usermod -aG docker "$USER"
  echo -e "${GREEN}Docker installed successfully.${NC}"
fi

# Ensure docker-compose plugin is available
sudo apt install -y docker-compose-plugin || true

# 4. Set up Tutor in dedicated Virtualenv
echo -e "\n${YELLOW}[Step 3/6] Setting up Tutor...${NC}"
TUTOR_VENV="${HOME}/.tutor-venv"
if [ ! -d "${TUTOR_VENV}" ]; then
  python3 -m venv "${TUTOR_VENV}"
fi

# shellcheck source=/dev/null
source "${TUTOR_VENV}/bin/activate"
pip install --upgrade pip
pip install "tutor[full]"

# Add tutor activation to bashrc if not present
if ! grep -q "tutor-venv/bin/activate" "${HOME}/.bashrc"; then
  echo "source ${TUTOR_VENV}/bin/activate" >> "${HOME}/.bashrc"
fi

# 5. Clone/Update the AndAI Codebase & Theme
echo -e "\n${YELLOW}[Step 4/6] Setting up AndAI Codebase & Themes...${NC}"
if [ -d "${REPO_DIR}" ]; then
  echo "Updating existing repository in ${REPO_DIR}..."
  cd "${REPO_DIR}"
  git pull origin main
else
  echo "Cloning repository to ${REPO_DIR}..."
  git clone "${REPO_URL}" "${REPO_DIR}"
fi

# Copy AndAI theme into Tutor themes directory
TUTOR_ROOT=$(tutor config printroot)
mkdir -p "${TUTOR_ROOT}/env/build/openedx/themes"
cp -r "${REPO_DIR}/themes/andai-theme" "${TUTOR_ROOT}/env/build/openedx/themes/"

# Configure Tutor parameters
echo "Saving Tutor configuration..."
tutor config save \
  --set "LMS_HOST=${LMS_HOST}" \
  --set "CMS_HOST=studio.${LMS_HOST}" \
  --set "MFE_HOST=apps.${LMS_HOST}" \
  --set "PLATFORM_NAME=${PLATFORM_NAME}" \
  --set "CONTACT_EMAIL=${ADMIN_EMAIL}"

# 6. Launch Tutor
echo -e "\n${YELLOW}[Step 5/6] Launching Open edX with 'tutor local launch'...${NC}"
echo -e "${BLUE}(This builds databases, applies migrations, and sets up containers)${NC}"
tutor local launch --non-interactive

# 7. Apply Post-Launch Branding and Container Fixes
echo -e "\n${YELLOW}[Step 6/6] Applying AndAI Branding & Trademark Removals...${NC}"

# A. Copy core logos into running containers
echo "Syncing AndAI logos into LMS and CMS containers..."
docker cp "${REPO_DIR}/lms/static/images/logo.png" tutor_local-lms-1:/openedx/staticfiles/images/logo.png
docker cp "${REPO_DIR}/lms/static/images/logo-large.png" tutor_local-lms-1:/openedx/staticfiles/images/logo-large.png
docker cp "${REPO_DIR}/lms/static/images/logo.png" tutor_local-lms-1:/openedx/edx-platform/lms/static/images/logo.png
docker cp "${REPO_DIR}/lms/static/images/logo-large.png" tutor_local-lms-1:/openedx/edx-platform/lms/static/images/logo-large.png

docker cp "${REPO_DIR}/cms/static/images/studio-logo.png" tutor_local-cms-1:/openedx/staticfiles/studio/images/studio-logo.png
docker cp "${REPO_DIR}/cms/static/images/studio-logo.png" tutor_local-cms-1:/openedx/edx-platform/cms/static/images/studio-logo.png

# B. Copy clean branding API and clean Studio footer templates
echo "Syncing clean branding API and Studio footer..."
docker cp "${REPO_DIR}/lms/djangoapps/branding/api.py" tutor_local-lms-1:/openedx/edx-platform/lms/djangoapps/branding/api.py
docker cp "${REPO_DIR}/cms/templates/widgets/footer.html" tutor_local-cms-1:/openedx/edx-platform/cms/templates/widgets/footer.html
docker cp "${REPO_DIR}/cms/templates/widgets/sock.html" tutor_local-cms-1:/openedx/edx-platform/cms/templates/widgets/sock.html

# C. Permanently remove "Runs on Tutor" and Open edX trademark notices from MFEs
echo "Applying clean CSS rules to Micro-Frontends..."
docker exec tutor_local-mfe-1 sh -c '
  for css in $(find /openedx/dist -name "*.css" 2>/dev/null); do
    printf "\n.footer-about-copyright, .footer-content-secondary p, p:has(a[href*=\"edx.org\"]), div:has(> a[href*=\"edx.org\"]), a[href*=\"edx.org\"]), [class*=\"trademark\"], footer :is(p,div,span):has(img[alt*=\"Tutor\"]), footer :is(p,div,span):has(img[alt*=\"edX\"]), footer a[href*=\"tutor\"], footer a[href*=\"overhang\"], footer img[alt*=\"Tutor\"], footer img[alt*=\"Open edX\"], .footer-trademark-text, .footer-trademark { display: none !important; }\n" >> "$css"
  done
'

# D. Restart containers to apply
echo "Restarting service containers..."
docker restart tutor_local-lms-1 tutor_local-cms-1 tutor_local-mfe-1

echo -e "\n${GREEN}================================================================${NC}"
echo -e "${GREEN}   Deployment Complete! AndAI Open edX is now Live!            ${NC}"
echo -e "${GREEN}================================================================${NC}"
echo -e "LMS (Learner Portal) : ${BLUE}http://${LMS_HOST}${NC}"
echo -e "Studio (Authoring)   : ${BLUE}http://studio.${LMS_HOST}${NC}"
echo -e "Learner Dashboard    : ${BLUE}http://apps.${LMS_HOST}/learner-dashboard/${NC}"
echo -e "Course Authoring MFE : ${BLUE}http://apps.${LMS_HOST}/authoring/home${NC}"
echo -e "Django Admin Panel   : ${BLUE}http://${LMS_HOST}/admin/${NC}"
echo -e "${GREEN}================================================================${NC}"
