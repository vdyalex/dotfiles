#!/usr/bin/env bash

# MacOS system preferences restore script
# Run:   zsh .macos
# After: log out and back in, or reboot, for all settings to apply.

set -euo pipefail


# ══════════════════════════════════════════════════════════════════════════════
# HEADER
# ══════════════════════════════════════════════════════════════════════════════

echo ""
echo "  ┌─────────────────────────────────────────────┐"
echo "  │        MacOS system preferences setup           │"
echo "  └─────────────────────────────────────────────┘"
echo ""



# ══════════════════════════════════════════════════════════════════════════════
# PRE-FLIGHT CHECKS
# ══════════════════════════════════════════════════════════════════════════════

_preflight_warnings=()

_pass() { printf "  ✓  %s\n" "$1"; }
_fail() {
  printf "  ✗  %s\n" "$1"
  [[ -n "${2:-}" ]] && printf "       %s\n" "$2" || true
  _preflight_warnings+=("$1")
}
_warn() {
  printf "  ?  %s\n" "$1"
  [[ -n "${2:-}" ]] && printf "       %s\n" "$2" || true
}

echo ""

# SIP
if csrutil status 2>/dev/null | grep -q "enabled"; then
  _pass "SIP enabled"
else
  _fail "SIP disabled" "Re-enable via recoveryOS, then re-run."
fi

# FileVault
_fv=$(fdesetup status 2>/dev/null || echo "")
if echo "$_fv" | grep -qE "FileVault is On|Encryption in progress"; then
  _pass "FileVault active"
else
  _fail "FileVault not active" \
    "System Settings → Privacy & Security → FileVault → Turn On"
fi

# Activation Lock
_al=$(system_profiler SPHardwareDataType 2>/dev/null \
  | awk -F': ' '/Activation Lock/{print $2}' | tr -d '[:space:]')
if [[ "$_al" == "Enabled" ]]; then
  _pass "Activation Lock enabled"
else
  _fail "Activation Lock not confirmed" \
    "System Settings → General → Info → Activation Lock"
fi

echo ""

# Items that cannot be verified locally — listed for manual confirmation
_warn "iCloud Advanced Data Protection enabled" \
  "System Settings → Apple Account → iCloud → Advanced Data Protection"

_warn "Startup Security: Full Security, no external boot" \
  "System Settings → General → Startup Disk → Security Policy"

_warn "Encrypted DNS configured (DoH/DoT profile or network filter)"

_warn "Private Wi-Fi Address (Rotating) set on all networks" \
  "Wi-Fi → each network → Private Wi-Fi Address → Rotating"

_warn "AirPlay Receiver password set" \
  "System Settings → General → AirDrop & Handoff → AirPlay Receiver"

_warn "Network filter and VPN profiles installed and configured"

echo ""

if [[ ${#_preflight_warnings[@]} -gt 0 ]]; then
  printf "  %d check(s) failed. Continue anyway? [y/N] " "${#_preflight_warnings[@]}"
  read -r _r
  [[ "${_r}" =~ ^[Yy]$ ]] || { echo "  Aborted."; exit 1; }
fi

echo "  All checks passed. Applying settings..."
echo ""


# ══════════════════════════════════════════════════════════════════════════════
# START
# ══════════════════════════════════════════════════════════════════════════════

echo "Applying MacOS settings..."
echo ""

# If this script has been run before, timestamp_timeout=0 is already in effect,
# which prevents sudo from caching credentials at all. The heredoc below runs
# as a single sudo prompt — it overwrites the timeout file with a generous
# limit and enables credential caching for the duration of this run.
# The zero timeout is restored as the very last command in Sudo Hardening.
sudo tee /etc/sudoers.d/00-timeout > /dev/null << 'EOF'
Defaults timestamp_timeout=300
Defaults !tty_tickets
EOF
sudo -v


# ══════════════════════════════════════════════════════════════════════════════
# FIREWALL
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Firewall]"

# Enable the application firewall — blocks unauthorised inbound connections at the app layer
echo "    → Enabling application firewall (on)"
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on

# Stealth mode prevents the Mac from responding to ICMP probes or unsolicited
# connection attempts on closed ports, making it harder to detect on a network
echo "    → Enabling stealth mode (on)"
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on

# Block all incoming connections
# Applies to inbound traffic only — outbound DNS, VPN, and browsing are unaffected.
# Apps that need to accept inbound connections can be explicitly allowed via the firewall UI.
echo "    → Enabling block-all incoming connections (on)"
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setblockall on


# ══════════════════════════════════════════════════════════════════════════════
# ACCESSIBILITY
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Accessibility]"

# Speak Selection lets the user have any selected text read aloud —
# useful accessibility feature without a privacy cost
echo "    → Enabling Speak Selection (true)"
defaults write com.apple.speechsynthesis SpeakSelectedTextEnabled -bool true

# Samantha Enhanced provides higher-quality local speech synthesis
# compared to the default compact voice
echo "    → Setting speech synthesis voice (Samantha-premium)"
defaults write com.apple.speech.synthesis SpeechSynthesizerVoice com.apple.ttsbundle.Samantha-premium

# Spring-loading lets folders open automatically while dragging a file over them,
# enabling deep folder navigation without releasing the drag
echo "    → Enabling spring-loading for folders (true)"
defaults write NSGlobalDomain com.apple.springing.enabled -bool true

# A shorter spring-loading delay (0.5 s vs the default ~1 s) makes
# folder navigation while dragging feel more responsive
echo "    → Setting spring-loading delay (0.5)"
defaults write NSGlobalDomain com.apple.springing.delay -float 0.5

# A faster double-click threshold (0.3 s) reduces the input latency
# between the two clicks being registered as a double-click
echo "    → Setting double-click speed threshold (0.3)"
defaults write NSGlobalDomain com.apple.mouse.doubleClickThreshold -float 0.3


# ══════════════════════════════════════════════════════════════════════════════
# APPEARANCE
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Appearance]"

# Auto appearance mode switches between Light and Dark following the system
# sunrise/sunset schedule — delete removes any pinned style before enabling auto-switch
echo "    → Removing pinned appearance style"
defaults delete NSGlobalDomain AppleInterfaceStyle 2>/dev/null || true
echo "    → Enabling automatic appearance mode (sunrise/sunset)"
defaults write NSGlobalDomain AppleInterfaceStyleSwitchesAutomatically -bool true

# Dark icon and widget theme is visually consistent with the auto-appearance
# system and preferred in low-light environments
echo "    → Setting icon/widget style (Dark)"
defaults write NSGlobalDomain AppleIconThemeName -string "Dark"

# Small sidebar icons reduce visual clutter in Finder and sidebars
# without sacrificing usability
# NSTableViewDefaultSizeMode: 1=small, 2=medium, 3=large
echo "    → Setting sidebar icon size (small / 1)"
defaults write NSGlobalDomain NSTableViewDefaultSizeMode -int 1

# Jump-to-position scroll bar click is more efficient than the default
# page-scroll behaviour — clicking anywhere on the bar jumps directly there
# AppleScrollerPagingBehavior: 0=jump to next page, 1=jump to clicked position
echo "    → Setting scroll bar click behaviour (jump to position / 1)"
defaults write NSGlobalDomain AppleScrollerPagingBehavior -int 1


# ══════════════════════════════════════════════════════════════════════════════
# APPLE INTELLIGENCE & SIRI
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Apple Intelligence & Siri]"

# Disabling the always-on "Listen for" trigger (Hey Siri / Raise to Siri)
# prevents continuous microphone access, reducing passive audio exposure.
# Hiding the status menu icon and disabling the voice trigger enforce this
# at both the UI and daemon levels.
# Siri Data Sharing Opt-In Status: 1=opted in, 2=opted out
echo "    → Disabling Siri data sharing opt-in (2)"
defaults write com.apple.assistant.support "Siri Data Sharing Opt-In Status" -int 2
echo "    → Hiding Siri status menu icon (false)"
defaults write com.apple.Siri StatusMenuVisible -bool false
echo "    → Disabling Siri voice trigger (false)"
defaults write com.apple.Siri VoiceTriggerUserEnabled -bool false

# Prefer spoken responses so Siri reads answers aloud rather than only
# displaying them on screen, which is useful when triggered by keyboard shortcut
echo "    → Enabling Siri spoken responses preference (true)"
defaults write com.apple.assistant.support "Assistant Prefers Voice Response" -bool true


# ══════════════════════════════════════════════════════════════════════════════
# DESKTOP & DOCK
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Desktop & Dock]"

