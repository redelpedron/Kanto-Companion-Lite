# Kanto Companion Lite (Android fork of matthew.me Kanto Companion)

An in-game companion that loads directly on top of the game to enhance my
playthrough of my childhood favorite game.

This fork is **Android-only**: every control is a touch button, drag, or tap —
there are no keyboard shortcuts and no mouse-wheel dependencies.

> **Fan-made; not affiliated with or endorsed by Nintendo / Game Freak / The Pokémon Company.**

## Table of Contents

- [Built On](#built-on)
- [On-screen buttons](#on-screen-buttons)
- [Overlay](#overlay)
- [Items (Bag ⇄ PC)](#items-bag--pc)
- [Party / Boxes](#party--boxes)
- [Notes](#notes)
- [Demos](#demos)

## Built On

This addon is a mod for [**Gen1Recomp**](https://github.com/bryanthaboi/gen1recomp),
a native LÖVE2D recreation of Pokémon Red and Blue (game data and graphics
are decoded at runtime from a legally-supplied ROM; no ROM or decompiled
assets ship with the base project). Gen1Recomp is where this addon is loaded
and used — install it through Gen1Recomp's mod manager (**F10** in-game) as
described in its own [README](https://github.com/bryanthaboi/gen1recomp#modding).

## On-screen buttons

Three round buttons sit in the bottom-right corner, above the D-pad/A-B controls
(left to right: **Party**, **Backpack**, **Toggle**):

- **Toggle** (bar icon) — shows/hides the live **overlay** (off by default).
- **Backpack** icon — opens the **Items** screen (move items between your Bag
  and the PC).
- **Poké Ball** icon — opens the **Party / Boxes** screen (deposit, withdraw,
  rearrange and swap Pokémon).

Both screens pause the game while open. Tap the **X** in the corner, tap the
same button again, or use the Android **back button** to close.

## Overlay

- **Party** panel — sprite, HP bar (animated), XP-to-next, level, status,
  types, and moves + PP. The mon that's out in battle is highlighted.
- **Trainer / Route** panel — money, play time, badges, dex, plus route
  encounters (grass/surf with %, level ranges, sprites). During a battle this
  swaps to a battle readout: your best moves ranked by effectiveness + STAB,
  the enemy's super-effective threats, a speed indicator, and — in wild
  battles — live per-ball catch odds at the target's current HP/status.

Layout adapts to orientation:

- **Landscape** — Party on the left, Trainer/Route (or Battle/Items in a
  fight) on the right, side by side.
- **Portrait** — a single full-width panel at a time; swipe left/right to
  page through Party / Trainer / Items / Route (or Battle / Items / Party
  during a fight), with dots showing your position. The Party page here is a
  compact 2-column grid, and move sets are simplified to just current/max PP
  (no room for move names at this width) — each PP value is still colored by
  matchup effectiveness against whatever you're fighting, so the moves worth
  using still stand out at a glance.

The overlay is read-only. Panels scale to your window (designed against
1440p); since the game renders widescreen they sit over the sides of the view.

## Items (Bag ⇄ PC)

- **Drag** an item to the other side, or **tap** it then **tap** the other
  side.
- **Sort** each side by Type / A–Z / Qty (view only). On the **Bag** you can
  **Save order** to make it stick in-game; the in-game **PC is always A–Z**, so
  its sort is browsing-only.
- A destination that can't accept the item turns **red** with the reason
  (bag/PC full, stack maxed).
- **Scroll** a list by dragging the scrollbar on its right edge.
- **Landscape:** Bag and PC panels split the screen 50/50. **Portrait:** they
  stack top/bottom instead of squeezing side by side.

## Party / Boxes

- **Left/top:** your party (up to 6) with HP. **Right/bottom:** a rail of all
  12 boxes plus the selected box as a sprite grid. Tap a box tab to switch.
- **Grab** a Pokémon and drop it on a slot or a box tab to deposit / withdraw
  / move between boxes. Dropping onto an **occupied** slot **swaps** the two.
- Rules are enforced: boxes hold 20, the party holds 6, you can't deposit your
  last Pokémon, and the party is **never left without a healthy Pokémon** (a
  swap that brings a healthy one in is fine).
- **Landscape:** party and boxes split the screen 50/50. **Portrait:** they
  stack top/bottom instead of squeezing side by side.

## Notes

- Ships no game assets: sprites and the badge sheet are read from your own game
  install at runtime, and it uses LÖVE's built-in font. A few symbols the font
  lacks (♀/♂, some battle glyphs) are shown as safe text equivalents.
- Android-only fork: keyboard shortcuts, mouse-wheel scrolling/quantity
  adjustment, right-click-to-cancel, and desktop cursor handling have all been
  removed in favor of touch-only controls.

## Demos

- 🎥 [Demos](https://github.com/redelpedron/Kanto-Companion-Lite/releases/tag/demos)