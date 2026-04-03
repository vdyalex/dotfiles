#!/bin/bash

# MacOS system preferences restore script
# Run:   zsh .macos
# After: log out and back in, or reboot, for all settings to apply.

# -e: exit on error
# -u: error on unset vars,
# -o pipefail: fail on pipe errors
set -euo pipefail


# ══════════════════════════════════════════════════════════════════════════════
# HEADER
# ══════════════════════════════════════════════════════════════════════════════

echo ""
echo "  ┌─────────────────────────────────────────────┐"
echo "  │        MacOS system preferences setup       │"
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
  read -r _input
  [[ "${_input}" =~ ^[Yy]$ ]] || { echo "  Aborted."; exit 1; }
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

unknown="(unknown)"


# ══════════════════════════════════════════════════════════════════════════════
# FIREWALL
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Firewall]"

# Enable the application firewall — blocks unauthorised inbound connections at the app layer
original=$(sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null | awk '/disabled/{print "off"; exit} {print "on"}' || true)
update=on
echo "    - Enabling application firewall: ${original:-$unknown} → ${update}"
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate ${update}

# Stealth mode prevents the Mac from responding to ICMP probes or unsolicited
# connection attempts on closed ports, making it harder to detect on a network
original=$(sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode 2>/dev/null | awk '{print $NF}' || true)
update=on
echo "    - Enabling stealth mode: ${original:-$unknown} → ${update}"
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode ${update}

# Block all incoming connections
# Applies to inbound traffic only — outbound DNS, VPN, and browsing are unaffected.
# Apps that need to accept inbound connections can be explicitly allowed via the firewall UI.
original=$(sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getblockall 2>/dev/null | awk '/disabled/{print "off"; exit} {print "on"}' || true)
update=on
echo "    - Enabling block-all incoming connections: ${original:-$unknown} → ${update}"
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setblockall ${update}


# ══════════════════════════════════════════════════════════════════════════════
# ACCESSIBILITY
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Accessibility]"

# Speak Selection lets the user have any selected text read aloud —
# useful accessibility feature without a privacy cost
original=$(defaults read com.apple.speechsynthesis SpeakSelectedTextEnabled 2>/dev/null || true)
update=1
echo "    - Enabling Speak Selection: ${original:-$unknown} → ${update}"
defaults write com.apple.speechsynthesis SpeakSelectedTextEnabled -int ${update}

# Samantha Enhanced provides higher-quality local speech synthesis
# compared to the default compact voice
original=$(defaults read com.apple.speech.synthesis SpeechSynthesizerVoice 2>/dev/null || true)
update=com.apple.ttsbundle.Samantha-premium
echo "    - Setting speech synthesis voice: '${original:-$unknown}' → '${update}'"
defaults write com.apple.speech.synthesis SpeechSynthesizerVoice ${update}

# Spring-loading lets folders open automatically while dragging a file over them,
# enabling deep folder navigation without releasing the drag
original=$(defaults read NSGlobalDomain com.apple.springing.enabled 2>/dev/null || true)
update=1
echo "    - Enabling spring-loading for folders: ${original:-$unknown} → ${update}"
defaults write NSGlobalDomain com.apple.springing.enabled -int ${update}

# A shorter spring-loading delay (0.5 s vs the default ~1 s) makes
# folder navigation while dragging feel more responsive
original=$(defaults read NSGlobalDomain com.apple.springing.delay 2>/dev/null || true)
update=0.5
echo "    - Setting spring-loading delay: ${original:-$unknown} → ${update}"
defaults write NSGlobalDomain com.apple.springing.delay -float ${update}

# A faster double-click threshold (0.3 s) reduces the input latency
# between the two clicks being registered as a double-click
original=$(defaults read NSGlobalDomain com.apple.mouse.doubleClickThreshold 2>/dev/null || true)
update=0.3
echo "    - Setting double-click speed threshold: ${original:-$unknown} → ${update}"
defaults write NSGlobalDomain com.apple.mouse.doubleClickThreshold -float ${update}


# ══════════════════════════════════════════════════════════════════════════════
# APPEARANCE
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Appearance]"

# Auto appearance mode switches between Light and Dark following the system
# sunrise/sunset schedule — delete removes any pinned style before enabling auto-switch
original=$(defaults read NSGlobalDomain AppleInterfaceStyle 2>/dev/null || true)
echo "    - Removing pinned appearance style: ${original:-$unknown} → (deleted)"
defaults delete NSGlobalDomain AppleInterfaceStyle 2>/dev/null || true
original=$(defaults read NSGlobalDomain AppleInterfaceStyleSwitchesAutomatically 2>/dev/null || true)
update=1
echo "    - Enabling automatic appearance mode: ${original:-$unknown} → ${update}"
defaults write NSGlobalDomain AppleInterfaceStyleSwitchesAutomatically -int ${update}

# Dark icon and widget theme is visually consistent with the auto-appearance
# system and preferred in low-light environments
original=$(defaults read NSGlobalDomain AppleIconThemeName 2>/dev/null || true)
update=Dark
echo "    - Setting icon/widget style: ${original:-$unknown} → ${update}"
defaults write NSGlobalDomain AppleIconThemeName -string "${update}"

# Small sidebar icons reduce visual clutter in Finder and sidebars
# without sacrificing usability
# NSTableViewDefaultSizeMode: 1=small, 2=medium, 3=large
original=$(defaults read NSGlobalDomain NSTableViewDefaultSizeMode 2>/dev/null || true)
update=1
echo "    - Setting sidebar icon size: ${original:-$unknown} → ${update}"
defaults write NSGlobalDomain NSTableViewDefaultSizeMode -int ${update}

# Jump-to-position scroll bar click is more efficient than the default
# page-scroll behaviour — clicking anywhere on the bar jumps directly there
# AppleScrollerPagingBehavior: 0=jump to next page, 1=jump to clicked position
original=$(defaults read NSGlobalDomain AppleScrollerPagingBehavior 2>/dev/null || true)
update=1
echo "    - Setting scroll bar click behaviour: ${original:-$unknown} → ${update}"
defaults write NSGlobalDomain AppleScrollerPagingBehavior -int ${update}


# ══════════════════════════════════════════════════════════════════════════════
# APPLE INTELLIGENCE & SIRI
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Apple Intelligence & Siri]"

# Disabling the always-on "Listen for" trigger (Hey Siri / Raise to Siri)
# prevents continuous microphone access, reducing passive audio exposure.
# Hiding the status menu icon and disabling the voice trigger enforce this
# at both the UI and daemon levels.
# Siri Data Sharing Opt-In Status: 1=opted in, 2=opted out
original=$(defaults read com.apple.assistant.support "Siri Data Sharing Opt-In Status" 2>/dev/null || true)
update=2
echo "    - Disabling Siri data sharing opt-in: ${original:-$unknown} → ${update}"
defaults write com.apple.assistant.support "Siri Data Sharing Opt-In Status" -int ${update}

original=$(defaults read com.apple.Siri StatusMenuVisible 2>/dev/null || true)
update=0
echo "    - Hiding Siri status menu icon: ${original:-$unknown} → ${update}"
defaults write com.apple.Siri StatusMenuVisible -int ${update}

original=$(defaults read com.apple.Siri VoiceTriggerUserEnabled 2>/dev/null || true)
update=0
echo "    - Disabling Siri voice trigger: ${original:-$unknown} → ${update}"
defaults write com.apple.Siri VoiceTriggerUserEnabled -int ${update}

# Prefer spoken responses so Siri reads answers aloud rather than only
# displaying them on screen, which is useful when triggered by keyboard shortcut
original=$(defaults read com.apple.assistant.support "Assistant Prefers Voice Response" 2>/dev/null || true)
update=1
echo "    - Enabling Siri spoken responses preference: ${original:-$unknown} → ${update}"
defaults write com.apple.assistant.support "Assistant Prefers Voice Response" -int ${update}


# ══════════════════════════════════════════════════════════════════════════════
# DESKTOP & DOCK
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Desktop & Dock]"

# A smaller Dock tile size (36 px) saves screen real estate on the primary display
original=$(defaults read com.apple.dock tilesize 2>/dev/null || true)
update=36
echo "    - Setting Dock tile size: ${original:-$unknown} → ${update}"
defaults write com.apple.dock tilesize -int ${update}

# Magnification gives a quick visual hint of the icon being hovered without
# permanently enlarging the Dock
original=$(defaults read com.apple.dock magnification 2>/dev/null || true)
update=1
echo "    - Enabling Dock magnification: ${original:-$unknown} → ${update}"
defaults write com.apple.dock magnification -int ${update}

# Magnification target size of 80 px is large enough to read icon labels
# without taking over the screen
original=$(defaults read com.apple.dock largesize 2>/dev/null || true)
update=80
echo "    - Setting Dock magnification size: ${original:-$unknown} → ${update}"
defaults write com.apple.dock largesize -int ${update}

# Scale effect is visually lighter and faster than the default Genie animation
# mineffect: "genie"=genie, "scale"=scale, "suck"=suck
original=$(defaults read com.apple.dock mineffect 2>/dev/null || true)
update=scale
echo "    - Setting window minimize animation: ${original:-$unknown} → ${update}"
defaults write com.apple.dock mineffect -string "${update}"

# Fill (maximize) on title bar double-click maps the familiar MacOS zoom behaviour
# to the expected Windows-style full-screen expand
# AppleActionOnDoubleClick:
#   "Minimize"=minimize window, "Maximize"=maximize window,
#   "Fill"=fill screen, "None"=do nothing
original=$(defaults read NSGlobalDomain AppleActionOnDoubleClick 2>/dev/null || true)
update=Fill
echo "    - Setting title bar double-click action: ${original:-$unknown} → ${update}"
defaults write NSGlobalDomain AppleActionOnDoubleClick -string "${update}"

# Minimizing to the app icon keeps the Dock clean and uncluttered
# instead of adding a separate thumbnail entry per window
original=$(defaults read com.apple.dock minimize-to-application 2>/dev/null || true)
update=1
echo "    - Enabling minimize-to-application-icon: ${original:-$unknown} → ${update}"
defaults write com.apple.dock minimize-to-application -int ${update}

# Auto-hiding the Dock reclaims the full display height when not in use
original=$(defaults read com.apple.dock autohide 2>/dev/null || true)
update=1
echo "    - Enabling Dock auto-hide: ${original:-$unknown} → ${update}"
defaults write com.apple.dock autohide -int ${update}

# Removing the hover delay and slide animation makes the Dock appear instantly
# when the cursor hits the screen edge — important when switching between
# full-screen apps rapidly
original=$(defaults read com.apple.dock autohide-delay 2>/dev/null || true)
update=0
echo "    - Removing Dock auto-hide delay: ${original:-$unknown} → ${update}"
defaults write com.apple.dock autohide-delay -float ${update}
original=$(defaults read com.apple.dock autohide-time-modifier 2>/dev/null || true)
update=0
echo "    - Removing Dock show/hide animation: ${original:-$unknown} → ${update}"
defaults write com.apple.dock autohide-time-modifier -float ${update}

# Making hidden app icons translucent gives a clear visual map of what is
# running but hidden (⌘H) vs what is visible — without this, hidden apps
# look identical to open ones in the Dock
original=$(defaults read com.apple.dock showhidden 2>/dev/null || true)
update=1
echo "    - Making hidden app icons translucent: ${original:-$unknown} → ${update}"
defaults write com.apple.dock showhidden -int ${update}