# A smaller Dock tile size (36 px) saves screen real estate on the primary display
echo "    → Setting Dock tile size (36)"
defaults write com.apple.dock tilesize -int 36

# Magnification gives a quick visual hint of the icon being hovered without
# permanently enlarging the Dock
echo "    → Enabling Dock magnification (true)"
defaults write com.apple.dock magnification -bool true

# Magnification target size of 80 px is large enough to read icon labels
# without taking over the screen
echo "    → Setting Dock magnification size (80)"
defaults write com.apple.dock largesize -int 80

# Scale effect is visually lighter and faster than the default Genie animation
# mineffect: "genie"=genie, "scale"=scale, "suck"=suck
echo "    → Setting window minimize animation (scale)"
defaults write com.apple.dock mineffect -string "scale"

# Fill (maximize) on title bar double-click maps the familiar MacOS zoom behaviour
# to the expected Windows-style full-screen expand
# AppleActionOnDoubleClick:
#   "Minimize"=minimize window, "Maximize"=maximize window,
#   "Fill"=fill screen, "None"=do nothing
echo "    → Setting title bar double-click action (Fill)"
defaults write NSGlobalDomain AppleActionOnDoubleClick -string "Fill"

# Minimizing to the app icon keeps the Dock clean and uncluttered
# instead of adding a separate thumbnail entry per window
echo "    → Enabling minimize-to-application-icon (true)"
defaults write com.apple.dock minimize-to-application -bool true

# Auto-hiding the Dock reclaims the full display height when not in use
echo "    → Enabling Dock auto-hide (true)"
defaults write com.apple.dock autohide -bool true

# Removing the hover delay and slide animation makes the Dock appear instantly
# when the cursor hits the screen edge — important when switching between
# full-screen apps rapidly
echo "    → Removing Dock auto-hide delay (0)"
defaults write com.apple.dock autohide-delay -float 0
echo "    → Removing Dock show/hide animation (0)"
defaults write com.apple.dock autohide-time-modifier -float 0

# Making hidden app icons translucent gives a clear visual map of what is
# running but hidden (⌘H) vs what is visible — without this, hidden apps
# look identical to open ones in the Dock
echo "    → Making hidden app icons translucent (true)"
defaults write com.apple.dock showhidden -bool true

# Dot indicators beneath open app icons let you distinguish pinned shortcuts
# from actually running applications at a glance
echo "    → Showing process indicators for open apps (true)"
defaults write com.apple.dock show-process-indicators -bool true

# Hiding recent/suggested apps prevents Apple's app suggestions from
# populating the Dock with items the user did not explicitly pin
echo "    → Disabling recent apps in Dock (false)"
defaults write com.apple.dock show-recents -bool false

# "Never" prevents MacOS from automatically switching documents to a tab view,
# preserving explicit window management
# AppleWindowTabbingMode: "manual"=only when requested, "always"=always prefer tabs, "never"=never use tabs
echo "    → Setting window tabbing mode (never)"
defaults write NSGlobalDomain AppleWindowTabbingMode -string "never"

# Requiring Option key to tile prevents windows from snapping to edges
# accidentally during ordinary drags
echo "    → Enabling Option-key edge tiling (true)"
defaults write com.apple.dock edge-tile-enabled -bool true

# Preserving Space order prevents unexpected desktop rearrangement driven
# by usage history rather than intentional layout
echo "    → Disabling auto-rearrange Spaces by recent use (false)"
defaults write com.apple.dock mru-spaces -bool false

# Grouping Mission Control windows by app makes it easier to locate
# a specific window when many apps are open simultaneously
echo "    → Enabling group-windows-by-app in Mission Control (true)"
defaults write com.apple.dock expose-group-apps -bool true

# Speeding up the Mission Control animation (0.1s vs the default ~0.25s) makes
# the spread and gather transition feel snappier for frequent use
echo "    → Setting Mission Control animation speed (0.1s)"
defaults write com.apple.dock expose-animation-duration -float 0.1

# Hover highlight in Dock stack grid view gives visual feedback on which icon
# is under the cursor — without it the grid feels unresponsive
echo "    → Enabling hover highlight in Dock stack grid view (true)"
defaults write com.apple.dock mouse-over-hilite-stack -bool true

# Spring-loading for Dock folder items — hover over a Dock folder while
# dragging a file to open it, allowing direct filing into subfolders
echo "    → Enabling spring-loading for Dock items (true)"
defaults write com.apple.dock enable-spring-load-actions-on-all-items -bool true


# ══════════════════════════════════════════════════════════════════════════════
# HOT CORNERS
# ══════════════════════════════════════════════════════════════════════════════
# Values: 0=disabled, 2=Mission Control, 3=App Exposé, 4=Desktop,
#         5=Start Screensaver, 6=Disable Screensaver, 7=Dashboard,
#         10=Put Display to Sleep, 11=Launchpad, 12=Notification Center,
#         14=Quick Note

echo "  [Hot Corners]"

# Top-left corner triggers Mission Control — provides a fast overview of all
# open windows and spaces from a natural corner gesture
echo "    → Setting top-left hot corner (Mission Control / 2)"
defaults write com.apple.dock wvous-tl-corner -int 2
defaults write com.apple.dock wvous-tl-modifier -int 0

# Top-right corner opens Notification Center — mirrors the click target
# in the menu bar for muscle-memory consistency
echo "    → Setting top-right hot corner (Notification Center / 12)"
defaults write com.apple.dock wvous-tr-corner -int 12
defaults write com.apple.dock wvous-tr-modifier -int 0

# Bottom-left corner creates a Quick Note — fast capture without switching apps
echo "    → Setting bottom-left hot corner (Quick Note / 14)"
defaults write com.apple.dock wvous-bl-corner -int 14
defaults write com.apple.dock wvous-bl-modifier -int 0

# Bottom-right corner reveals the Desktop — quick access to files or widgets
# without minimizing all windows manually
echo "    → Setting bottom-right hot corner (Desktop / 4)"
defaults write com.apple.dock wvous-br-corner -int 4
defaults write com.apple.dock wvous-br-modifier -int 0

# Single killall after all Dock writes — restarting mid-write causes the Dock
# to relaunch before all values are committed, reverting some settings
killall Dock 2>/dev/null || true


# ══════════════════════════════════════════════════════════════════════════════
# DISPLAYS
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Displays]"

# Showing resolutions as a list gives precise pixel dimensions rather than
# vague "Larger Text" / "More Space" slider labels
echo "    → Enabling resolution list view (true)"
defaults write com.apple.Displays showResolutionList -bool true

