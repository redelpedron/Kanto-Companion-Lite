# Kanto Companion Lite

An Android in-game companion for Pokémon Red, Blue, and Gold, designed to enhance your playthrough with useful information and touch-friendly tools directly over the game.

Kanto Companion Lite takes inspiration from the original Kanto Companion concept while providing its own Android-focused interface, responsive layouts, and touch-first experience.

> **Fan-made:** Not affiliated with or endorsed by Nintendo, Game Freak, or The Pokémon Company.

## Table of Contents

- [Built On](#built-on)
- [Features](#features)
  - [On-screen Controls](#on-screen-controls)
  - [Overlay](#overlay)
  - [Items](#items)
  - [Party & Boxes](#party--boxes)
- [Responsive Layout](#responsive-layout)
- [Notes](#notes)
- [Demos](#demos)

## Built On

Kanto Companion Lite is a mod for [Gen1Recomp](https://github.com/bryanthaboi/gen1recomp), a native LÖVE2D recreation of Pokémon Red and Blue that has since grown to also run Pokémon Gold.

The companion runs directly inside the recomp and can be installed through its built-in mod manager (F10 in-game), as described in the Gen1Recomp [README](https://github.com/bryanthaboi/gen1recomp#modding).

Kanto Companion Lite works the same way on both generations — the overlay, controls, and interfaces described below apply equally whether you're playing Red, Blue, or Gold. A couple of small touches are Gold-specific and called out where relevant.

Kanto Companion Lite does not ship with the original game's ROM or decompiled game assets.

## Features

### On-screen Controls

Kanto Companion Lite provides touch-friendly controls for accessing its features without relying on a keyboard or mouse.

Three buttons are available in the bottom-right area of the game:

- **Party** — Opens the Party / Boxes interface
- **Backpack** — Opens the Items interface
- **Toggle** — Shows or hides the live companion overlay

The Items and Party / Boxes interfaces pause the game while open. They can be closed using the X button, the corresponding control button, or the Android back button.

### Overlay

The companion overlay provides information that would otherwise require checking multiple in-game menus.

#### Party

Displays information about your current party, including:

- Pokémon sprite
- HP and animated HP bar
- Level
- XP required for the next level
- Status condition
- Types
- Moves and PP

The Pokémon currently active in battle is highlighted.

#### Trainer & Route

Displays trainer and progression information such as:

- Money
- Play time
- Badges (on Gold, both your Johto and, once earned, Kanto badge counts are shown)
- Pokédex progress
- Route information
- Wild Pokémon encounters
- Encounter percentages
- Level ranges
- Encounter sprites

On Gold, wild encounters that change with the time of day are broken out into separate morning, day, and night listings, so you can see exactly what's available right now.

During battle, the panel changes into a battle-focused readout, including the opposing trainer's name and full team where applicable.

#### Battle Information

During battles, the companion can provide:

- Recommended moves ranked by effectiveness
- STAB information
- Enemy super-effective threats
- Speed comparison
- Live catch probabilities during wild encounters
- Catch probabilities adjusted for the target's current HP and status

### Items

The Items interface allows items to be moved between your Bag and PC using touch controls.

**Interactions:**
- Drag an item to the other side
- Or tap an item and then tap its destination

**Features:**
- Sort by Type, A–Z, or Quantity
- Save the Bag's ordering to make the arrangement persistent in-game
- PC ordering remains controlled by the game and is therefore browsing-only
- Invalid destinations are clearly indicated, including full bags, full PCs, and maximum stack limits
- Scroll through lists using the scrollbar on the edge of the panel

**Layout Adaptation:**
The layout adapts automatically to the available space:

- **Landscape:** Bag and PC are displayed side by side
- **Portrait:** Bag and PC are arranged vertically

### Party & Boxes

Manage your party and PC boxes directly through a touch-based interface.

**Supported Actions:**
- Depositing Pokémon
- Withdrawing Pokémon
- Moving Pokémon between boxes
- Rearranging the party
- Swapping Pokémon between occupied slots
- Switching between all 12 PC boxes

**Game Rules:**
The interface enforces the game's party and box rules:

- Party capacity is limited to 6 Pokémon
- Each PC box holds up to 20 Pokémon
- Your last Pokémon cannot be deposited
- The party cannot be left without a healthy Pokémon
- Swapping a Pokémon with a healthy Pokémon is permitted

**Movement Mechanics:**
Pokémon can be moved by grabbing them and dropping them onto:

- An empty slot
- An occupied slot (swaps the Pokémon)
- A PC box tab

## Responsive Layout

The interface is designed around the available game viewport rather than relying on a single fixed device resolution.

### Landscape

Panels make use of the additional horizontal space:

- Party and Trainer/Route information can appear side by side
- Items use a Bag / PC split layout
- Party and PC boxes use a side-by-side layout

### Portrait

The interface reorganizes itself vertically to remain usable on narrower screens.

The overlay displays one primary panel at a time and can be navigated by swiping horizontally.

Depending on the current game state, available pages include:

- Party
- Trainer
- Route
- Items
- Battle

Page indicators show the current position.

The Party page uses a compact two-column layout. Move information is condensed to current/max PP at narrow widths, while PP indicators retain matchup-based highlighting so useful moves remain immediately visible.

### Touch-First Design

Kanto Companion Lite is designed specifically around touch interaction.

**Does NOT depend on:**
- Keyboard shortcuts
- Mouse-wheel scrolling
- Right-click actions
- Desktop cursor behavior

**Built around:**
- Tapping
- Dragging
- Swiping
- Touch-based scrolling

This allows the companion to function naturally on Android devices without requiring desktop-style input.

## Notes

Kanto Companion Lite ships without the game's original assets.

Game sprites and other required visual data are obtained from the user's existing Gen1Recomp installation at runtime, for whichever supported game you're playing. The interface uses LÖVE's built-in font.

Where the built-in font does not contain certain symbols, such as gender symbols or specific battle glyphs, safe text equivalents are used.

## Demos

🎥 [Demos](https://github.com/redelpedron/Kanto-Companion-Lite/releases/tag/demos)