# Dot indicators beneath open app icons let you distinguish pinned shortcuts
# from actually running applications at a glance
original=$(defaults read com.apple.dock show-process-indicators 2>/dev/null || true)
update=1
echo "    - Showing process indicators for open apps: ${original:-$unknown} → ${update}"
defaults write com.apple.dock show-process-indicators -int ${update}

# Hiding recent/suggested apps prevents Apple's app suggestions from
# populating the Dock with items the user did not explicitly pin
original=$(defaults read com.apple.dock show-recents 2>/dev/null || true)
update=0
echo "    - Disabling recent apps in Dock: ${original:-$unknown} → ${update}"
defaults write com.apple.dock show-recents -int ${update}

# "Never" prevents MacOS from automatically switching documents to a tab view,
# preserving explicit window management
# AppleWindowTabbingMode: "manual"=only when requested, "always"=always prefer tabs, "never"=never use tabs
original=$(defaults read NSGlobalDomain AppleWindowTabbingMode 2>/dev/null || true)
update=never
echo "    - Setting window tabbing mode: ${original:-$unknown} → ${update}"
defaults write NSGlobalDomain AppleWindowTabbingMode -string "${update}"

# Requiring Option key to tile prevents windows from snapping to edges
# accidentally during ordinary drags
original=$(defaults read com.apple.dock edge-tile-enabled 2>/dev/null || true)
update=1
echo "    - Enabling Option-key edge tiling: ${original:-$unknown} → ${update}"
defaults write com.apple.dock edge-tile-enabled -int ${update}

# Preserving Space order prevents unexpected desktop rearrangement driven
# by usage history rather than intentional layout
original=$(defaults read com.apple.dock mru-spaces 2>/dev/null || true)
update=0
echo "    - Disabling auto-rearrange Spaces by recent use: ${original:-$unknown} → ${update}"
defaults write com.apple.dock mru-spaces -int ${update}

# Grouping Mission Control windows by app makes it easier to locate
# a specific window when many apps are open simultaneously
original=$(defaults read com.apple.dock expose-group-apps 2>/dev/null || true)
update=1
echo "    - Enabling group-windows-by-app in Mission Control: ${original:-$unknown} → ${update}"
defaults write com.apple.dock expose-group-apps -int ${update}

# Speeding up the Mission Control animation (0.1s vs the default ~0.25s) makes
# the spread and gather transition feel snappier for frequent use
original=$(defaults read com.apple.dock expose-animation-duration 2>/dev/null || true)
update=0.1
echo "    - Setting Mission Control animation speed: ${original:-$unknown} → ${update}"
defaults write com.apple.dock expose-animation-duration -float ${update}

# Hover highlight in Dock stack grid view gives visual feedback on which icon
# is under the cursor — without it the grid feels unresponsive
original=$(defaults read com.apple.dock mouse-over-hilite-stack 2>/dev/null || true)
update=1
echo "    - Enabling hover highlight in Dock stack grid view: ${original:-$unknown} → ${update}"
defaults write com.apple.dock mouse-over-hilite-stack -int ${update}

# Spring-loading for Dock folder items — hover over a Dock folder while
# dragging a file to open it, allowing direct filing into subfolders
original=$(defaults read com.apple.dock enable-spring-load-actions-on-all-items 2>/dev/null || true)
update=1
echo "    - Enabling spring-loading for Dock items: ${original:-$unknown} → ${update}"
defaults write com.apple.dock enable-spring-load-actions-on-all-items -int ${update}


# ══════════════════════════════════════════════════════════════════════════════
# HOT CORNERS
# ══════════════════════════════════════════════════════════════════════════════
# Values:
#   0=disabled
#   2=Mission Control
#   3=App Exposé
#   4=Desktop,
#   5=Start Screensaver
#   6=Disable Screensaver
#   7=Dashboard,
#   10=Put Display to Sleep
#   11=Launchpad
#   12=Notification Center,
#         14=Quick Note

echo "  [Hot Corners]"

# Top-left corner triggers Mission Control — provides a fast overview of all
# open windows and spaces from a natural corner gesture
original=$(defaults read com.apple.dock wvous-tl-corner 2>/dev/null || true)
update=2
echo "    - Setting top-left hot corner: ${original:-$unknown} → ${update}"
defaults write com.apple.dock wvous-tl-corner -int ${update}

original=$(defaults read com.apple.dock wvous-tl-modifier 2>/dev/null || true)
update=0
echo "    - Setting top-left hot corner (modifier): ${original:-$unknown} → ${update}"
defaults write com.apple.dock wvous-tl-modifier -int ${update}

# Top-right corner opens Notification Center — mirrors the click target
# in the menu bar for muscle-memory consistency
original=$(defaults read com.apple.dock wvous-tr-corner 2>/dev/null || true)
update=12
echo "    - Setting top-right hot corner: ${original:-$unknown} → ${update}"
defaults write com.apple.dock wvous-tr-corner -int ${update}

original=$(defaults read com.apple.dock wvous-tr-modifier 2>/dev/null || true)
update=0
echo "    - Setting top-right hot corner (modifier): ${original:-$unknown} → ${update}"
defaults write com.apple.dock wvous-tr-modifier -int ${update}

# Bottom-left corner creates a Quick Note — fast capture without switching apps
original=$(defaults read com.apple.dock wvous-bl-corner 2>/dev/null || true)
update=14
echo "    - Setting bottom-left hot corner: ${original:-$unknown} → ${update}"
defaults write com.apple.dock wvous-bl-corner -int ${update}

original=$(defaults read com.apple.dock wvous-bl-modifier 2>/dev/null || true)
update=0
echo "    - Setting bottom-left hot corner (modifier): ${original:-$unknown} → ${update}"
defaults write com.apple.dock wvous-bl-modifier -int ${update}

# Bottom-right corner reveals the Desktop — quick access to files or widgets
# without minimizing all windows manually
original=$(defaults read com.apple.dock wvous-br-corner 2>/dev/null || true)
update=4
echo "    - Setting bottom-right hot corner: ${original:-$unknown} → ${update}"
defaults write com.apple.dock wvous-br-corner -int ${update}

original=$(defaults read com.apple.dock wvous-br-modifier 2>/dev/null || true)
update=0
echo "    - Setting bottom-right hot corner (modifier): ${original:-$unknown} → ${update}"
defaults write com.apple.dock wvous-br-modifier -int ${update}

# Single killall after all Dock writes — restarting mid-write causes the Dock
# to relaunch before all values are committed, reverting some settings
killall Dock 2>/dev/null || true


# ══════════════════════════════════════════════════════════════════════════════
# DISPLAYS
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Displays]"

# Showing resolutions as a list gives precise pixel dimensions rather than
# vague "Larger Text" / "More Space" slider labels
original=$(defaults read com.apple.Displays showResolutionList 2>/dev/null || true)
update=1
echo "    - Enabling resolution list view: ${original:-$unknown} → ${update}"
defaults write com.apple.Displays showResolutionList -int ${update}