# "More Space" is the highest scaled resolution available for the built-in display.
# displayplacer detects the screen ID and mode number at runtime — the mode
# index for "More Space" is hardware-specific so it cannot be hardcoded.
# Requires: brew install displayplacer
if command -v displayplacer &>/dev/null; then
  # Find the built-in display ID (type:built-in)
  _display_id=$(displayplacer list 2>/dev/null \
    | awk '/Persistent screen id/{id=$NF} /type:built-in/{print id; exit}')
  if [[ -n "$_display_id" ]]; then
    # "More Space" is the HiDPI scaled mode with the highest pixel width.
    # displayplacer list shows each mode as e.g. "mode 3: res:2560x1600 hz:60 scaled:1 hidpi:1"
    # We filter for hidpi:1 scaled:1 modes only, then pick the one with the largest width.
    _more_space_mode=$(displayplacer list 2>/dev/null \
      | awk -v id="$_display_id" '
          /Persistent screen id/ { found = ($NF == id) }
          found && /hidpi:1/ && /scaled:1/ {
            match($0, /mode ([0-9]+):/, m)
            match($0, /res:([0-9]+)x/, r)
            if (r[1]+0 > max) { max = r[1]+0; best = m[1] }
          }
          END { print best }
        ')
    if [[ -n "$_more_space_mode" ]]; then
      echo "    → Setting display to More Space (mode ${_more_space_mode})"
      displayplacer "id:${_display_id} mode:${_more_space_mode}"
    else
      echo "    ⚠  Could not determine More Space mode — skipping display resolution"
    fi
  else
    echo "    ⚠  Built-in display not found — skipping display resolution"
  fi
else
  echo "    ⚠  displayplacer not installed — skipping display resolution"
  echo "       Install with: brew install displayplacer"
fi

# Night Shift (Sunset to Sunrise) and True Tone reduce blue light at night
# and adapt colour temperature to ambient lighting — both are stored under the
# per-user UUID key in the root-owned CoreBrightness plist
_cb_plist="/var/root/Library/Preferences/com.apple.CoreBrightness.plist"
_user_uuid=$(dscl . -read "/Users/${USER}" GeneratedUID 2>/dev/null | awk '{print $2}')
if [[ -n "$_user_uuid" ]]; then
  _cb_key="CBUser-${_user_uuid}"
  _pb() { sudo /usr/libexec/PlistBuddy -c "$1" "$_cb_plist" 2>/dev/null || true; }

  echo "    → Setting Night Shift mode (Sunset to Sunrise / 1)"
  # BlueReductionMode: 0=off, 1=sunset to sunrise (auto), 2=custom schedule
  _pb "Set  :${_cb_key}:CBBlueReductionStatus:BlueReductionMode 1"   || \
  _pb "Add  :${_cb_key}:CBBlueReductionStatus:BlueReductionMode integer 1"

  echo "    → Enabling auto Night Shift (1)"
  _pb "Set  :${_cb_key}:CBBlueReductionStatus:AutoBlueReductionEnabled 1" || \
  _pb "Add  :${_cb_key}:CBBlueReductionStatus:AutoBlueReductionEnabled integer 1"

  echo "    → Enabling True Tone (true)"
  _pb "Set  :${_cb_key}:CBColorAdaptationEnabled bool true" || \
  _pb "Add  :${_cb_key}:CBColorAdaptationEnabled bool true"

  # Unloading and reloading corebrightnessd forces it to re-read the plist
  # from disk — a simple killall is not enough as it restarts from its cache
  sudo launchctl unload /System/Library/LaunchDaemons/com.apple.corebrightnessd.plist 2>/dev/null || true
  sudo launchctl load  /System/Library/LaunchDaemons/com.apple.corebrightnessd.plist 2>/dev/null || true

  sudo killall corebrightnessd 2>/dev/null || true
fi


# ══════════════════════════════════════════════════════════════════════════════
# MENU BAR
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Menu Bar]"

# Keeping the menu bar visible in windowed mode while hiding it in full screen
# preserves quick access to menu items during normal use without consuming
# screen space in full-screen apps
echo "    → Showing menu bar in windowed mode (false)"
defaults write NSGlobalDomain _HIHideMenuBar -bool false
echo "    → Hiding menu bar in full screen (false)"
defaults write com.apple.NSGlobalDomain AppleMenuBarVisibleInFullscreen -bool false

# Disabling the background blur keeps the menu bar visually minimal
# and avoids compositing overhead
echo "    → Disabling menu bar background blur (false)"
defaults write NSGlobalDomain AppleWindowBackgroundBlurEnabled -bool false

# Analog clock reduces digital clutter in the menu bar and provides
# a quick at-a-glance time reference
echo "    → Setting clock style (analog / true)"
defaults write com.apple.menuextra.clock IsAnalog -bool true

# Hiding the date keeps the menu bar compact — the date is visible
# in Notification Center and Calendar at a glance
# ShowDate: 0=hidden, 1=always shown, 2=shown when space allows
echo "    → Hiding date in menu bar clock (0)"
defaults write com.apple.menuextra.clock ShowDate -int 0

# Hiding the day of week further reduces menu bar text width
# when the analog clock already conveys the time
echo "    → Hiding day of week in menu bar clock (false)"
defaults write com.apple.menuextra.clock ShowDayOfWeek -bool false

# Showing battery percentage provides an exact charge level at a glance
# rather than relying on the battery icon approximation
echo "    → Showing battery percentage in menu bar (true)"
defaults write com.apple.menuextra.battery ShowPercent -bool true

# Sound icon always visible ensures volume control is accessible from the menu bar
# without activating audio first
echo "    → Showing Sound icon in menu bar always (true)"
defaults write com.apple.controlcenter "NSStatusItem Visible Sound" -bool true

# Hiding Bluetooth from the menu bar reduces icon clutter; Bluetooth can be
# managed from System Settings or Control Center when needed
echo "    → Hiding Bluetooth from menu bar (false)"
defaults write com.apple.controlcenter "NSStatusItem Visible Bluetooth" -bool false

# Hiding Spotlight from the menu bar declutters the bar; Spotlight is
# accessible via ⌘Space regardless
echo "    → Hiding Spotlight from menu bar (false)"
defaults write com.apple.controlcenter "NSStatusItem Visible Spotlight" -bool false

# Hiding the Siri menu bar icon enforces the disabled-voice-trigger preference
# set in the Apple Intelligence & Siri section
echo "    → Hiding Siri from menu bar (false)"
defaults write com.apple.Siri StatusMenuVisible -bool false

# Hiding AirDrop from the menu bar reduces surface area — AirDrop is disabled
# via NetworkBrowser preferences; showing the icon would be misleading
echo "    → Hiding AirDrop from menu bar (false)"
defaults write com.apple.controlcenter "NSStatusItem Visible AirDrop" -bool false

# Hiding the Display icon keeps the bar clean; brightness is managed via
# keyboard keys and Night Shift via the configured schedule
echo "    → Hiding Display from menu bar (false)"
defaults write com.apple.controlcenter "NSStatusItem Visible Display" -bool false

# Showing the Energy Mode indicator provides quick visibility into whether
# Low Power or High Power mode is active, which affects performance and battery
echo "    → Showing Battery Energy Mode indicator in menu bar always (true)"
defaults write com.apple.controlcenter "NSStatusItem Visible BatteryShowEnergyMode" -bool true
# ShowEnergyMode: 0=hidden, 1=icon only, 2=icon and label
echo "    → Setting battery energy mode display style (2)"
defaults write com.apple.menuextra.battery ShowEnergyMode -int 2

killall SystemUIServer ControlCenter 2>/dev/null || true


# ══════════════════════════════════════════════════════════════════════════════
# AIRDROP & HANDOFF
# ══════════════════════════════════════════════════════════════════════════════

echo "  [AirDrop & Handoff]"

# AirDrop visibility set to No One prevents the device from appearing as a
# drop target to nearby devices, removing a passive file-transfer attack surface
echo "    → Disabling AirDrop visibility (No One / true)"
defaults write com.apple.NetworkBrowser DisableAirDrop -bool true

# Keeping AirPlay Receiver enabled but restricting it to the current user
# (via empty media-sharing UUID) limits who can cast to this device from the
# local network — password requirement enforces further authentication
echo "    → Enabling AirPlay Receiver for current user only (true)"
defaults write com.apple.controlcenter AirplayReceiverEnabled -bool true
echo "    → Restricting AirPlay media sharing UUID (empty)"
defaults write com.apple.amp.mediasharingd "default-media-sharing-uuid" -string ""
# AirPlay password requirement — set manually: System Settings → General → AirDrop & Handoff → Require password


# ══════════════════════════════════════════════════════════════════════════════
# GENERAL — AUTOFILL & PASSWORDS
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Autofill & Passwords]"

# Automatically deleting one-time verification codes after use reduces the
# window during which a copied or visible code could be exploited by another
# app or person with screen access
echo "    → Enabling auto-delete of verification codes after use (true)"
defaults write com.apple.messages DeleteVerificationCodesAfterUse -bool true


# ══════════════════════════════════════════════════════════════════════════════
# BATTERY
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Battery]"

# High Power mode on AC adapter maximises performance when battery life is
# not a concern and the machine is plugged in
# powermode: 0=low power, 1=automatic, 2=high power
echo "    → Setting power adapter energy mode (High Power / 2)"
sudo pmset -c powermode 2

# Low Power mode on battery extends runtime by reducing CPU and GPU performance
# when away from a charger
# powermode: 0=low power, 1=automatic, 2=high power
echo "    → Setting battery energy mode (Low Power / 1)"
sudo pmset -b powermode 1

# Disabling Wake for Network Access on battery prevents the wireless radio
# from waking the machine to handle push notifications, saving charge
echo "    → Disabling wake for network access on battery (0)"
sudo pmset -b womp 0
echo "    → Enabling wake for network access on power adapter (1)"
sudo pmset -c womp 1


# ══════════════════════════════════════════════════════════════════════════════
# DATE & TIME
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Date & Time]"

# 24-hour format avoids AM/PM ambiguity and is consistent with ISO-8601
# and common international conventions
echo "    → Enabling 24-hour time format (true)"
defaults write NSGlobalDomain AppleICUForce24HourTime -bool true


# ══════════════════════════════════════════════════════════════════════════════
# WI-FI
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Wi-Fi]"