# "More Space" is the highest scaled resolution available for the built-in display.
# displayplacer detects the screen ID and mode number at runtime — the mode
# index for "More Space" is hardware-specific so it cannot be hardcoded.
# Requires: brew install displayplacer
if command -v displayplacer &>/dev/null; then
  # Find the built-in display ID (type:built-in)
  display_id=$(displayplacer list 2>/dev/null \
    | awk '/Persistent screen id/{id=$NF} /type:built-in/{print id; exit}')
  if [[ -n "$display_id" ]]; then
    # "More Space" is the HiDPI scaled mode with the highest pixel width.
    # displayplacer list shows each mode as e.g. "mode 3: res:2560x1600 hz:60 scaled:1 hidpi:1"
    # We filter for hidpi:1 scaled:1 modes only, then pick the one with the largest width.
    display_more_space_mode=$(displayplacer list 2>/dev/null \
      | awk -v id="$display_id" '
          /Persistent screen id/ { found = ($NF == id) }
          found && /hidpi:1/ && /scaled:1/ {
            match($0, /mode ([0-9]+):/, m)
            match($0, /res:([0-9]+)x/, r)
            if (r[1]+0 > max) { max = r[1]+0; best = m[1] }
          }
          END { print best }
        ')
    if [[ -n "$display_more_space_mode" ]]; then
      original=$(displayplacer list | awk '/mode:/{m=$0} END{print m}' 2>/dev/null || true)
      update=$display_more_space_mode
      echo "    - Setting display to More Space: ${original:-$unknown} → ${update}"
      displayplacer "id:${display_id} mode:${update}"
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
core_brightness_plist="/var/root/Library/Preferences/com.apple.CoreBrightness.plist"
user_uuid=$(dscl . -read "/Users/${USER}" GeneratedUID 2>/dev/null | awk '{print $2}')
if [[ -n "$user_uuid" ]]; then
  core_brightness_key="CBUser-${user_uuid}"
  _plist_buddy() { sudo /usr/libexec/PlistBuddy -c "$1" "$core_brightness_plist" 2>/dev/null || true; }

  # BlueReductionMode: 0=off, 1=sunset to sunrise (auto), 2=custom schedule
  original=$(sudo /usr/libexec/PlistBuddy -c "Print :${core_brightness_key}:CBBlueReductionStatus:BlueReductionMode" "$core_brightness_plist" 2>/dev/null || true)
  update=1
  echo "    - Setting Night Shift mode: ${original:-$unknown} → ${update}"
  _plist_buddy "Set  :${core_brightness_key}:CBBlueReductionStatus:BlueReductionMode ${update}"   || \
  _plist_buddy "Add  :${core_brightness_key}:CBBlueReductionStatus:BlueReductionMode integer ${update}"

  original=$(sudo /usr/libexec/PlistBuddy -c "Print :${core_brightness_key}:CBBlueReductionStatus:AutoBlueReductionEnabled" "$core_brightness_plist" 2>/dev/null || true)
  update=1
  echo "    - Enabling auto Night Shift: ${original:-$unknown} → ${update}"
  _plist_buddy "Set  :${core_brightness_key}:CBBlueReductionStatus:AutoBlueReductionEnabled ${update}" || \
  _plist_buddy "Add  :${core_brightness_key}:CBBlueReductionStatus:AutoBlueReductionEnabled integer ${update}"

  original=$(sudo /usr/libexec/PlistBuddy -c "Print :${core_brightness_key}:CBColorAdaptationEnabled" "$core_brightness_plist" 2>/dev/null || true)
  update=1
  echo "    - Enabling True Tone: ${original:-$unknown} → ${update}"
  _plist_buddy "Set  :${core_brightness_key}:CBColorAdaptationEnabled ${update}" || \
  _plist_buddy "Add  :${core_brightness_key}:CBColorAdaptationEnabled integer ${update}"

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
original=$(defaults read NSGlobalDomain _HIHideMenuBar 2>/dev/null || true)
update=0
echo "    - Showing menu bar in windowed mode: ${original:-$unknown} → ${update}"
defaults write NSGlobalDomain _HIHideMenuBar -int ${update}

original=$(defaults read com.apple.NSGlobalDomain AppleMenuBarVisibleInFullscreen 2>/dev/null || true)
update=0
echo "    - Hiding menu bar in full screen: ${original:-$unknown} → ${update}"
defaults write com.apple.NSGlobalDomain AppleMenuBarVisibleInFullscreen -int ${update}

# Disabling the background blur keeps the menu bar visually minimal
# and avoids compositing overhead
original=$(defaults read NSGlobalDomain AppleWindowBackgroundBlurEnabled 2>/dev/null || true)
update=0
echo "    - Disabling menu bar background blur: ${original:-$unknown} → ${update}"
defaults write NSGlobalDomain AppleWindowBackgroundBlurEnabled -int ${update}

# Analog clock reduces digital clutter in the menu bar and provides
# a quick at-a-glance time reference
original=$(defaults read com.apple.menuextra.clock IsAnalog 2>/dev/null || true)
update=1
echo "    - Setting clock style: ${original:-$unknown} → ${update}"
defaults write com.apple.menuextra.clock IsAnalog -int ${update}

# Hiding the date keeps the menu bar compact — the date is visible
# in Notification Center and Calendar at a glance
# ShowDate: 0=hidden, 1=always shown, 2=shown when space allows
original=$(defaults read com.apple.menuextra.clock ShowDate 2>/dev/null || true)
update=0
echo "    - Hiding date in menu bar clock: ${original:-$unknown} → ${update}"
defaults write com.apple.menuextra.clock ShowDate -int ${update}

# Hiding the day of week further reduces menu bar text width
# when the analog clock already conveys the time
original=$(defaults read com.apple.menuextra.clock ShowDayOfWeek 2>/dev/null || true)
update=0
echo "    - Hiding day of week in menu bar clock: ${original:-$unknown} → ${update}"
defaults write com.apple.menuextra.clock ShowDayOfWeek -int ${update}

# Showing battery percentage provides an exact charge level at a glance
# rather than relying on the battery icon approximation
original=$(defaults read com.apple.menuextra.battery ShowPercent 2>/dev/null || true)
update=1
echo "    - Showing battery percentage in menu bar: ${original:-$unknown} → ${update}"
defaults write com.apple.menuextra.battery ShowPercent -int ${update}

# Sound icon always visible ensures volume control is accessible from the menu bar
# without activating audio first
original=$(defaults read com.apple.controlcenter "NSStatusItem Visible Sound" 2>/dev/null || true)
update=1
echo "    - Showing Sound icon in menu bar always: ${original:-$unknown} → ${update}"
defaults write com.apple.controlcenter "NSStatusItem Visible Sound" -int ${update}

# Hiding Bluetooth from the menu bar reduces icon clutter; Bluetooth can be
# managed from System Settings or Control Center when needed
original=$(defaults read com.apple.controlcenter "NSStatusItem Visible Bluetooth" 2>/dev/null || true)
update=0
echo "    - Hiding Bluetooth from menu bar: ${original:-$unknown} → ${update}"
defaults write com.apple.controlcenter "NSStatusItem Visible Bluetooth" -int ${update}

# Hiding Spotlight from the menu bar declutters the bar; Spotlight is
# accessible via ⌘Space regardless
original=$(defaults read com.apple.controlcenter "NSStatusItem Visible Spotlight" 2>/dev/null || true)
update=0
echo "    - Hiding Spotlight from menu bar: ${original:-$unknown} → ${update}"
defaults write com.apple.controlcenter "NSStatusItem Visible Spotlight" -int ${update}

# Hiding the Siri menu bar icon enforces the disabled-voice-trigger preference
# set in the Apple Intelligence & Siri section
original=$(defaults read com.apple.Siri StatusMenuVisible 2>/dev/null || true)
update=0
echo "    - Hiding Siri from menu bar: ${original:-$unknown} → ${update}"
defaults write com.apple.Siri StatusMenuVisible -int ${update}

# Hiding AirDrop from the menu bar reduces surface area — AirDrop is disabled
# via NetworkBrowser preferences; showing the icon would be misleading
original=$(defaults read com.apple.controlcenter "NSStatusItem Visible AirDrop" 2>/dev/null || true)
update=0
echo "    - Hiding AirDrop from menu bar: ${original:-$unknown} → ${update}"
defaults write com.apple.controlcenter "NSStatusItem Visible AirDrop" -int ${update}

# Hiding the Display icon keeps the bar clean; brightness is managed via
# keyboard keys and Night Shift via the configured schedule
original=$(defaults read com.apple.controlcenter "NSStatusItem Visible Display" 2>/dev/null || true)
update=0
echo "    - Hiding Display from menu bar: ${original:-$unknown} → ${update}"
defaults write com.apple.controlcenter "NSStatusItem Visible Display" -int ${update}

# Showing the Energy Mode indicator provides quick visibility into whether
# Low Power or High Power mode is active, which affects performance and battery
original=$(defaults read com.apple.controlcenter "NSStatusItem Visible BatteryShowEnergyMode" 2>/dev/null || true)
update=1
echo "    - Showing Battery Energy Mode indicator in menu bar always: ${original:-$unknown} → ${update}"
defaults write com.apple.controlcenter "NSStatusItem Visible BatteryShowEnergyMode" -int ${update}
# ShowEnergyMode: 0=hidden, 1=icon only, 2=icon and label
original=$(defaults read com.apple.menuextra.battery ShowEnergyMode 2>/dev/null || true)
update=2
echo "    - Setting battery energy mode display style: ${original:-$unknown} → ${update}"
defaults write com.apple.menuextra.battery ShowEnergyMode -int ${update}

killall SystemUIServer ControlCenter 2>/dev/null || true


# ══════════════════════════════════════════════════════════════════════════════
# AIRDROP & HANDOFF
# ══════════════════════════════════════════════════════════════════════════════

echo "  [AirDrop & Handoff]"

# AirDrop visibility set to No One prevents the device from appearing as a
# drop target to nearby devices, removing a passive file-transfer attack surface
original=$(defaults read com.apple.NetworkBrowser DisableAirDrop 2>/dev/null || true)
update=1
echo "    - Disabling AirDrop visibility: ${original:-$unknown} → ${update}"
defaults write com.apple.NetworkBrowser DisableAirDrop -int ${update}

# Keeping AirPlay Receiver enabled but restricting it to the current user
# (via empty media-sharing UUID) limits who can cast to this device from the
# local network — password requirement enforces further authentication
original=$(defaults read com.apple.controlcenter AirplayReceiverEnabled 2>/dev/null || true)
update=1
echo "    - Enabling AirPlay Receiver for current user only: ${original:-$unknown} → ${update}"
defaults write com.apple.controlcenter AirplayReceiverEnabled -int ${update}

original=$(defaults read com.apple.amp.mediasharingd default-media-sharing-uuid 2>/dev/null || true)
echo "    - Restricting AirPlay media sharing UUID: ${original:-$unknown} → (empty)"
defaults write com.apple.amp.mediasharingd "default-media-sharing-uuid" -string ""
# AirPlay password requirement — set manually: System Settings → General → AirDrop & Handoff → Require password


# ══════════════════════════════════════════════════════════════════════════════
# GENERAL — AUTOFILL & PASSWORDS
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Autofill & Passwords]"

# Automatically deleting one-time verification codes after use reduces the
# window during which a copied or visible code could be exploited by another
# app or person with screen access
original=$(defaults read com.apple.messages DeleteVerificationCodesAfterUse 2>/dev/null || true)
update=1
echo "    - Enabling auto-delete of verification codes after use: ${original:-$unknown} → ${update}"
defaults write com.apple.messages DeleteVerificationCodesAfterUse -int ${update}


# ══════════════════════════════════════════════════════════════════════════════
# BATTERY
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Battery]"

# High Power mode on AC adapter maximises performance when battery life is
# not a concern and the machine is plugged in
# powermode: 0=low power, 1=automatic, 2=high power
original=$(pmset -g custom 2>/dev/null | awk '/^AC Power:/{f=1;next} /^[A-Z]/{f=0} f&&/powermode/{print $2;exit}' || true)
update=2
echo "    - Setting power adapter energy mode: ${original:-$unknown} → ${update}"
sudo pmset -c powermode ${update} &>/dev/null || true

# Low Power mode on battery extends runtime by reducing CPU and GPU performance
# when away from a charger
# powermode: 0=low power, 1=automatic, 2=high power
original=$(pmset -g custom 2>/dev/null | awk '/^Battery Power:/{f=1;next} /^[A-Z]/{f=0} f&&/powermode/{print $2;exit}' || true)
update=1
echo "    - Setting battery energy mode: ${original:-$unknown} → ${update}"
sudo pmset -b powermode ${update} &>/dev/null || true

# Disabling Wake for Network Access on battery prevents the wireless radio
# from waking the machine to handle push notifications, saving charge
original=$(pmset -g custom 2>/dev/null | awk '/^Battery Power:/{f=1;next} /^[A-Z]/{f=0} f&&/womp/{print $2;exit}' || true)
update=0
echo "    - Disabling wake for network access on battery: ${original:-$unknown} → ${update}"
sudo pmset -b womp ${update} &>/dev/null || true

original=$(pmset -g custom 2>/dev/null | awk '/^AC Power:/{f=1;next} /^[A-Z]/{f=0} f&&/womp/{print $2;exit}' || true)
update=1
echo "    - Enabling wake for network access on power adapter: ${original:-$unknown} → ${update}"
sudo pmset -c womp ${update} &>/dev/null || true


# ══════════════════════════════════════════════════════════════════════════════
# DATE & TIME
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Date & Time]"

# 24-hour format avoids AM/PM ambiguity and is consistent with ISO-8601
# and common international conventions
original=$(defaults read NSGlobalDomain AppleICUForce24HourTime 2>/dev/null || true)
update=1
echo "    - Enabling 24-hour time format: ${original:-$unknown} → ${update}"
defaults write NSGlobalDomain AppleICUForce24HourTime -int ${update}


# ══════════════════════════════════════════════════════════════════════════════
# WI-FI
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Wi-Fi]"

# Detect the Wi-Fi interface name (typically en0 or en1)
wifi_status=$(networksetup -listallhardwareports | awk '/Wi-Fi|AirPort/{getline; print $NF}' | head -1)

if [[ -n "$wifi_status" ]]; then
  # Preferred join mode keeps known networks connected without aggressively
  # hunting for open or unknown networks; disabling Auto Hotspot prevents
  # unwanted Personal Hotspot connections. Disabling RememberRecentNetworks
  # removes network history. RequireAdmin flags prevent unauthorised changes.
  # AllowLegacyNetworks=NO disables older, weaker Wi-Fi security protocols.
  echo "    - Configuring Wi-Fi preferences on ${wifi_status}"
  sudo /usr/libexec/airportd "$wifi_status" prefs \
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
DNS_PRIMARY="1.1.1.1"
DNS_SECONDARY="1.0.0.1"

original=$(networksetup -getdnsservers "Wi-Fi" 2>/dev/null || true)
update=($DNS_PRIMARY $DNS_SECONDARY)
echo "    - Setting DNS servers on Wi-Fi: ${original:-$unknown} → ${update}"
sudo networksetup -setdnsservers "Wi-Fi" ${update} 2>/dev/null || true

if networksetup -listallnetworkservices 2>/dev/null | grep -q '^Ethernet$'; then
  original=$(networksetup -getdnsservers "Ethernet" 2>/dev/null || true)
  update=($DNS_PRIMARY $DNS_SECONDARY)
  echo "    - Setting DNS servers on Ethernet: ${original:-$unknown} → ${update}"
  sudo networksetup -setdnsservers "Ethernet" ${update} 2>/dev/null || true
fi

# Flushing the DNS cache ensures the new resolvers are used immediately
# without waiting for existing TTLs to expire
echo "    - Flushing DNS cache"
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder 2>/dev/null || true


# ══════════════════════════════════════════════════════════════════════════════
# SPOTLIGHT
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Spotlight]"

# Disabling search query sharing prevents typed queries from being sent to
# Apple's servers to "improve" Spotlight results — queries remain local
# Search Queries Data Sharing Status: 1=opted in, 2=opted out
original=$(defaults read com.apple.assistant.support "Search Queries Data Sharing Status" 2>/dev/null || true)
update=2
echo "    - Disabling Spotlight search query sharing with Apple: ${original:-$unknown} → ${update}"
defaults write com.apple.assistant.support "Search Queries Data Sharing Status" -int ${update}

# Spotlight Data Sharing Opt-In Status: 1=opted in, 2=opted out
original=$(defaults read com.apple.Spotlight "Spotlight Data Sharing Opt-In Status" 2>/dev/null || true)
update=2
echo "    - Disabling Spotlight data sharing opt-in: ${original:-$unknown} → ${update}"
defaults write com.apple.Spotlight "Spotlight Data Sharing Opt-In Status" -int ${update}

# Clipboard search in Spotlight (Sequoia+) makes recently copied text
# searchable without any data leaving the device
original=$(defaults read com.apple.Spotlight ResultsFromClipboardEnabled 2>/dev/null || true)
update=1
echo "    - Enabling Spotlight clipboard search: ${original:-$unknown} → ${update}"
defaults write com.apple.Spotlight ResultsFromClipboardEnabled -int ${update}

# 8-hour clipboard retention balances convenience with privacy — the
# clipboard history expires within a working session
# ClipboardHistoryDuration: seconds (3600=1h, 28800=8h, 86400=24h)
original=$(defaults read com.apple.Spotlight ClipboardHistoryDuration 2>/dev/null || true)
update=28800
echo "    - Setting Spotlight clipboard history duration: ${original:-$unknown} → ${update}"
defaults write com.apple.Spotlight ClipboardHistoryDuration -int ${update}


# ══════════════════════════════════════════════════════════════════════════════
# SCREEN SAVER
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Screen Saver]"

# 5-minute idle timeout before the screen saver engages reduces the window
# during which an unattended unlocked screen is visible
# idleTime: seconds (0=never, 300=5min, 600=10min)
original=$(defaults read com.apple.screensaver idleTime 2>/dev/null || true)
update=300
echo "    - Setting screen saver idle time: ${original:-$unknown} → ${update}"
defaults write com.apple.screensaver idleTime -int ${update}

# Requiring a password the instant the screen saver activates or the display
# sleeps closes the grace-period window — without this, a brief wake requires
# no password even with FileVault enabled
# askForPassword: 0=never, 1=require password on wake
# askForPasswordDelay: seconds before password required after wake (0=immediately)
original=$(defaults read com.apple.screensaver askForPassword 2>/dev/null || true)
update=1
echo "    - Requiring password immediately on screen saver: ${original:-$unknown} → ${update}"
defaults write com.apple.screensaver askForPassword -int ${update}

original=$(defaults read com.apple.screensaver askForPasswordDelay 2>/dev/null || true)
update=0
echo "    - Requiring password immediately on sleep wake: ${original:-$unknown} → ${update}"
defaults write com.apple.screensaver askForPasswordDelay -int ${update}


# ══════════════════════════════════════════════════════════════════════════════
# NOTIFICATIONS
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Notifications]"

# Suppressing notifications during mirroring or screen sharing prevents
# sensitive alerts from appearing on projected or shared displays
# dnd_mirroring: 0=allow notifications, 1=enabled (legacy), 2=suppress notifications
original=$(defaults read com.apple.ncprefs dnd_mirroring 2>/dev/null || true)
update=2
echo "    - Disabling notifications when display is mirrored/shared: ${original:-$unknown} → ${update}"
defaults write com.apple.ncprefs dnd_mirroring -int ${update}


# ══════════════════════════════════════════════════════════════════════════════
# SOUND
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Sound]"

# Pebble is a subtle, non-jarring alert sound appropriate for a professional
# environment compared to the louder default sounds
original=$(defaults read NSGlobalDomain com.apple.sound.beep.sound 2>/dev/null || true)
update='/System/Library/Sounds/Pebble.aiff'
echo "    - Setting alert sound: '${original:-$unknown}' → '${update}'"
defaults write NSGlobalDomain com.apple.sound.beep.sound -string "${update}"

# Disabling the volume-change feedback pop removes the audible click that plays
# when adjusting volume via the keyboard, which can be disruptive in quiet settings
# com.apple.sound.beep.feedback: 0=silent, 1=play feedback sound on volume change
original=$(defaults read NSGlobalDomain com.apple.sound.beep.feedback 2>/dev/null || true)
update=0
echo "    - Disabling volume change feedback sound: ${original:-$unknown} → ${update}"
defaults write NSGlobalDomain com.apple.sound.beep.feedback -int ${update}


# ══════════════════════════════════════════════════════════════════════════════
# FOCUS
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Focus]"

# Disabling Focus status sharing prevents third-party apps from querying whether
# notifications are silenced — this is behavioural data that should not be exposed
original=$(defaults read com.apple.donotdisturb focus-status-sharing-enabled 2>/dev/null || true)
update=0
echo "    - Disabling Focus status sharing: ${original:-$unknown} → ${update}"
defaults write com.apple.donotdisturb focus-status-sharing-enabled -int ${update}


# ══════════════════════════════════════════════════════════════════════════════
# SCREEN TIME
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Screen Time]"

# Disabling Screen Time entirely avoids the continuous activity logging it
# performs — app usage, website visits, and communication data are not recorded
original=$(defaults read com.apple.screentime STScreenTimeEnabled 2>/dev/null || true)
update=0
echo "    - Disabling Screen Time: ${original:-$unknown} → ${update}"
defaults write com.apple.screentime STScreenTimeEnabled -int ${update}


# ══════════════════════════════════════════════════════════════════════════════
# LOCK SCREEN
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Lock Screen]"

# 2-minute display sleep on battery balances readability with battery conservation
# and reduces the window an unattended screen is visible
original=$(pmset -g custom 2>/dev/null | awk '/^Battery Power:/{f=1;next} /^[A-Z]/{f=0} f&&/displaysleep/{print $2;exit}' || true)
update=2
echo "    - Setting display sleep on battery: ${original:-$unknown} → ${update}"
sudo pmset -b displaysleep ${update} &>/dev/null || true

# 10-minute display sleep on AC adapter is a relaxed timeout appropriate when
# plugged in, while still ensuring the screen locks reasonably quickly when idle
original=$(pmset -g custom 2>/dev/null | awk '/^AC Power:/{f=1;next} /^[A-Z]/{f=0} f&&/displaysleep/{print $2;exit}' || true)
update=10
echo "    - Setting display sleep on power adapter: ${original:-$unknown} → ${update}"
sudo pmset -c displaysleep ${update} &>/dev/null || true

# Disabling password hints removes potential clues to the password that could
# aid a shoulder-surfer or physical attacker at the login screen
# RetriesUntilHint: failed attempts before hint shown (0=never show hint)
original=$(sudo defaults read /Library/Preferences/com.apple.loginwindow RetriesUntilHint 2>/dev/null || true)
update=0
echo "    - Disabling password hints at login screen: ${original:-$unknown} → ${update}"
sudo defaults write /Library/Preferences/com.apple.loginwindow RetriesUntilHint -int ${update}


# ══════════════════════════════════════════════════════════════════════════════
# PRIVACY & SECURITY
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Privacy & Security]"

# Requiring administrator authentication for system-wide preferences prevents
# standard users or malicious apps from silently modifying security settings
original=$(sudo security authorizationdb read system.preferences 2>/dev/null | awk '/<key>rule<\/key>/{found=1} found && /<string>/{gsub(/.*<string>|<\/string>.*/,""); print; exit}' || true)
update=authenticate-admin
echo "    - Requiring admin password for system preferences: ${original:-$unknown} → ${update}"
sudo security authorizationdb write system.preferences ${update} 2>/dev/null || true

original=$(sudo defaults read /Library/Preferences/com.apple.security requireAdminForPref 2>/dev/null || true)
update=1
echo "    - Enforcing admin requirement for preference panes: ${original:-$unknown} → ${update}"
sudo defaults write /Library/Preferences/com.apple.security requireAdminForPref -int ${update}

# Disabling personalized Apple ads stops Apple from building an ad profile
# from app usage, purchases, and browsing activity
original=$(defaults read com.apple.AdLib allowApplePersonalizedAdvertising 2>/dev/null || true)
update=0
echo "    - Disabling personalized Apple ads: ${original:-$unknown} → ${update}"
defaults write com.apple.AdLib allowApplePersonalizedAdvertising -int ${update}

original=$(defaults read com.apple.AdLib forceLimitAdTracking 2>/dev/null || true)
update=1
echo "    - Enabling limit ad tracking: ${original:-$unknown} → ${update}"
defaults write com.apple.AdLib forceLimitAdTracking -int ${update}


# ══════════════════════════════════════════════════════════════════════════════
# ANALYTICS & IMPROVEMENTS
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Analytics & Improvements]"

# Disabling Mac analytics prevents MacOS from automatically uploading
# diagnostics, usage patterns, and hardware identifiers to Apple's servers
original=$(defaults read com.apple.DiagnosticReportingService AutoSubmit 2>/dev/null || true)
update=0
echo "    - Disabling Mac analytics auto-submit: ${original:-$unknown} → ${update}"
defaults write com.apple.DiagnosticReportingService AutoSubmit -int ${update}

original=$(defaults read com.apple.SubmitDiagInfo AutoSubmit 2>/dev/null || true)
update=0
echo "    - Disabling diagnostic info auto-submit: ${original:-$unknown} → ${update}"
defaults write com.apple.SubmitDiagInfo AutoSubmit -int ${update}

# Disabling Improve Assistive Voice Features stops Voice Control audio
# samples from being sent to Apple for analysis and model training
original=$(defaults read com.apple.voiceservices.logging AssistantVoiceTriggerLoggingEnabled 2>/dev/null || true)
update=0
echo "    - Disabling assistive voice trigger logging: ${original:-$unknown} → ${update}"
defaults write com.apple.voiceservices.logging AssistantVoiceTriggerLoggingEnabled -int ${update}

# Disabling third-party crash data sharing prevents app crash reports
# from being forwarded to developers via Apple's relay — some may contain
# user data captured at the point of crash
original=$(defaults read com.apple.DiagnosticReportingService ThirdPartyDataSubmit 2>/dev/null || true)
update=0
echo "    - Disabling third-party diagnostic data sharing: ${original:-$unknown} → ${update}"
defaults write com.apple.DiagnosticReportingService ThirdPartyDataSubmit -int ${update}

# Disabling iCloud analytics prevents usage metadata collected in iCloud
# from being transmitted to Apple for product improvement purposes
original=$(defaults read com.apple.icloud.fmfd AutoSubmit 2>/dev/null || true)
update=0
echo "    - Disabling iCloud analytics auto-submit: ${original:-$unknown} → ${update}"
defaults write com.apple.icloud.fmfd AutoSubmit -int ${update}


# ══════════════════════════════════════════════════════════════════════════════
# TERMINAL
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Terminal]"

# Secure Keyboard Entry prevents other apps from using the Accessibility or
# event-tap APIs to read keystrokes while Terminal is focused — stops a
# compromised or malicious app from logging passwords, SSH keys, and commands
# typed in Terminal; a checkmark appears in Terminal > Secure Keyboard Entry
original=$(defaults read com.apple.terminal SecureKeyboardEntry 2>/dev/null || true)
update=1
echo "    - Enabling Secure Keyboard Entry in Terminal: ${original:-$unknown} → ${update}"
defaults write com.apple.terminal SecureKeyboardEntry -int ${update}