# Detect the Wi-Fi interface name (typically en0 or en1)
_wifi_if=$(networksetup -listallhardwareports \
  | awk '/Wi-Fi|AirPort/{getline; print $NF}' | head -1)

if [[ -n "$_wifi_if" ]]; then
  # Preferred join mode keeps known networks connected without aggressively
  # hunting for open or unknown networks; disabling Auto Hotspot prevents
  # unwanted Personal Hotspot connections. Disabling RememberRecentNetworks
  # removes network history. RequireAdmin flags prevent unauthorised changes.
  # AllowLegacyNetworks=NO disables older, weaker Wi-Fi security protocols.
  echo "    → Configuring Wi-Fi preferences on ${_wifi_if}"
  sudo /usr/libexec/airportd "$_wifi_if" prefs \
    JoinMode=Preferred \
    AutoHotspotJoinMode=Never \
    RememberRecentNetworks=NO \
    RequireAdminNetworkChange=YES \
    RequireAdminPowerToggle=YES \
    AllowLegacyNetworks=NO || true
else
  echo "  ⚠  Wi-Fi interface not found — skipping Wi-Fi preferences"
fi


# ══════════════════════════════════════════════════════════════════════════════
# DNS
# ══════════════════════════════════════════════════════════════════════════════

echo "  [DNS]"

# Custom DNS resolvers (e.g. filtering or privacy-respecting providers)
# override the ISP-assigned servers that could log or manipulate queries
DNS_PRIMARY=""
DNS_SECONDARY=""
printf "    Configure custom DNS servers? [y/N] "
read -r _r
if [[ "${_r}" =~ ^[Yy]$ ]]; then
  printf "    Primary DNS server:   "
  read -r DNS_PRIMARY
  printf "    Secondary DNS server: "
  read -r DNS_SECONDARY
fi

if [[ -n "${DNS_PRIMARY}" && -n "${DNS_SECONDARY}" ]]; then
  echo "    → Setting DNS servers on Wi-Fi (${DNS_PRIMARY}, ${DNS_SECONDARY})"
  sudo networksetup -setdnsservers "Wi-Fi" "$DNS_PRIMARY" "$DNS_SECONDARY"
  echo "    → Setting DNS servers on Ethernet (${DNS_PRIMARY}, ${DNS_SECONDARY})"
  sudo networksetup -setdnsservers "Ethernet" "$DNS_PRIMARY" "$DNS_SECONDARY" 2>/dev/null || true

  # Flushing the DNS cache ensures the new resolvers are used immediately
  # without waiting for existing TTLs to expire
  echo "    → Flushing DNS cache"
  sudo dscacheutil -flushcache
  sudo killall -HUP mDNSResponder 2>/dev/null || true
fi


# ══════════════════════════════════════════════════════════════════════════════
# SPOTLIGHT
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Spotlight]"

# Disabling search query sharing prevents typed queries from being sent to
# Apple's servers to "improve" Spotlight results — queries remain local
# Search Queries Data Sharing Status: 1=opted in, 2=opted out
echo "    → Disabling Spotlight search query sharing with Apple (2)"
defaults write com.apple.assistant.support "Search Queries Data Sharing Status" -int 2
# Spotlight Data Sharing Opt-In Status: 1=opted in, 2=opted out
echo "    → Disabling Spotlight data sharing opt-in (2)"
defaults write com.apple.Spotlight "Spotlight Data Sharing Opt-In Status" -int 2

# Clipboard search in Spotlight (Sequoia+) makes recently copied text
# searchable without any data leaving the device
echo "    → Enabling Spotlight clipboard search (true)"
defaults write com.apple.Spotlight ResultsFromClipboardEnabled -bool true

# 8-hour clipboard retention balances convenience with privacy — the
# clipboard history expires within a working session
# ClipboardHistoryDuration: seconds (3600=1h, 28800=8h, 86400=24h)
echo "    → Setting Spotlight clipboard history duration (8 hours / 28800)"
defaults write com.apple.Spotlight ClipboardHistoryDuration -int 28800


# ══════════════════════════════════════════════════════════════════════════════
# SCREEN SAVER
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Screen Saver]"

# 5-minute idle timeout before the screen saver engages reduces the window
# during which an unattended unlocked screen is visible
# idleTime: seconds (0=never, 300=5min, 600=10min)
echo "    → Setting screen saver idle time (5 minutes / 300)"
defaults write com.apple.screensaver idleTime -int 300

# Requiring a password the instant the screen saver activates or the display
# sleeps closes the grace-period window — without this, a brief wake requires
# no password even with FileVault enabled
# askForPassword: 0=never, 1=require password on wake
# askForPasswordDelay: seconds before password required after wake (0=immediately)
echo "    → Requiring password immediately on screen saver / sleep wake"
defaults write com.apple.screensaver askForPassword -int 1
defaults write com.apple.screensaver askForPasswordDelay -int 0


# ══════════════════════════════════════════════════════════════════════════════
# NOTIFICATIONS
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Notifications]"

# Suppressing notifications during mirroring or screen sharing prevents
# sensitive alerts from appearing on projected or shared displays
# dnd_mirroring: 0=allow notifications, 1=enabled (legacy), 2=suppress notifications
echo "    → Disabling notifications when display is mirrored/shared (2)"
defaults write com.apple.ncprefs dnd_mirroring -int 2


# ══════════════════════════════════════════════════════════════════════════════
# SOUND
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Sound]"

# Pebble is a subtle, non-jarring alert sound appropriate for a professional
# environment compared to the louder default sounds
echo "    → Setting alert sound (Pebble)"
defaults write NSGlobalDomain com.apple.sound.beep.sound -string "/System/Library/Sounds/Pebble.aiff"

# Disabling the volume-change feedback pop removes the audible click that plays
# when adjusting volume via the keyboard, which can be disruptive in quiet settings
# com.apple.sound.beep.feedback: 0=silent, 1=play feedback sound on volume change
echo "    → Disabling volume change feedback sound (0)"
defaults write NSGlobalDomain com.apple.sound.beep.feedback -int 0


# ══════════════════════════════════════════════════════════════════════════════
# FOCUS
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Focus]"

# Disabling Focus status sharing prevents third-party apps from querying whether
# notifications are silenced — this is behavioural data that should not be exposed
echo "    → Disabling Focus status sharing (false)"
defaults write com.apple.donotdisturb focus-status-sharing-enabled -bool false


# ══════════════════════════════════════════════════════════════════════════════
# SCREEN TIME
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Screen Time]"

# Disabling Screen Time entirely avoids the continuous activity logging it
# performs — app usage, website visits, and communication data are not recorded
echo "    → Disabling Screen Time (false)"
defaults write com.apple.screentime STScreenTimeEnabled -bool false


# ══════════════════════════════════════════════════════════════════════════════
# LOCK SCREEN
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Lock Screen]"

# 2-minute display sleep on battery balances readability with battery conservation
# and reduces the window an unattended screen is visible
echo "    → Setting display sleep on battery (2 minutes)"
sudo pmset -b displaysleep 2

# 10-minute display sleep on AC adapter is a relaxed timeout appropriate when
# plugged in, while still ensuring the screen locks reasonably quickly when idle
echo "    → Setting display sleep on power adapter (10 minutes)"
sudo pmset -c displaysleep 10

# Disabling password hints removes potential clues to the password that could
# aid a shoulder-surfer or physical attacker at the login screen
# RetriesUntilHint: failed attempts before hint shown (0=never show hint)
echo "    → Disabling password hints at login screen (0)"
sudo defaults write /Library/Preferences/com.apple.loginwindow RetriesUntilHint -int 0


# ══════════════════════════════════════════════════════════════════════════════
# PRIVACY & SECURITY
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Privacy & Security]"

# Requiring administrator authentication for system-wide preferences prevents
# standard users or malicious apps from silently modifying security settings
echo "    → Requiring admin password for system preferences (authenticate-admin)"
sudo security authorizationdb write system.preferences authenticate-admin 2>/dev/null || true
echo "    → Enforcing admin requirement for preference panes (true)"
sudo defaults write /Library/Preferences/com.apple.security requireAdminForPref -bool true

# Disabling personalized Apple ads stops Apple from building an ad profile
# from app usage, purchases, and browsing activity
echo "    → Disabling personalized Apple ads (false)"
defaults write com.apple.AdLib allowApplePersonalizedAdvertising -bool false
echo "    → Enabling limit ad tracking (true)"
defaults write com.apple.AdLib forceLimitAdTracking -bool true