# ══════════════════════════════════════════════════════════════════════════════
# TOUCH ID
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Touch ID]"

# Enabling Touch ID for fast user switching allows switching between MacOS
# user accounts using biometric authentication instead of a full password prompt
original=$(defaults read com.apple.loginwindow useTouchIDForFUS 2>/dev/null || true)
update=1
echo "    - Enabling Touch ID for fast user switching: ${original:-$unknown} → ${update}"
defaults write com.apple.loginwindow useTouchIDForFUS -int ${update}


# ══════════════════════════════════════════════════════════════════════════════
# KEYBOARD
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Keyboard]"

# Fastest key repeat rate (2) eliminates perceptible pause between repeated
# keystrokes, which is critical for efficient text editing and navigation
# KeyRepeat: 15ms units (2=30ms fastest, 6=90ms default, 300=slowest)
original=$(defaults read NSGlobalDomain KeyRepeat 2>/dev/null || true)
update=2
echo "    - Setting key repeat rate: ${original:-$unknown} → ${update}"
defaults write NSGlobalDomain KeyRepeat -int ${update}

# Shortest initial repeat delay (15) reduces the time before a held key starts
# repeating, making hold-to-navigate significantly more responsive
# InitialKeyRepeat: 15ms units (15=225ms shortest, 25=375ms default, 120=slowest)
original=$(defaults read NSGlobalDomain InitialKeyRepeat 2>/dev/null || true)
update=15
echo "    - Setting initial key repeat delay: ${original:-$unknown} → ${update}"
defaults write NSGlobalDomain InitialKeyRepeat -int ${update}

# Globe key → Change Input Source (1) is the most common use of the Globe key
# for multi-language users; avoids accidental Dictation triggers
# AppleFnUsageType:
#   0=do nothing, 1=change input source, 2=show emoji picker, 3=start dictation
original=$(defaults read com.apple.HIToolbox AppleFnUsageType 2>/dev/null || true)
update=1
echo "    - Setting Globe key action: ${original:-$unknown} → ${update}"
defaults write com.apple.HIToolbox AppleFnUsageType -int ${update}

# Full keyboard navigation (mode 3) allows Tab to cycle through every UI
# control — buttons, checkboxes, menus — essential for accessibility
# and keyboard-driven workflows
# AppleKeyboardUIMode: 0=text fields and lists only, 2=all controls (legacy), 3=all controls
original=$(defaults read NSGlobalDomain AppleKeyboardUIMode 2>/dev/null || true)
update=3
echo "    - Enabling full keyboard navigation: ${original:-$unknown} → ${update}"
defaults write NSGlobalDomain AppleKeyboardUIMode -int ${update}

# Disabling Dictation prevents audio from being streamed to Apple's speech
# recognition servers when the Dictation shortcut is triggered
# AppleDictationAutoEnable: 0=disabled, 1=enabled
original=$(defaults read com.apple.HIToolbox AppleDictationAutoEnable 2>/dev/null || true)
update=0
echo "    - Disabling Dictation: ${original:-$unknown} → ${update}"
defaults write com.apple.HIToolbox AppleDictationAutoEnable -int ${update}

# Disabling autocorrect preserves intentional spelling and avoids unexpected
# word substitutions, particularly when typing code, names, or abbreviations
original=$(defaults read NSGlobalDomain NSAutomaticSpellingCorrectionEnabled 2>/dev/null || true)
update=0
echo "    - Disabling automatic spelling correction: ${original:-$unknown} → ${update}"
defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -int ${update}

# Disabling automatic capitalisation prevents MacOS from overriding casing,
# which is important in code, command-line input, and structured text
original=$(defaults read NSGlobalDomain NSAutomaticCapitalizationEnabled 2>/dev/null || true)
update=0
echo "    - Disabling automatic capitalisation: ${original:-$unknown} → ${update}"
defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -int ${update}

# Disabling period substitution stops double-space from being converted to
# ". " — a mobile typing habit that fires accidentally on a Mac keyboard
# when pausing mid-sentence
original=$(defaults read NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled 2>/dev/null || true)
update=0
echo "    - Disabling automatic period substitution: ${original:-$unknown} → ${update}"
defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -int ${update}


# ══════════════════════════════════════════════════════════════════════════════
# KEYBOARD SHORTCUTS
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Keyboard Shortcuts]"

# Disabling screenshot shortcuts frees Cmd+Shift+3/4/5 for other tools
# (e.g. window managers, clipboard managers) and prevents accidental captures
# AppleSymbolicHotKeys IDs:
#   28=save screen to file
#   29=copy screen to clipboard,
#   30=save selection to file
#   31=copy selection to clipboard,
#   184=screenshot and recording options panel
echo "    - Disabling screenshot shortcut:"
echo "      × Save screen to file (28)"
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 28 '<dict><key>enabled</key><false/></dict>'
echo "      × Copy screen to clipboard (29)"
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 29 '<dict><key>enabled</key><false/></dict>'
echo "      × Save selection to file (30)"
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 30 '<dict><key>enabled</key><false/></dict>'
echo "      × Copy selection to clipboard (31)"
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 31 '<dict><key>enabled</key><false/></dict>'
echo "      × Screenshot and recording options (184)"
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 184 '<dict><key>enabled</key><false/></dict>'

# Disabling input source switching shortcuts prevents Ctrl+Space and
# Ctrl+Option+Space from hijacking key combinations used by editors and IDEs
# AppleSymbolicHotKeys IDs:
#   60=select previous input source
#   61=select next input source
echo "    - Disabling input source shortcut:"
echo "      × Select previous input source (60)"
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 60 '<dict><key>enabled</key><false/></dict>'
echo "      × Select next input source (61)"
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 61 '<dict><key>enabled</key><false/></dict>'

# Apply symbolic hotkey changes immediately without requiring a restart
/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u


# ══════════════════════════════════════════════════════════════════════════════
# TRACKPAD
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Trackpad]"

# Tap-to-click enables a light tap instead of a physical click, reducing
# finger fatigue and matching the expected MacBook trackpad behaviour
original=$(defaults read com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking 2>/dev/null || true)
update=1
echo "    - Enabling tap to click for Bluetooth trackpad: ${original:-$unknown} → ${update}"
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -int ${update}

original=$(defaults read com.apple.AppleMultitouchTrackpad Clicking 2>/dev/null || true)
update=1
echo "    - Enabling tap to click for built-in trackpad: ${original:-$unknown} → ${update}"
defaults write com.apple.AppleMultitouchTrackpad Clicking -int ${update}

# com.apple.mouse.tapBehavior: 0=tap to click disabled, 1=tap to click enabled
original=$(defaults -currentHost read NSGlobalDomain com.apple.mouse.tapBehavior 2>/dev/null || true)
update=1
echo "    - Enabling tap to click system-wide: ${original:-$unknown} → ${update}"
defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int ${update}
defaults write NSGlobalDomain com.apple.mouse.tapBehavior -int ${update}

# Click pressure: 0=light, 1=medium, 2=firm
original=$(defaults read com.apple.AppleMultitouchTrackpad FirstButtonThreshold 2>/dev/null || true)
update=1
echo "    - Setting primary click pressure: ${original:-$unknown} → ${update}"
defaults write com.apple.AppleMultitouchTrackpad FirstButtonThreshold -int ${update}

original=$(defaults read com.apple.AppleMultitouchTrackpad SecondButtonThreshold 2>/dev/null || true)
update=1
echo "    - Setting secondary click pressure: ${original:-$unknown} → ${update}"
defaults write com.apple.AppleMultitouchTrackpad SecondButtonThreshold -int ${update}

# Tracking speed 1.5 is above the default 1.0 and provides a balance between
# precision and speed — adjust to taste within the 0.0–3.0 range
# com.apple.trackpad.scaling: 0.0=slowest, 1.0=default, 3.0=fastest
original=$(defaults read NSGlobalDomain com.apple.trackpad.scaling 2>/dev/null || true)
update=1.5
echo "    - Setting trackpad tracking speed: ${original:-$unknown} → ${update}"
defaults write NSGlobalDomain com.apple.trackpad.scaling -float ${update}

# Three-finger swipe down for App Exposé is more ergonomic than four-finger
# swipe and mirrors the Mission Control gesture but scoped to the current app
original=$(defaults read com.apple.dock showAppExposeGestureEnabled 2>/dev/null || true)
update=1
echo "    - Enabling App Exposé swipe gesture in Dock: ${original:-$unknown} → ${update}"
defaults write com.apple.dock showAppExposeGestureEnabled -int ${update}

# TrackpadFourFingerVertSwipeGesture: 0=disabled, 2=enabled
original=$(defaults read com.apple.AppleMultitouchTrackpad TrackpadFourFingerVertSwipeGesture 2>/dev/null || true)
update=0
echo "    - Disabling four-finger vertical swipe gesture: ${original:-$unknown} → ${update}"
defaults write com.apple.AppleMultitouchTrackpad TrackpadFourFingerVertSwipeGesture -int ${update}

# TrackpadThreeFingerVertSwipeGesture: 0=disabled, 2=enabled
original=$(defaults read com.apple.AppleMultitouchTrackpad TrackpadThreeFingerVertSwipeGesture 2>/dev/null || true)
update=2
echo "    - Enabling three-finger vertical swipe gesture: ${original:-$unknown} → ${update}"
defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerVertSwipeGesture -int ${update}

killall Dock 2>/dev/null || true


# ══════════════════════════════════════════════════════════════════════════════
# NETWORK HARDENING
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Network Hardening]"

# Disabling Bonjour multicast advertisements stops the Mac from broadcasting
# its hostname and available services over mDNS, reducing LAN-level discoverability
original=$(sudo defaults read /Library/Preferences/com.apple.mDNSResponder NoMulticastAdvertisements 2>/dev/null || true)
update=1
echo "    - Disabling Bonjour multicast advertisements: ${original:-$unknown} → ${update}"
sudo defaults write /Library/Preferences/com.apple.mDNSResponder NoMulticastAdvertisements -int ${update}

# Disabling Remote Apple Events prevents remote AppleScript execution from
# another machine on the network — a potential lateral movement vector
original=$(sudo systemsetup -getremoteappleevents 2>/dev/null | awk -F': ' '{print $NF; exit}' || true)
update=off
echo "    - Disabling Remote Apple Events: ${original:-$unknown} → ${update}"
sudo systemsetup -f -setremoteappleevents ${update} &>/dev/null || true

# Disabling IPv6 on Wi-Fi and Ethernet removes link-local addresses from the LAN,
# reducing the attack surface from neighbour discovery and router advertisement spoofing.
# Remove these two lines if corporate VPN or services require IPv6.
original=$(networksetup -getinfo "Wi-Fi" | awk '/IPv6/ {print $NF}' 2>/dev/null || true)
echo "    - Disabling IPv6 on Wi-Fi: ${original:-$unknown} → off"
sudo networksetup -setv6off "Wi-Fi" 2>/dev/null || true
if networksetup -listallnetworkservices 2>/dev/null | grep -q '^Ethernet$'; then
  original=$(networksetup -getinfo "Ethernet" | awk '/IPv6/ {print $NF}' 2>/dev/null || true)
  echo "    - Disabling IPv6 on Ethernet: ${original:-$unknown} → off"
  sudo networksetup -setv6off "Ethernet" 2>/dev/null || true
fi

# Enabling TCP keepalive on battery to ensure Find My Mac works properly. Preserve iMessage/FaceTime push delivery when plugged in.
original=$(pmset -g custom 2>/dev/null | awk '/^Battery Power:/{f=1;next} /^[A-Z]/{f=0} f&&/tcpkeepalive/{print $2;exit}' || true)
update=1
echo "    - Enabling TCP keepalive on battery: ${original:-$unknown} → ${update}"
sudo pmset -b tcpkeepalive ${update} &>/dev/null || true


# ══════════════════════════════════════════════════════════════════════════════
# SLEEP & ENCRYPTION HARDENING
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Sleep & Encryption Hardening]"

# Destroying the FileVault key on standby forces full password re-entry after
# the standbydelay window elapses — the encryption key is purged from RAM,
# not just the screen lock. Touch ID and biometric unlock continue to work
# during normal sleep; they stop only once standby is reached.
original=$(pmset -g live 2>/dev/null | awk 'tolower($1)~/destroyfvkeyonstandby/{print $2;exit}' || true)
update=1
echo "    - Enabling FileVault key destruction on standby: ${original:-$unknown} → ${update}"
sudo pmset -a destroyfvkeyonstandby ${update} &>/dev/null || true

# 15-minute standby delay means biometric unlock works normally for short
# sleep periods; after 15 minutes the key is purged and the full password
# is required on next wake
original=$(pmset -g live 2>/dev/null | awk '/standbydelay/{print $2;exit}' || true)
update=900
echo "    - Setting standby delay: ${original:-$unknown} → ${update}"
sudo pmset -a standbydelay ${update} &>/dev/null || true

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
original=$(pmset -g live 2>/dev/null | awk '/hibernatemode/{print $2;exit}' || true)
update=25
echo "    - Setting hibernate mode: ${original:-$unknown} → ${update}"
sudo pmset -a hibernatemode ${update} &>/dev/null || true


# ══════════════════════════════════════════════════════════════════════════════
# FONTS
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Fonts]"

target_fonts_dir="$HOME/Library/Fonts"
source_fonts_archive="fonts.tar.gz"
source_fonts_path="${CHEZMOI_SOURCE_DIR}/assets/${source_fonts_archive}"

printf "    Install fonts from ${source_fonts_archive}? [y/N] "
read -r _input
if [[ "${_input}" =~ ^[Yy]$ ]]; then
  echo "    - Decompressing fonts: ${source_fonts_archive} into '${target_fonts_dir}'"
  mkdir -p "$target_fonts_dir"
  tar -xzvf "$source_fonts_path" -C "$target_fonts_dir"
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
safari_profile="${CHEZMOI_SOURCE_DIR}/assets/safari.mobileconfig"

printf "    Install Safari configuration profile? [y/N] "
read -r _input
if [[ "${_input}" =~ ^[Yy]$ ]]; then
  echo "    - Installing Safari configuration profile"
  open "$safari_profile"
  # Give the profile installer a moment to register before opening System Settings
  sleep 2
  echo "    - Opening System Settings → General → Device Management"
  open "x-apple.systempreferences:com.apple.preferences.configurationprofiles"
  echo "    ⚠  Approve the profile in System Settings → General → Device Management"

  echo "  ┌────────────────────────────────────────────────────────────────────┐"
  echo "  │  Safari → Settings — complete these manually after approving       │"
  echo "  │  the configuration profile in System Settings → Device Management  │"
  echo "  └────────────────────────────────────────────────────────────────────┘"
fi


# ══════════════════════════════════════════════════════════════════════════════
# SOFTWARE UPDATE
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Software Update]"

# Checking daily rather than weekly means you're never more than 24 hours
# behind on available updates without having done anything
original=$(defaults read com.apple.SoftwareUpdate AutomaticCheckEnabled 2>/dev/null || true)
update=1
echo "    - Enabling automatic update checks: ${original:-$unknown} → ${update}"
defaults write com.apple.SoftwareUpdate AutomaticCheckEnabled -int ${update}

# ScheduleFrequency: 1=daily, 7=weekly
original=$(defaults read com.apple.SoftwareUpdate ScheduleFrequency 2>/dev/null || true)
update=1
echo "    - Setting update check frequency: ${original:-$unknown} → ${update}"
defaults write com.apple.SoftwareUpdate ScheduleFrequency -int ${update}

# Background download means updates are ready to install immediately when
# you open System Settings — no waiting for the download to complete
# AutomaticDownload: 0=disabled, 1=enabled
original=$(defaults read com.apple.SoftwareUpdate AutomaticDownload 2>/dev/null || true)
update=1
echo "    - Enabling background update downloads: ${original:-$unknown} → ${update}"
defaults write com.apple.SoftwareUpdate AutomaticDownload -int ${update}

# Security patches — XProtect malware definitions, MRT, Gatekeeper blocklists,
# certificate revocations — install automatically without prompting;
# zero-day patches are applied without requiring manual action
# CriticalUpdateInstall: 0=disabled, 1=enabled
original=$(defaults read com.apple.SoftwareUpdate CriticalUpdateInstall 2>/dev/null || true)
update=1
echo "    - Enabling automatic security patch installation: ${original:-$unknown} → ${update}"
defaults write com.apple.SoftwareUpdate CriticalUpdateInstall -int ${update}

# App Store purchased apps update automatically in the background — security
# patches for App Store apps are applied without needing to open the App Store
original=$(defaults read com.apple.commerce AutoUpdate 2>/dev/null || true)
update=1
echo "    - Enabling automatic App Store app updates: ${original:-$unknown} → ${update}"
defaults write com.apple.commerce AutoUpdate -int ${update}


# ══════════════════════════════════════════════════════════════════════════════
# ACTIVITY MONITOR
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Activity Monitor]"

# Sorting by CPU descending means the highest-consuming process is always
# at the top when you open Activity Monitor — no manual column click required
original=$(defaults read com.apple.ActivityMonitor SortColumn 2>/dev/null || true)
update=CPUUsage
echo "    - Setting Activity Monitor sort column: ${original:-$unknown} → ${update}"
defaults write com.apple.ActivityMonitor SortColumn -string "${update}"

# SortDirection: 0=descending, 1=ascending
original=$(defaults read com.apple.ActivityMonitor SortDirection 2>/dev/null || true)
update=0
echo "    - Setting Activity Monitor sort direction: ${original:-$unknown} → ${update}"
defaults write com.apple.ActivityMonitor SortDirection -int ${update}

# Showing all processes rather than just user-owned ones gives a complete
# picture of system activity including background daemons
# ShowCategory:
#   0=all processes
#   1=my processes
#   2=system processes,
#   3=other processes
#   4=windowed processes
original=$(defaults read com.apple.ActivityMonitor ShowCategory 2>/dev/null || true)
update=0
echo "    - Showing all processes in Activity Monitor: ${original:-$unknown} → ${update}"
defaults write com.apple.ActivityMonitor ShowCategory -int ${update}


# ══════════════════════════════════════════════════════════════════════════════
# TIME MACHINE
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Time Machine]"

# Suppressing the "Use this disk for Time Machine?" prompt that fires every
# time an external drive is connected — USB sticks, SD cards, daily-use drives
# all trigger it; this silences it without disabling Time Machine itself
original=$(defaults read com.apple.TimeMachine DoNotOfferNewDisksForBackup 2>/dev/null || true)
update=1
echo "    - Disabling Time Machine new-disk prompt: ${original:-$unknown} → ${update}"
defaults write com.apple.TimeMachine DoNotOfferNewDisksForBackup -int ${update}

# Local Time Machine snapshots are stored on the startup disk when the backup
# drive is not connected — disabling them frees disk space at the cost of
# losing the ability to recover files when the backup drive is absent
original=$(tmutil listlocalsnapshots / 2>/dev/null | wc -l | awk '{print $1}' || true)
echo "    - Disabling local Time Machine snapshots: ${original:-0} local snapshots"
hash tmutil &>/dev/null && sudo tmutil disablelocal 2>/dev/null || true


# ══════════════════════════════════════════════════════════════════════════════
# UI BEHAVIOUR
# ══════════════════════════════════════════════════════════════════════════════

echo "  [UI Behaviour]"

# Toolbar title proxy icons and path tooltips appear after a ~0.5s hover delay
# by default — setting to 0 makes them respond instantly
original=$(defaults read NSGlobalDomain NSToolbarTitleViewRolloverDelay 2>/dev/null || true)
update=0
echo "    - Setting toolbar title rollover delay: ${original:-$unknown} → ${update}"
defaults write NSGlobalDomain NSToolbarTitleViewRolloverDelay -float ${update}

# The animated focus ring pulses in when tabbing between UI controls —
# disabling the animation makes keyboard navigation feel snappier
original=$(defaults read NSGlobalDomain NSUseAnimatedFocusRing 2>/dev/null || true)
update=0
echo "    - Disabling focus ring animation: ${original:-$unknown} → ${update}"
defaults write NSGlobalDomain NSUseAnimatedFocusRing -int ${update}

# Open and save dialogs default to a compact two-panel view that hides the
# sidebar and path bar — forcing expanded mode means full Finder-style
# navigation is available immediately on every save without clicking a toggle
original=$(defaults read NSGlobalDomain NSNavPanelExpandedStateForSaveMode 2>/dev/null || true)
update=1
echo "    - Expanding save panel by default: ${original:-$unknown} → ${update}"
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -int ${update}

original=$(defaults read NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 2>/dev/null || true)
update=1
echo "    - Expanding save panel by default mode 2: ${original:-$unknown} → ${update}"
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -int ${update}

# Print dialogs also default to compact mode — forcing expanded mode means
# paper size, orientation, and printer-specific options are visible immediately
original=$(defaults read NSGlobalDomain PMPrintingExpandedStateForPrint 2>/dev/null || true)
update=1
echo "    - Expanding print panel by default: ${original:-$unknown} → ${update}"
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -int ${update}
original=$(defaults read NSGlobalDomain PMPrintingExpandedStateForPrint2 2>/dev/null || true)
update=1
echo "    - Expanding print panel by default mode 2: ${original:-$unknown} → ${update}"
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint2 -int ${update}

# Setting window resize time to near-zero makes Cocoa windows snap to their
# new size instantly — the default ~0.2s spring animation adds perceptible
# latency on every maximize, double-click resize, or drag-resize
original=$(defaults read NSGlobalDomain NSWindowResizeTime 2>/dev/null || true)
update=0.001
echo "    - Setting window resize animation to near-instant: ${original:-$unknown} → ${update}"
defaults write NSGlobalDomain NSWindowResizeTime -float ${update}


# ══════════════════════════════════════════════════════════════════════════════
# ADDITIONAL PRIVACY
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Additional Privacy]"

# Handoff/Continuity is enabled intentionally for active cross-device workflow —
# these flags allow this device to advertise and receive Continuity activities
# (Handoff, Universal Clipboard, etc.) to/from trusted Apple devices
original=$(defaults read com.apple.coreduetd.plist ActivityAdvertisingAllowed 2>/dev/null || true)
update=1
echo "    - Enabling Handoff activity advertising: ${original:-$unknown} → ${update}"
defaults write com.apple.coreduetd.plist ActivityAdvertisingAllowed -int ${update}

original=$(defaults read com.apple.coreduetd.plist ActivityReceivingAllowed 2>/dev/null || true)
update=1
echo "    - Enabling Handoff activity receiving: ${original:-$unknown} → ${update}"
defaults write com.apple.coreduetd.plist ActivityReceivingAllowed -int ${update}