# ══════════════════════════════════════════════════════════════════════════════
# ANALYTICS & IMPROVEMENTS
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Analytics & Improvements]"

# Disabling Mac analytics prevents MacOS from automatically uploading
# diagnostics, usage patterns, and hardware identifiers to Apple's servers
echo "    → Disabling Mac analytics auto-submit (false)"
defaults write com.apple.DiagnosticReportingService AutoSubmit -bool false
echo "    → Disabling diagnostic info auto-submit (false)"
defaults write com.apple.SubmitDiagInfo AutoSubmit -bool false

# Disabling Improve Assistive Voice Features stops Voice Control audio
# samples from being sent to Apple for analysis and model training
echo "    → Disabling assistive voice trigger logging (false)"
defaults write com.apple.voiceservices.logging AssistantVoiceTriggerLoggingEnabled -bool false

# Disabling third-party crash data sharing prevents app crash reports
# from being forwarded to developers via Apple's relay — some may contain
# user data captured at the point of crash
echo "    → Disabling third-party diagnostic data sharing (false)"
defaults write com.apple.DiagnosticReportingService ThirdPartyDataSubmit -bool false

# Disabling iCloud analytics prevents usage metadata collected in iCloud
# from being transmitted to Apple for product improvement purposes
echo "    → Disabling iCloud analytics auto-submit (false)"
defaults write com.apple.icloud.fmfd AutoSubmit -bool false


# ══════════════════════════════════════════════════════════════════════════════
# TERMINAL
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Terminal]"

# Secure Keyboard Entry prevents other apps from using the Accessibility or
# event-tap APIs to read keystrokes while Terminal is focused — stops a
# compromised or malicious app from logging passwords, SSH keys, and commands
# typed in Terminal; a checkmark appears in Terminal > Secure Keyboard Entry
echo "    → Enabling Secure Keyboard Entry in Terminal (true)"
defaults write com.apple.terminal SecureKeyboardEntry -bool true


# ══════════════════════════════════════════════════════════════════════════════
# TOUCH ID
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Touch ID]"

# Enabling Touch ID for fast user switching allows switching between MacOS
# user accounts using biometric authentication instead of a full password prompt
echo "    → Enabling Touch ID for fast user switching (true)"
defaults write com.apple.loginwindow useTouchIDForFUS -bool true


# ══════════════════════════════════════════════════════════════════════════════
# KEYBOARD
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Keyboard]"

# Fastest key repeat rate (2) eliminates perceptible pause between repeated
# keystrokes, which is critical for efficient text editing and navigation
# KeyRepeat: 15ms units (2=30ms fastest, 6=90ms default, 300=slowest)
echo "    → Setting key repeat rate (2)"
defaults write NSGlobalDomain KeyRepeat -int 2

# Shortest initial repeat delay (15) reduces the time before a held key starts
# repeating, making hold-to-navigate significantly more responsive
# InitialKeyRepeat: 15ms units (15=225ms shortest, 25=375ms default, 120=slowest)
echo "    → Setting initial key repeat delay (15)"
defaults write NSGlobalDomain InitialKeyRepeat -int 15

# Globe key → Change Input Source (1) is the most common use of the Globe key
# for multi-language users; avoids accidental Dictation triggers
# AppleFnUsageType:
#   0=do nothing, 1=change input source, 2=show emoji picker, 3=start dictation
echo "    → Setting Globe key action (Change Input Source / 1)"
defaults write com.apple.HIToolbox AppleFnUsageType -int 1

# Full keyboard navigation (mode 3) allows Tab to cycle through every UI
# control — buttons, checkboxes, menus — essential for accessibility
# and keyboard-driven workflows
# AppleKeyboardUIMode: 0=text fields and lists only, 2=all controls (legacy), 3=all controls
echo "    → Enabling full keyboard navigation (3)"
defaults write NSGlobalDomain AppleKeyboardUIMode -int 3

# Disabling Dictation prevents audio from being streamed to Apple's speech
# recognition servers when the Dictation shortcut is triggered
# AppleDictationAutoEnable: 0=disabled, 1=enabled
echo "    → Disabling Dictation (0)"
defaults write com.apple.HIToolbox AppleDictationAutoEnable -int 0

# Disabling autocorrect preserves intentional spelling and avoids unexpected
# word substitutions, particularly when typing code, names, or abbreviations
echo "    → Disabling automatic spelling correction (false)"
defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false

# Disabling automatic capitalisation prevents MacOS from overriding casing,
# which is important in code, command-line input, and structured text
echo "    → Disabling automatic capitalisation (false)"
defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false

# Disabling period substitution stops double-space from being converted to
# ". " — a mobile typing habit that fires accidentally on a Mac keyboard
# when pausing mid-sentence
echo "    → Disabling automatic period substitution (false)"
defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false


# ══════════════════════════════════════════════════════════════════════════════
# TRACKPAD
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Trackpad]"

# Tap-to-click enables a light tap instead of a physical click, reducing
# finger fatigue and matching the expected MacBook trackpad behaviour
echo "    → Enabling tap to click for Bluetooth trackpad (true)"
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
echo "    → Enabling tap to click for built-in trackpad (true)"
defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true
# com.apple.mouse.tapBehavior: 0=tap to click disabled, 1=tap to click enabled
echo "    → Enabling tap to click system-wide (1)"
defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
defaults write NSGlobalDomain com.apple.mouse.tapBehavior -int 1

# Click pressure: 0=light, 1=medium, 2=firm
echo "    → Setting primary click pressure (medium / 1)"
defaults write com.apple.AppleMultitouchTrackpad FirstButtonThreshold -int 1
echo "    → Setting secondary click pressure (medium / 1)"
defaults write com.apple.AppleMultitouchTrackpad SecondButtonThreshold -int 1

# Tracking speed 1.5 is above the default 1.0 and provides a balance between
# precision and speed — adjust to taste within the 0.0–3.0 range
# com.apple.trackpad.scaling: 0.0=slowest, 1.0=default, 3.0=fastest
echo "    → Setting trackpad tracking speed (1.5)"
defaults write NSGlobalDomain com.apple.trackpad.scaling -float 1.5

# Three-finger swipe down for App Exposé is more ergonomic than four-finger
# swipe and mirrors the Mission Control gesture but scoped to the current app
# TrackpadFourFingerVertSwipeGesture: 0=disabled, 2=enabled
# TrackpadThreeFingerVertSwipeGesture: 0=disabled, 2=enabled
echo "    → Enabling App Exposé swipe gesture in Dock (true)"
defaults write com.apple.dock showAppExposeGestureEnabled -bool true
echo "    → Disabling four-finger vertical swipe gesture (0)"
defaults write com.apple.AppleMultitouchTrackpad TrackpadFourFingerVertSwipeGesture -int 0
echo "    → Enabling three-finger vertical swipe gesture (2)"
defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerVertSwipeGesture -int 2

killall Dock 2>/dev/null || true


# ══════════════════════════════════════════════════════════════════════════════
# NETWORK HARDENING
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Network Hardening]"

# Disabling Bonjour multicast advertisements stops the Mac from broadcasting
# its hostname and available services over mDNS, reducing LAN-level discoverability
echo "    → Disabling Bonjour multicast advertisements (true)"
sudo defaults write /Library/Preferences/com.apple.mDNSResponder NoMulticastAdvertisements -bool true

# Disabling Remote Apple Events prevents remote AppleScript execution from
# another machine on the network — a potential lateral movement vector
echo "    → Disabling Remote Apple Events (off)"
sudo systemsetup -f -setremoteappleevents off 2>/dev/null || true

# Disabling IPv6 on Wi-Fi and Ethernet removes link-local addresses from the LAN,
# reducing the attack surface from neighbour discovery and router advertisement spoofing.
# Remove these two lines if corporate VPN or services require IPv6.
echo "    → Disabling IPv6 on Wi-Fi"
sudo networksetup -setv6off "Wi-Fi" 2>/dev/null || true
echo "    → Disabling IPv6 on Ethernet"
sudo networksetup -setv6off "Ethernet" 2>/dev/null || true

# Disabling TCP keepalive on battery prevents the Mac from waking from sleep
# to service push notification keepalives, saving power.
# Kept enabled on AC (-c) to preserve iMessage/FaceTime push delivery when plugged in.
echo "    → Disabling TCP keepalive on battery (0)"
sudo pmset -b tcpkeepalive 0


# ══════════════════════════════════════════════════════════════════════════════
# SLEEP & ENCRYPTION HARDENING
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Sleep & Encryption Hardening]"

# Destroying the FileVault key on standby forces full password re-entry after
# the standbydelay window elapses — the encryption key is purged from RAM,
# not just the screen lock. Touch ID and biometric unlock continue to work
# during normal sleep; they stop only once standby is reached.
echo "    → Enabling FileVault key destruction on standby (1)"
sudo pmset -a destroyfvkeyonstandby 1

# 15-minute standby delay means biometric unlock works normally for short
# sleep periods; after 15 minutes the key is purged and the full password
# is required on next wake
echo "    → Setting standby delay (15 minutes / 900)"
sudo pmset -a standbydelay 900

# Hibernate mode 25 writes a FileVault-encrypted RAM image to disk before
# sleeping, ensuring data-at-rest protection even if the battery dies during standby
# hibernatemode:
#   0=sleep only (RAM powered, instant wake, no disk image)
#   3=safe sleep (RAM powered + encrypted disk image written, macOS default on laptops)
#   25=hibernate (RAM written to disk, RAM powered off, most secure, slower wake)
#
# Lid close behaviour with this configuration:
#   0–15 min  → normal sleep, RAM powered, Touch ID works on wake
#   15 min+   → standby triggers, FileVault key purged from RAM, full password required
#   battery dies during sleep → hibernate image protects data, resumes from disk on next boot
echo "    → Setting hibernate mode (hibernate only / 25)"
sudo pmset -a hibernatemode 25


# ══════════════════════════════════════════════════════════════════════════════
# FONTS
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Fonts]"

_fonts_dir="$HOME/Library/Fonts"
_fonts_archive="${CHEZMOI_SOURCE_DIR}/fonts.tar.gz"

if [[ ! -f "$_fonts_archive" ]]; then
  echo "    ⚠  fonts.tar.gz not found — skipping font installation"
  echo "       Expected at: ${_fonts_archive}"
else
  echo "    → Decompressing fonts.tar.gz into ~/Library/Fonts"
  mkdir -p "$_fonts_dir"
  tar -xzvf "$_fonts_archive" -C "$_fonts_dir"
  echo "    ✓  Fonts installed"
fi


# ══════════════════════════════════════════════════════════════════════════════
# SAFARI
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Safari]"

# On MacOS Tahoe and later, Safari preferences are fully sandbox-protected and
# cannot be written from outside the app — defaults write and direct plist
# access are both blocked. A configuration profile covers the manageable keys;
# the remainder must be set manually (see checklist at the end of this script).
# The profile must be in the same directory as this script.
_safari_profile="${CHEZMOI_SOURCE_DIR}/safari.mobileconfig"

if [[ -f "$_safari_profile" ]]; then
  echo "    → Installing Safari configuration profile"
  open "$_safari_profile"
  # Give the profile installer a moment to register before opening System Settings
  sleep 2
  echo "    → Opening System Settings → General → Device Management"
  open "x-apple.systempreferences:com.apple.preferences.configurationprofiles"
  echo "    ⚠  Approve the profile in System Settings → General → Device Management"
else
  echo "    ⚠  safari.mobileconfig not found — skipping Safari settings..."
  echo "       Expected at: ${_safari_profile}"
fi


# ══════════════════════════════════════════════════════════════════════════════
# SOFTWARE UPDATE
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Software Update]"

# Checking daily rather than weekly means you're never more than 24 hours
# behind on available updates without having done anything
echo "    → Enabling automatic update checks (true)"
defaults write com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true
# ScheduleFrequency: 1=daily, 7=weekly
echo "    → Setting update check frequency (daily / 1)"
defaults write com.apple.SoftwareUpdate ScheduleFrequency -int 1

# Background download means updates are ready to install immediately when
# you open System Settings — no waiting for the download to complete
# AutomaticDownload: 0=disabled, 1=enabled
echo "    → Enabling background update downloads (1)"
defaults write com.apple.SoftwareUpdate AutomaticDownload -int 1

# Security patches — XProtect malware definitions, MRT, Gatekeeper blocklists,
# certificate revocations — install automatically without prompting;
# zero-day patches are applied without requiring manual action
# CriticalUpdateInstall: 0=disabled, 1=enabled
echo "    → Enabling automatic security patch installation (1)"
defaults write com.apple.SoftwareUpdate CriticalUpdateInstall -int 1

# App Store purchased apps update automatically in the background — security
# patches for App Store apps are applied without needing to open the App Store
echo "    → Enabling automatic App Store app updates (true)"
defaults write com.apple.commerce AutoUpdate -bool true


# ══════════════════════════════════════════════════════════════════════════════
# ACTIVITY MONITOR
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Activity Monitor]"

# Showing a live CPU usage histogram in the Dock icon lets you spot runaway
# processes at a glance without switching to the app — all cores shown in
# a small real-time graph
# IconType:
#   0=application icon, 1=network usage, 2=disk activity,
#   3=memory usage, 4=CPU history, 5=CPU usage
echo "    → Setting Activity Monitor Dock icon to CPU usage graph (5)"
defaults write com.apple.ActivityMonitor IconType -int 5

# Sorting by CPU descending means the highest-consuming process is always
# at the top when you open Activity Monitor — no manual column click required
echo "    → Setting Activity Monitor sort column (CPUUsage)"
defaults write com.apple.ActivityMonitor SortColumn -string "CPUUsage"
# SortDirection: 0=descending, 1=ascending
echo "    → Setting Activity Monitor sort direction (descending / 0)"
defaults write com.apple.ActivityMonitor SortDirection -int 0

# Showing all processes rather than just user-owned ones gives a complete
# picture of system activity including background daemons
# ShowCategory:
#   0=all processes, 1=my processes, 2=system processes,
#   3=other processes, 4=windowed processes
echo "    → Showing all processes in Activity Monitor (0)"
defaults write com.apple.ActivityMonitor ShowCategory -int 0


# ══════════════════════════════════════════════════════════════════════════════
# TIME MACHINE
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Time Machine]"

# Suppressing the "Use this disk for Time Machine?" prompt that fires every
# time an external drive is connected — USB sticks, SD cards, daily-use drives
# all trigger it; this silences it without disabling Time Machine itself
echo "    → Disabling Time Machine new-disk prompt (true)"
defaults write com.apple.TimeMachine DoNotOfferNewDisksForBackup -bool true

# Local Time Machine snapshots are stored on the startup disk when the backup
# drive is not connected — disabling them frees disk space at the cost of
# losing the ability to recover files when the backup drive is absent
echo "    → Disabling local Time Machine snapshots"
hash tmutil &>/dev/null && sudo tmutil disablelocal 2>/dev/null || true


# ══════════════════════════════════════════════════════════════════════════════
# UI BEHAVIOUR
# ══════════════════════════════════════════════════════════════════════════════

echo "  [UI Behaviour]"

# Toolbar title proxy icons and path tooltips appear after a ~0.5s hover delay
# by default — setting to 0 makes them respond instantly
echo "    → Setting toolbar title rollover delay (0)"
defaults write NSGlobalDomain NSToolbarTitleViewRolloverDelay -float 0

# The animated focus ring pulses in when tabbing between UI controls —
# disabling the animation makes keyboard navigation feel snappier
echo "    → Disabling focus ring animation (false)"
defaults write NSGlobalDomain NSUseAnimatedFocusRing -bool false

# Open and save dialogs default to a compact two-panel view that hides the
# sidebar and path bar — forcing expanded mode means full Finder-style
# navigation is available immediately on every save without clicking a toggle
echo "    → Expanding save panel by default (true)"
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
echo "    → Expanding save panel by default mode 2 (true)"
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true

# Print dialogs also default to compact mode — forcing expanded mode means
# paper size, orientation, and printer-specific options are visible immediately
echo "    → Expanding print panel by default (true)"
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true
echo "    → Expanding print panel by default mode 2 (true)"
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint2 -bool true

# Setting window resize time to near-zero makes Cocoa windows snap to their
# new size instantly — the default ~0.2s spring animation adds perceptible
# latency on every maximize, double-click resize, or drag-resize
echo "    → Setting window resize animation to near-instant (0.001)"
defaults write NSGlobalDomain NSWindowResizeTime -float 0.001


# ══════════════════════════════════════════════════════════════════════════════
# ADDITIONAL PRIVACY
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Additional Privacy]"