# Silencing the crash reporter dialog prevents the UI prompt from appearing
# after a crash, which could inadvertently invite "Send to Apple" clicks.
# Analytical opt-out is already set in the Analytics section.
# DialogType: "developer"=detailed dialog, "basic"=basic dialog, "none"=silent
original=$(defaults read com.apple.CrashReporter DialogType 2>/dev/null || true)
update=none
echo "    - Setting crash reporter dialog type: ${original:-$unknown} → ${update}"
defaults write com.apple.CrashReporter DialogType ${update}

# Setting Recent Documents limit to 0 prevents "Open Recent" history from
# accumulating in app menus, removing a passive record of opened files
# NSRecentDocumentsLimit: 0=disabled, default=10
original=$(defaults read NSGlobalDomain NSRecentDocumentsLimit 2>/dev/null || true)
update=0
echo "    - Setting recent documents limit: ${original:-$unknown} → ${update}"
defaults write NSGlobalDomain NSRecentDocumentsLimit -int ${update}

# Re-enforcing Gatekeeper ensures only signed and notarised apps can run.
# Some third-party installers call spctl --master-disable; this restores it.
original=$(sudo spctl --status 2>/dev/null | awk '{print $NF; exit}' || true)
echo "    - Re-enabling Gatekeeper: ${original:-$unknown} → enabled"
sudo spctl --master-enable 2>/dev/null || true


# ══════════════════════════════════════════════════════════════════════════════
# LOGIN WINDOW HARDENING
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Login Window Hardening]"

# Showing name and password fields instead of a user list prevents enumeration
# of local accounts by anyone who reaches the login screen
original=$(sudo defaults read /Library/Preferences/com.apple.loginwindow SHOWFULLNAME 2>/dev/null || true)
update=1
echo "    - Showing name+password fields at login: ${original:-$unknown} → ${update}"
sudo defaults write /Library/Preferences/com.apple.loginwindow SHOWFULLNAME -int ${update}

# Login window disclaimer — prompted here, right before the command that sets it.
# Displaying a custom contact banner at the login window enables recovery
# of the device if lost, and signals to a finder that the device is monitored
LOGIN_BANNER=""
printf "    Set login window banner? [y/N] "
read -r _input
if [[ "${_input}" =~ ^[Yy]$ ]]; then
  printf "    Owner name:  "
  read -r OWNER_NAME
  printf "    Owner phone: "
  read -r OWNER_PHONE
  LOGIN_BANNER="Authorized use only. This device is encrypted and its location tracking is enabled. If found, contact ${OWNER_NAME} by call, SMS, iMessage, WhatsApp, or Telegram at ${OWNER_PHONE}."
fi

if [[ -n "${LOGIN_BANNER:-}" ]]; then
  original=$(sudo defaults read /Library/Preferences/com.apple.loginwindow ShowBannerText 2>/dev/null || true)
  update=1
  echo "    - Enabling login window message display: ${original:-$unknown} → ${update}"
  sudo defaults write /Library/Preferences/com.apple.loginwindow ShowBannerText -int ${update}

  original=$(sudo defaults read /Library/Preferences/com.apple.loginwindow LoginwindowText 2>/dev/null || true)
  update=$LOGIN_BANNER
  echo "    - Setting login window disclaimer text:"
  echo "      × ${original:-$unknown}"
  echo "      → ${update}"
  sudo defaults write /Library/Preferences/com.apple.loginwindow LoginwindowText -string "${update}"
fi

# Disabling console login prevents an attacker with physical access from
# bypassing the graphical login screen by typing ">console" as the username
original=$(sudo defaults read /Library/Preferences/com.apple.loginwindow DisableConsoleAccess 2>/dev/null || true)
update=1
echo "    - Disabling console login: ${original:-$unknown} → ${update}"
sudo defaults write /Library/Preferences/com.apple.loginwindow DisableConsoleAccess -int ${update}

# Disabling login from an account whose home directory is on an external drive
# closes a vector where an attacker could boot from a crafted external disk
# and log in as a valid user whose home directory is mounted from it
original=$(sudo defaults read /Library/Preferences/com.apple.loginwindow EnableExternalAccounts 2>/dev/null || true)
update=0
echo "    - Disabling login for accounts on external drives: ${original:-$unknown} → ${update}"
sudo defaults write /Library/Preferences/com.apple.loginwindow EnableExternalAccounts -int ${update}

# Disabling re-launch of apps from the previous session prevents apps from
# automatically opening on next login, giving a clean, known-good startup state
original=$(defaults read com.apple.loginwindow TALLogoutSavesState 2>/dev/null || true)
update=0
echo "    - Disabling app state save at logout: ${original:-$unknown} → ${update}"
defaults write com.apple.loginwindow TALLogoutSavesState -int ${update}

original=$(defaults read com.apple.loginwindow LoginwindowLaunchesRelaunchApps 2>/dev/null || true)
update=0
echo "    - Disabling app re-launch on login: ${original:-$unknown} → ${update}"
defaults write com.apple.loginwindow LoginwindowLaunchesRelaunchApps -int ${update}

# Allowing the user to reset their login password via Apple Account provides
# a recovery path if the password is forgotten, without requiring Recovery Mode
original=$(sudo dscl . -read "/Users/${USER}" appleIDAuthSupported 2>/dev/null | awk '{print $NF; exit}' || true)
update=1
echo "    - Enabling password reset via Apple Account: ${original:-$unknown} → ${update}"
sudo dscl . -create "/Users/${USER}" appleIDAuthSupported ${update}


# ══════════════════════════════════════════════════════════════════════════════
# SERVICES HARDENING
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Services Hardening]"

# Setting the computer name controls how this Mac appears on the network,
# in Finder sidebars, and in system dialogs — a descriptive name avoids
# exposing the owner's full name embedded in the default hostname
COMPUTER_NAME=""
printf "    Set computer name? [y/N] "
read -r _input
if [[ "${_input}" =~ ^[Yy]$ ]]; then
  printf "    Computer name: "
  read -r COMPUTER_NAME
fi

if [[ -n "${COMPUTER_NAME}" ]]; then
  original=$(sudo systemsetup -getcomputername 2>/dev/null | awk -F': ' '{print $NF; exit}' || echo $unknown)
  echo "    - Setting computer name: ${original:-$unknown} → ${COMPUTER_NAME}"
  sudo systemsetup -setcomputername "${COMPUTER_NAME}" &>/dev/null || true
  sudo scutil --set ComputerName "${COMPUTER_NAME}"
  sudo scutil --set HostName "${COMPUTER_NAME}"
  sudo scutil --set LocalHostName "${COMPUTER_NAME//' '/-}"
fi

# Disabling Remote Login (SSH server) closes the inbound SSH port, preventing
# remote shell access even for authenticated users
original=$(sudo systemsetup -getremotelogin 2>/dev/null | awk -F': ' '{print $NF; exit}' || true)
update=off
echo "    - Disabling Remote Login / SSH server: ${original:-$unknown} → ${update}"
sudo systemsetup -f -setremotelogin ${update} &>/dev/null || true
original=$(sudo launchctl print-disabled system | awk '/com.openssh.sshd/ {print $NF}' 2>/dev/null || true)
echo "    - Disabling SSH daemon via launchctl: ${original:-$unknown} → disabled"
sudo launchctl disable system/com.openssh.sshd 2>/dev/null || true

# Auto-restarting after a complete system freeze (kernel panic, hung process)
# means returning to a login screen rather than a frozen display that requires
# a manual hard power-cycle
original=$(sudo systemsetup -getrestartfreeze 2>/dev/null | awk -F': ' '{print $NF; exit}' || true)
update=on
echo "    - Enabling auto-restart on system freeze: ${original:-$unknown} → ${update}"
sudo systemsetup -setrestartfreeze ${update} &>/dev/null || true

# Disabling legacy network services removes attack surface from protocols
# that either have no authentication (TFTP), use plaintext transport (FTP, Telnet),
# or are unnecessary on a modern personal Mac (NFS, RPC, NetBIOS)
original=$(sudo launchctl print-disabled system | awk '/com.apple.tftpd/ {print $NF}' 2>/dev/null || true)
echo "    - Disabling TFTP: ${original:-$unknown} → disabled"
sudo launchctl disable system/com.apple.tftpd   2>/dev/null || true
original=$(sudo launchctl print-disabled system | awk '/com.apple.ftpd/ {print $NF}' 2>/dev/null || true)
echo "    - Disabling FTP: ${original:-$unknown} → disabled"
sudo launchctl disable system/com.apple.ftpd    2>/dev/null || true
original=$(sudo launchctl print-disabled system | awk '/com.apple.telnetd/ {print $NF}' 2>/dev/null || true)
echo "    - Disabling Telnet: ${original:-$unknown} → disabled"
sudo launchctl disable system/com.apple.telnetd 2>/dev/null || true
original=$(sudo launchctl print-disabled system | awk '/com.apple.nfsd/ {print $NF}' 2>/dev/null || true)
echo "    - Disabling NFS: ${original:-$unknown} → disabled"
sudo launchctl disable system/com.apple.nfsd    2>/dev/null || true
original=$(sudo launchctl print-disabled system | awk '/com.apple.rpcbind/ {print $NF}' 2>/dev/null || true)
echo "    - Disabling RPC portmapper: ${original:-$unknown} → disabled"
sudo launchctl disable system/com.apple.rpcbind 2>/dev/null || true
original=$(sudo launchctl print-disabled system | awk '/com.apple.netbiosd/ {print $NF}' 2>/dev/null || true)
echo "    - Disabling NetBIOS: ${original:-$unknown} → disabled"
sudo launchctl disable system/com.apple.netbiosd 2>/dev/null || true

# Disabling Internet Sharing prevents this Mac from acting as a NAT gateway,
# which would expose the network to any device connected via sharing
original=$(sudo /usr/libexec/PlistBuddy -c "Print :NAT:Enabled" /Library/Preferences/SystemConfiguration/com.apple.nat.plist 2>/dev/null || true)
update=0
echo "    - Disabling Internet Sharing / NAT gateway: ${original:-$unknown} → ${update}"
sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.nat NAT -dict Enabled -int ${update}

# Deactivating Content Caching stops this Mac from serving as an Apple CDN
# relay on the local network, which could expose network topology and traffic
original=$(sudo AssetCacheManagerUtil isActivated 2>/dev/null | awk '{print $NF; exit}' || true)
echo "    - Deactivating Content Caching: ${original:-$unknown} → deactivated"
sudo AssetCacheManagerUtil deactivate 2>/dev/null || true


# ══════════════════════════════════════════════════════════════════════════════
# AUDIT AND LOGGING
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Audit & Logging]"

# Enabling the Basic Security Module (BSM) audit daemon (auditd) creates tamper-evident logs
# of authentication events, privilege escalation, and file access operations —
# essential for post-incident forensic investigation
original=$(sudo launchctl print system/com.apple.auditd >/dev/null 2>&1 && echo "enabled" || echo "disabled")
echo "    - Enabling Basic Security Module audit daemon: ${original} → enabled"
sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.auditd.plist 2>/dev/null || true

# Retaining system logs for 365 days provides a full year of audit history —
# the default MacOS log retention is very short (days) and insufficient for
# detecting slow or retrospective threats
# logTTL: days (default=7, recommended minimum=90)
original=$(sudo defaults read /Library/Preferences/com.apple.logd logTTL 2>/dev/null || true)
update=365
echo "    - Setting system log retention: ${original:-$unknown} → ${update}"
sudo defaults write /Library/Preferences/com.apple.logd logTTL -int ${update}