# Handoff/Continuity is enabled intentionally for active cross-device workflow —
# these flags allow this device to advertise and receive Continuity activities
# (Handoff, Universal Clipboard, etc.) to/from trusted Apple devices
echo "    → Enabling Handoff activity advertising (true)"
defaults write com.apple.coreduetd.plist ActivityAdvertisingAllowed -bool true
echo "    → Enabling Handoff activity receiving (true)"
defaults write com.apple.coreduetd.plist ActivityReceivingAllowed -bool true

# Silencing the crash reporter dialog prevents the UI prompt from appearing
# after a crash, which could inadvertently invite "Send to Apple" clicks.
# Analytical opt-out is already set in the Analytics section.
# DialogType: "developer"=detailed dialog, "basic"=basic dialog, "none"=silent
echo "    → Setting crash reporter dialog type (none)"
defaults write com.apple.CrashReporter DialogType none

# Setting Recent Documents limit to 0 prevents "Open Recent" history from
# accumulating in app menus, removing a passive record of opened files
# NSRecentDocumentsLimit: 0=disabled, default=10
echo "    → Setting recent documents limit (0)"
defaults write NSGlobalDomain NSRecentDocumentsLimit -int 0

# Re-enforcing Gatekeeper ensures only signed and notarised apps can run.
# Some third-party installers call spctl --master-disable; this restores it.
echo "    → Re-enabling Gatekeeper (master-enable)"
sudo spctl --master-enable 2>/dev/null || true


# ══════════════════════════════════════════════════════════════════════════════
# LOGIN WINDOW HARDENING
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Login Window Hardening]"

# Showing name and password fields instead of a user list prevents enumeration
# of local accounts by anyone who reaches the login screen
echo "    → Showing name+password fields at login (true)"
sudo defaults write /Library/Preferences/com.apple.loginwindow SHOWFULLNAME -bool true

# Login window disclaimer — prompted here, right before the command that sets it.
# Displaying a custom contact banner at the login window enables recovery
# of the device if lost, and signals to a finder that the device is monitored
LOGIN_BANNER=""
printf "    Set login window banner? [y/N] "
read -r _r
if [[ "${_r}" =~ ^[Yy]$ ]]; then
  printf "    Owner name:  "
  read -r OWNER_NAME
  printf "    Owner phone: "
  read -r OWNER_PHONE
  LOGIN_BANNER="Authorized use only. This device is encrypted and location tracking is enabled. If found, contact ${OWNER_NAME} by call, SMS, iMessage, WhatsApp, or Telegram at ${OWNER_PHONE}."
fi

if [[ -n "${LOGIN_BANNER:-}" ]]; then
  echo "    → Setting login window disclaimer text"
  sudo defaults write /Library/Preferences/com.apple.loginwindow LoginwindowText -string "$LOGIN_BANNER"
else
  sudo defaults delete /Library/Preferences/com.apple.loginwindow LoginwindowText 2>/dev/null || true
fi

# Disabling console login prevents an attacker with physical access from
# bypassing the graphical login screen by typing ">console" as the username
echo "    → Disabling console login (true)"
sudo defaults write /Library/Preferences/com.apple.loginwindow DisableConsoleAccess -bool true

# Disabling login from an account whose home directory is on an external drive
# closes a vector where an attacker could boot from a crafted external disk
# and log in as a valid user whose home directory is mounted from it
echo "    → Disabling login for accounts on external drives (false)"
sudo defaults write /Library/Preferences/com.apple.loginwindow EnableExternalAccounts -bool false

# Disabling re-launch of apps from the previous session prevents apps from
# automatically opening on next login, giving a clean, known-good startup state
echo "    → Disabling app state save at logout (false)"
defaults write com.apple.loginwindow TALLogoutSavesState -bool false
echo "    → Disabling app re-launch on login (false)"
defaults write com.apple.loginwindow LoginwindowLaunchesRelaunchApps -bool false

# Allowing the user to reset their login password via Apple Account provides
# a recovery path if the password is forgotten, without requiring Recovery Mode
echo "    → Enabling password reset via Apple Account (current user)"
sudo dscl . -create "/Users/${USER}" appleIDAuthSupported 1


# ══════════════════════════════════════════════════════════════════════════════
# SERVICES HARDENING
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Services Hardening]"

# Setting the computer name controls how this Mac appears on the network,
# in Finder sidebars, and in system dialogs — a descriptive name avoids
# exposing the owner's full name embedded in the default hostname
COMPUTER_NAME=""
printf "    Set computer name? [y/N] "
read -r _r
if [[ "${_r}" =~ ^[Yy]$ ]]; then
  printf "    Computer name: "
  read -r COMPUTER_NAME
fi

if [[ -n "${COMPUTER_NAME}" ]]; then
  echo "    → Setting computer name (${COMPUTER_NAME})"
  sudo systemsetup -setcomputername "${COMPUTER_NAME}" 2>/dev/null || true
  sudo scutil --set ComputerName "${COMPUTER_NAME}"
  sudo scutil --set HostName "${COMPUTER_NAME}"
  sudo scutil --set LocalHostName "${COMPUTER_NAME//' '/-}"
fi

# Disabling Remote Login (SSH server) closes the inbound SSH port, preventing
# remote shell access even for authenticated users
echo "    → Disabling Remote Login / SSH server (off)"
sudo systemsetup -f -setremotelogin off 2>/dev/null || true
echo "    → Disabling SSH daemon via launchctl"
sudo launchctl disable system/com.openssh.sshd 2>/dev/null || true

# Auto-restarting after a complete system freeze (kernel panic, hung process)
# means returning to a login screen rather than a frozen display that requires
# a manual hard power-cycle
echo "    → Enabling auto-restart on system freeze (on)"
sudo systemsetup -setrestartfreeze on 2>/dev/null || true

# Disabling legacy network services removes attack surface from protocols
# that either have no authentication (TFTP), use plaintext transport (FTP, Telnet),
# or are unnecessary on a modern personal Mac (NFS, RPC, NetBIOS)
echo "    → Disabling TFTP (no-auth protocol)"
sudo launchctl disable system/com.apple.tftpd   2>/dev/null || true
echo "    → Disabling FTP (unencrypted protocol)"
sudo launchctl disable system/com.apple.ftpd    2>/dev/null || true
echo "    → Disabling Telnet (plaintext protocol)"
sudo launchctl disable system/com.apple.telnetd 2>/dev/null || true
echo "    → Disabling NFS (network file sharing)"
sudo launchctl disable system/com.apple.nfsd    2>/dev/null || true
echo "    → Disabling RPC portmapper"
sudo launchctl disable system/com.apple.rpcbind 2>/dev/null || true
echo "    → Disabling NetBIOS (Windows network discovery)"
sudo launchctl disable system/com.apple.netbiosd 2>/dev/null || true

# Disabling Internet Sharing prevents this Mac from acting as a NAT gateway,
# which would expose the network to any device connected via sharing
echo "    → Disabling Internet Sharing / NAT gateway (Enabled=0)"
sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.nat \
    NAT -dict Enabled -int 0

# Deactivating Content Caching stops this Mac from serving as an Apple CDN
# relay on the local network, which could expose network topology and traffic
echo "    → Deactivating Content Caching (Apple CDN relay)"
sudo AssetCacheManagerUtil deactivate 2>/dev/null || true


# ══════════════════════════════════════════════════════════════════════════════
# AUDIT AND LOGGING
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Audit & Logging]"

# Enabling the BSM security audit daemon (auditd) creates tamper-evident logs
# of authentication events, privilege escalation, and file access operations —
# essential for post-incident forensic investigation
echo "    → Enabling BSM security audit daemon (auditd)"
sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.auditd.plist 2>/dev/null || true

# Retaining system logs for 365 days provides a full year of audit history —
# the default MacOS log retention is very short (days) and insufficient for
# detecting slow or retrospective threats
# logTTL: days (default=7, recommended minimum=90)
echo "    → Setting system log retention (365 days)"
sudo defaults write /Library/Preferences/com.apple.logd logTTL -int 365

# Enabling default-level logging for the security subsystem captures
# authentication, authorisation, and cryptographic events at full detail
echo "    → Enabling detailed security subsystem logging (level:default)"
sudo log config --mode "level:default" --subsystem com.apple.security 2>/dev/null || true


# ══════════════════════════════════════════════════════════════════════════════
# FINDER
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Finder]"

# ── General ──────────────────────────────────────────────────────────────────

# Disabling all Finder window and Get Info animations makes every Finder
# interaction feel instantaneous — windows open and close without any slide
echo "    → Disabling all Finder animations (true)"
defaults write com.apple.finder DisableAllAnimations -bool true

# Showing hard disks on the Desktop gives direct access to internal volumes
# from the Desktop without opening Finder
echo "    → Showing hard disks on Desktop (true)"
defaults write com.apple.finder ShowHardDrivesOnDesktop -bool true

# Showing external disks on the Desktop makes plugged-in drives immediately
# visible and accessible without launching Finder
echo "    → Showing external disks on Desktop (true)"
defaults write com.apple.finder ShowExternalHardDrivesOnDesktop -bool true

# Showing removable media on the Desktop surfaces CDs, DVDs, and iOS devices
# as soon as they are connected
echo "    → Showing removable media on Desktop (true)"
defaults write com.apple.finder ShowRemovableMediaOnDesktop -bool true

# Opening new Finder windows to Documents provides a sensible default
# that matches where most working files are stored
# NewWindowTarget:
#   "PfCm"=Computer, "PfVo"=Volume, "PfHm"=Home, "PfDe"=Desktop,
#   "PfDo"=Documents, "PfAF"=All Files, "PfLo"=custom path
echo "    → Setting new Finder window target (Documents)"
defaults write com.apple.finder NewWindowTarget -string "PfDo"
echo "    → Setting new Finder window target path (~/Documents)"
defaults write com.apple.finder NewWindowTargetPath -string "file://${HOME}/Documents/"

# Opening folders in tabs rather than new windows keeps Finder sessions
# contained and avoids window sprawl
echo "    → Enabling open-folders-in-tabs (true)"
defaults write com.apple.finder FinderSpawnTab -bool true

# ── Advanced ─────────────────────────────────────────────────────────────────

# Showing all filename extensions is a critical security setting — it prevents
# spoofed extensions (e.g. "document.pdf.app") from appearing as safe file types
echo "    → Showing all filename extensions (true)"
defaults write NSGlobalDomain AppleShowAllExtensions -bool true

# The status bar at the bottom of every Finder window shows item count and
# available disk space — without it you must ⌘I a folder or open Disk Utility
# to know how full a volume is
echo "    → Showing Finder status bar (true)"
defaults write com.apple.finder ShowStatusBar -bool true

# The path bar shows a breadcrumb trail at the bottom of every Finder window —
# click any crumb to jump there, or drag a file onto a crumb to move it
echo "    → Showing Finder path bar (true)"
defaults write com.apple.finder ShowPathbar -bool true

# Showing the full Unix path in the Finder window title bar (e.g.
# /Users/<user>/Documents/Project) makes it easy to copy paths for Terminal use
echo "    → Showing full POSIX path in Finder title (true)"
defaults write com.apple.finder _FXShowPosixPathInTitle -bool true

# Suppressing .DS_Store on network shares stops MacOS from littering other
# OS users' shared volumes with invisible Mac-specific metadata files;
# suppressing on USB drives prevents spreading them to every machine you connect to
echo "    → Disabling .DS_Store on network volumes (true)"
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
echo "    → Disabling .DS_Store on USB volumes (true)"
defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true

# Disabling the extension change warning removes the "Are you sure?" dialog
# that fires every time a file is renamed with a different extension —
# pure friction for anyone who renames files regularly
echo "    → Disabling extension change warning (false)"
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false

# Keeping folders at the top when sorting by name groups directories above files,
# making directory navigation faster and more predictable
echo "    → Keeping folders on top when sorted by name (true)"
defaults write com.apple.finder _FXSortFoldersFirst -bool true

# Same folders-first behaviour on the Desktop ensures visual consistency
# with Finder windows when sorting Desktop items by name
echo "    → Keeping folders on top on the Desktop (true)"
defaults write com.apple.finder _FXSortFoldersFirstOnDesktop -bool true

# Searching the current folder by default scopes results to the relevant
# directory, avoiding noisy Mac-wide results when a folder-specific search
# is intended
# FXDefaultSearchScope: "SCev"=entire Mac, "SCcf"=current folder, "SCsp"=previous scope
echo "    → Setting default search scope (current folder / SCcf)"
defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"

# Column view provides Miller-column navigation — each click opens a new
# column showing the selected folder's contents, ideal for deep hierarchies
# FXPreferredViewStyle: "icnv"=icon, "Nlsv"=list, "clmv"=column, "Flwv"=gallery
echo "    → Setting default Finder view style (column / clmv)"
defaults write com.apple.finder FXPreferredViewStyle -string "clmv"

# Expanding the most useful Get Info sections (General, Open With, Sharing &
# Permissions) by default saves clicks when checking file metadata or
# changing the default app for a file type
echo "    → Expanding Get Info panes by default (General, Open With, Permissions)"
defaults write com.apple.finder FXInfoPanesExpanded -dict \
  General -bool true \
  OpenWith -bool true \
  Privileges -bool true

# Showing mounted servers on the Desktop alongside local drives makes remote
# volumes immediately visible without opening Finder
echo "    → Showing mounted servers on Desktop (true)"
defaults write com.apple.finder ShowMountedServersOnDesktop -bool true

# ── Sidebar ──────────────────────────────────────────────────────────────────

# Hiding "On My Mac" from the sidebar avoids duplicate home folder entries;
# navigation to the local home is handled via Favorites
echo "    → Hiding On My Mac section from sidebar (false)"
defaults write com.apple.finder ShowOnMyMacSection -bool false

# Showing Bonjour computers in the sidebar enables local network device
# discovery directly in Finder without additional tools
echo "    → Showing Bonjour computers in sidebar (true)"
defaults write com.apple.finder ShowBonjour -bool true

# Showing Trash in the sidebar provides a single-click shortcut to the Trash
# from any Finder window
echo "    → Showing Trash in sidebar (true)"
defaults write com.apple.finder ShowTrashInSidebar -bool true

killall Finder 2>/dev/null || true


# ══════════════════════════════════════════════════════════════════════════════
# SUDO HARDENING
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Sudo Hardening]"

# Re-validate credentials before writing sudoers files — the cache may have
# expired if the script ran longer than the default 5-minute timeout.
sudo -v

# Logging all sudo commands creates a tamper-evident audit trail of every
# privileged invocation, including the user, working directory, and command run
echo "    → Enabling sudo command logging (/var/log/sudo.log)"
echo "Defaults log_host, log_year, logfile=/var/log/sudo.log" | sudo tee /etc/sudoers.d/01-logging > /dev/null
sudo chmod 440 /etc/sudoers.d/01-logging

# Requiring a password for every sudo invocation disables the default 5-minute
# credential cache. A hijacked or left-open terminal session cannot escalate
# privileges without re-authenticating each time.
# Written last so the rest of the script is not affected by the zero timeout.
# Written to /etc/sudoers.d/ to avoid modifying the main sudoers file.
echo "    → Setting sudo timestamp timeout (0 — no credential cache)"
echo "Defaults timestamp_timeout=0" | sudo tee /etc/sudoers.d/00-timeout > /dev/null
sudo chmod 440 /etc/sudoers.d/00-timeout


# ══════════════════════════════════════════════════════════════════════════════
# COMPLETE
# ══════════════════════════════════════════════════════════════════════════════

echo ""
echo "  ✓  All settings applied."
echo ""


# ══════════════════════════════════════════════════════════════════════════════
# SAFARI — MANUAL CHECKLIST
# ══════════════════════════════════════════════════════════════════════════════

echo "  ┌──────────────────────────────────────────────────────────────────┐"
echo "  │  Safari → Settings — complete these manually after approving     │"
echo "  │  the configuration profile in System Settings → Device Management│"
echo "  └──────────────────────────────────────────────────────────────────┘"
echo ""
echo "  Tabs"
echo "    □  Always show website titles in tabs: ON"
echo ""
echo "  Advanced"
echo "    □  Use advanced tracking and fingerprinting protection: in All Browsing"
echo "    □  Allow websites to check for Apple Pay and Apple Card: OFF"
echo "    □  Allow privacy-preserving measurement of ad effectiveness: OFF"
echo ""


# ══════════════════════════════════════════════════════════════════════════════
# RESTART PROMPT
# ══════════════════════════════════════════════════════════════════════════════

printf "  Restart now for all settings to take full effect? [y/N] "
read -r _r
if [[ "${_r}" =~ ^[Yy]$ ]]; then
  echo "  Restarting..."
  sudo shutdown -r now
else
  echo "  Skipped. Log out and back in, or reboot manually, when ready."
fi