# Enabling default-level logging for the security subsystem captures
# authentication, authorisation, and cryptographic events at full detail
original=$(sudo log config --status --subsystem com.apple.security 2>/dev/null | awk '/Mode/{print $NF; exit}' || true)
update='level:default'
echo "    - Enabling detailed security subsystem logging: ${original:-$unknown} → ${update}"
sudo log config --mode "${update}" --subsystem com.apple.security 2>/dev/null || true


# ══════════════════════════════════════════════════════════════════════════════
# FINDER
# ══════════════════════════════════════════════════════════════════════════════

echo "  [Finder]"

# ── General ──────────────────────────────────────────────────────────────────

# Disabling all Finder window and Get Info animations makes every Finder
# interaction feel instantaneous — windows open and close without any slide
original=$(defaults read com.apple.finder DisableAllAnimations 2>/dev/null || true)
update=1
echo "    - Disabling all Finder animations: ${original:-$unknown} → ${update}"
defaults write com.apple.finder DisableAllAnimations -int ${update}

# Showing hard disks on the Desktop gives direct access to internal volumes
# from the Desktop without opening Finder
original=$(defaults read com.apple.finder ShowHardDrivesOnDesktop 2>/dev/null || true)
update=1
echo "    - Showing hard disks on Desktop: ${original:-$unknown} → ${update}"
defaults write com.apple.finder ShowHardDrivesOnDesktop -int ${update}

# Showing external disks on the Desktop makes plugged-in drives immediately
# visible and accessible without launching Finder
original=$(defaults read com.apple.finder ShowExternalHardDrivesOnDesktop 2>/dev/null || true)
update=1
echo "    - Showing external disks on Desktop: ${original:-$unknown} → ${update}"
defaults write com.apple.finder ShowExternalHardDrivesOnDesktop -int ${update}

# Showing removable media on the Desktop surfaces CDs, DVDs, and iOS devices
# as soon as they are connected
original=$(defaults read com.apple.finder ShowRemovableMediaOnDesktop 2>/dev/null || true)
update=1
echo "    - Showing removable media on Desktop: ${original:-$unknown} → ${update}"
defaults write com.apple.finder ShowRemovableMediaOnDesktop -int ${update}

# Opening new Finder windows to Documents provides a sensible default
# that matches where most working files are stored
# NewWindowTarget:
#   "PfCm"=Computer, "PfVo"=Volume, "PfHm"=Home, "PfDe"=Desktop,
#   "PfDo"=Documents, "PfAF"=All Files, "PfLo"=custom path
original=$(defaults read com.apple.finder NewWindowTarget 2>/dev/null || true)
update=PfDo
echo "    - Setting new Finder window target: ${original:-$unknown} → ${update}"
defaults write com.apple.finder NewWindowTarget -string "${update}"

original=$(defaults read com.apple.finder NewWindowTargetPath 2>/dev/null || true)
update='file://${HOME}/Documents/'
echo "    - Setting new Finder window target path: '${original:-$unknown}' → '${update}'"
defaults write com.apple.finder NewWindowTargetPath -string "${update}"

# Opening folders in tabs rather than new windows keeps Finder sessions
# contained and avoids window sprawl
original=$(defaults read com.apple.finder FinderSpawnTab 2>/dev/null || true)
update=1
echo "    - Enabling open-folders-in-tabs: ${original:-$unknown} → ${update}"
defaults write com.apple.finder FinderSpawnTab -int ${update}

# ── Advanced ─────────────────────────────────────────────────────────────────

# Showing all filename extensions is a critical security setting — it prevents
# spoofed extensions (e.g. "document.pdf.app") from appearing as safe file types
original=$(defaults read NSGlobalDomain AppleShowAllExtensions 2>/dev/null || true)
update=1
echo "    - Showing all filename extensions: ${original:-$unknown} → ${update}"
defaults write NSGlobalDomain AppleShowAllExtensions -int ${update}

# The status bar at the bottom of every Finder window shows item count and
# available disk space — without it you must ⌘I a folder or open Disk Utility
# to know how full a volume is
original=$(defaults read com.apple.finder ShowStatusBar 2>/dev/null || true)
update=1
echo "    - Showing Finder status bar: ${original:-$unknown} → ${update}"
defaults write com.apple.finder ShowStatusBar -int ${update}

# The path bar shows a breadcrumb trail at the bottom of every Finder window —
# click any crumb to jump there, or drag a file onto a crumb to move it
original=$(defaults read com.apple.finder ShowPathbar 2>/dev/null || true)
update=1
echo "    - Showing Finder path bar: ${original:-$unknown} → ${update}"
defaults write com.apple.finder ShowPathbar -int ${update}

# Showing the full Unix path in the Finder window title bar (e.g.
# /Users/<user>/Documents/Project) makes it easy to copy paths for Terminal use
original=$(defaults read com.apple.finder _FXShowPosixPathInTitle 2>/dev/null || true)
update=1
echo "    - Showing full POSIX path in Finder title: ${original:-$unknown} → ${update}"
defaults write com.apple.finder _FXShowPosixPathInTitle -int ${update}

# Suppressing .DS_Store on network shares stops MacOS from littering other
# OS users' shared volumes with invisible Mac-specific metadata files;
# suppressing on USB drives prevents spreading them to every machine you connect to
original=$(defaults read com.apple.desktopservices DSDontWriteNetworkStores 2>/dev/null || true)
update=1
echo "    - Disabling .DS_Store on network volumes: ${original:-$unknown} → ${update}"
defaults write com.apple.desktopservices DSDontWriteNetworkStores -int ${update}

original=$(defaults read com.apple.desktopservices DSDontWriteUSBStores 2>/dev/null || true)
update=1
echo "    - Disabling .DS_Store on USB volumes: ${original:-$unknown} → ${update}"
defaults write com.apple.desktopservices DSDontWriteUSBStores -int ${update}

# Disabling the extension change warning removes the "Are you sure?" dialog
# that fires every time a file is renamed with a different extension —
# pure friction for anyone who renames files regularly
original=$(defaults read com.apple.finder FXEnableExtensionChangeWarning 2>/dev/null || true)
update=0
echo "    - Disabling extension change warning: ${original:-$unknown} → ${update}"
defaults write com.apple.finder FXEnableExtensionChangeWarning -int ${update}

# Keeping folders at the top when sorting by name groups directories above files,
# making directory navigation faster and more predictable
original=$(defaults read com.apple.finder _FXSortFoldersFirst 2>/dev/null || true)
update=1
echo "    - Keeping folders on top when sorted by name: ${original:-$unknown} → ${update}"
defaults write com.apple.finder _FXSortFoldersFirst -int ${update}

# Same folders-first behaviour on the Desktop ensures visual consistency
# with Finder windows when sorting Desktop items by name
original=$(defaults read com.apple.finder _FXSortFoldersFirstOnDesktop 2>/dev/null || true)
update=1
echo "    - Keeping folders on top on the Desktop: ${original:-$unknown} → ${update}"
defaults write com.apple.finder _FXSortFoldersFirstOnDesktop -int ${update}

# Searching the current folder by default scopes results to the relevant
# directory, avoiding noisy Mac-wide results when a folder-specific search
# is intended
# FXDefaultSearchScope: "SCev"=entire Mac, "SCcf"=current folder, "SCsp"=previous scope
original=$(defaults read com.apple.finder FXDefaultSearchScope 2>/dev/null || true)
update=SCcf
echo "    - Setting default search scope: ${original:-$unknown} → ${update}"
defaults write com.apple.finder FXDefaultSearchScope -string "${update}"

# Column view provides Miller-column navigation — each click opens a new
# column showing the selected folder's contents, ideal for deep hierarchies
# FXPreferredViewStyle: "icnv"=icon, "Nlsv"=list, "clmv"=column, "Flwv"=gallery
original=$(defaults read com.apple.finder FXPreferredViewStyle 2>/dev/null || true)
update=clmv
echo "    - Setting default Finder view style: ${original:-$unknown} → ${update}"
defaults write com.apple.finder FXPreferredViewStyle -string "${update}"

# Expanding the most useful Get Info sections (General, Open With, Sharing &
# Permissions) by default saves clicks when checking file metadata or
# changing the default app for a file type
echo "    - Expanding Get Info panes by default (General, Open With, Permissions)"
defaults write com.apple.finder FXInfoPanesExpanded -dict General -bool true OpenWith -bool true Privileges -bool true

# Showing mounted servers on the Desktop alongside local drives makes remote
# volumes immediately visible without opening Finder
original=$(defaults read com.apple.finder ShowMountedServersOnDesktop 2>/dev/null || true)
update=1
echo "    - Showing mounted servers on Desktop: ${original:-$unknown} → ${update}"
defaults write com.apple.finder ShowMountedServersOnDesktop -int ${update}

# ── Sidebar ──────────────────────────────────────────────────────────────────

# Hiding "On My Mac" from the sidebar avoids duplicate home folder entries;
# navigation to the local home is handled via Favorites
original=$(defaults read com.apple.finder ShowOnMyMacSection 2>/dev/null || true)
update=0
echo "    - Hiding On My Mac section from sidebar: ${original:-$unknown} → ${update}"
defaults write com.apple.finder ShowOnMyMacSection -int ${update}

# Showing Bonjour computers in the sidebar enables local network device
# discovery directly in Finder without additional tools
original=$(defaults read com.apple.finder ShowBonjour 2>/dev/null || true)
update=1
echo "    - Showing Bonjour computers in sidebar: ${original:-$unknown} → ${update}"
defaults write com.apple.finder ShowBonjour -int ${update}

# Showing Trash in the sidebar provides a single-click shortcut to the Trash
# from any Finder window
original=$(defaults read com.apple.finder ShowTrashInSidebar 2>/dev/null || true)
update=1
echo "    - Showing Trash in sidebar: ${original:-$unknown} → ${update}"
defaults write com.apple.finder ShowTrashInSidebar -int ${update}

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
echo "    - Enabling sudo command logging"
echo "Defaults log_host, log_year, logfile=/var/log/sudo.log" | sudo tee /etc/sudoers.d/01-logging > /dev/null
sudo chmod 440 /etc/sudoers.d/01-logging

# Requiring a password for every sudo invocation disables the default 5-minute
# credential cache. A hijacked or left-open terminal session cannot escalate
# privileges without re-authenticating each time.
# Written last so the rest of the script is not affected by the zero timeout.
# Written to /etc/sudoers.d/ to avoid modifying the main sudoers file.
echo "    - Setting sudo timestamp timeout"
echo "Defaults timestamp_timeout=0" | sudo tee /etc/sudoers.d/00-timeout > /dev/null
sudo chmod 440 /etc/sudoers.d/00-timeout


# ══════════════════════════════════════════════════════════════════════════════
# COMPLETE
# ══════════════════════════════════════════════════════════════════════════════

echo ""
echo "  ✓  All settings applied."
echo ""


# ══════════════════════════════════════════════════════════════════════════════
# RESTART PROMPT
# ══════════════════════════════════════════════════════════════════════════════

printf "  Restart now for all settings to take full effect? [y/N] "
read -r _input
if [[ "${_input}" =~ ^[Yy]$ ]]; then
  echo "  Restarting..."
  sudo shutdown -r now
else
  echo "  Skipped. Log out and back in, or reboot manually, when ready."
fi
