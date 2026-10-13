[README.md](https://github.com/user-attachments/files/33386484/README.md)
# AmmoCount

A small Hunter-only addon for WoW Forever that shows how much ammo is in your quiver or ammo pouch, right on the bag's icon.

The number is drawn as **current over maximum**, one above the other (for example, 1917 over 2000), and the current count changes color as you run low:

| Color  | Meaning (default)            |
| ------ | ---------------------------- |
| White  | Plenty of ammo (over 50% full) |
| Yellow | Getting low (50% full or less) |
| Red    | Very low (20% full or less)    |

## Features

- Shows current / max ammo over the quiver or ammo pouch icon in your bag bar.
- Color-coded count: white, yellow, then red as you run low.
- Hunters only. On any other class the addon does nothing.
- Only appears if you actually have a quiver or ammo pouch equipped. If you have two, each shows its own count.
- Simple settings window, no commands needed.

## Install

1. Download and unzip `AmmoCount.zip`.
2. Copy the `AmmoCount` folder into your game's AddOns folder:
   `World of Warcraft/_classic_/Interface/AddOns/`
   (use the folder that matches your WoW Forever install if yours is named differently).
3. Make sure you end up with `Interface/AddOns/AmmoCount/AmmoCount.toc`, not a folder nested inside another folder.
4. Start the game, or type `/reload` if you're already logged in.
5. At the character select screen, check that **AmmoCount** is enabled in the AddOns list.

## Configure

Type `/ammo` to open the settings window. You can also open it from **Game Options > AddOns > AmmoCount**.

- **When do the numbers change color?** Set the percentage at which the count turns yellow and red. Red can never be higher than yellow. The legend underneath updates as you change the values.
- **Number size:** Make the numbers bigger or smaller (8 to 24). The max number below is always 2 smaller than the current count.
- **Hide the game's own ammo number:** See the section below.

Click an arrow to change a value by one, or hold **Shift** while clicking for a bigger step. Changes apply immediately, so you can watch your bag icon as you adjust. **Reset defaults** is in the bottom bar.

### Commands (optional)

| Command                | What it does                                 |
| ---------------------- | -------------------------------------------- |
| `/ammo`                | Open the settings window                     |
| `/ammo yellow <pct>`   | Set the yellow limit (% full)                |
| `/ammo red <pct>`      | Set the red limit (% full)                   |
| `/ammo size <8-24>`    | Set the number size                          |
| `/ammo blizz on`/`off` | Show (`on`) or hide (`off`) the game's own ammo number |
| `/ammo reset`          | Restore defaults                             |
| `/ammo debug`          | Show what the addon sees in your bags (useful when asking for help) |

## The Blizzard ammo number bug

WoW Forever's default UI also shows an ammo count on the bag bar. It's supposed to appear on your quiver or ammo pouch, but currently it bugs out and appears on the **main backpack** instead. If you also have the empty-bag-slots count turned on, the two numbers overlap on the backpack. The game's number is also just a plain count, with no max and no color change, and there is no setting to turn it off.

**What AmmoCount does about it:**

- It hides the game's ammo number on the backpack.
- It also hides the game's number on any bag button that holds a quiver or ammo pouch, since AmmoCount's own display replaces it.
- It does not touch your empty-bag-slots (free slots) number.

Because it works this way, nothing needs to change if Blizzard fixes the bug and moves the number to the right bag. AmmoCount's display will still be the only one on the quiver, and the backpack stays clean.

If you'd like the game's number back, untick **Hide the game's own ammo number** in the settings window (or type `/ammo blizz on`).

## Troubleshooting

- **Nothing shows up:** Check the addon is enabled in the AddOns list, that you're playing a Hunter, and that a quiver or ammo pouch is equipped in a bag slot. Ammo sitting only in the ammo slot isn't counted.
- **`/ammo` does nothing:** The addon isn't loading. Check the folder location and that it's enabled.
- **Numbers still missing:** Type `/ammo debug` and check that your quiver is detected and a bag button is found. If no bag button is found (for example with a bag addon like Bagnon or ElvUI), the addon shows the count in a small box instead. You can move it by holding **Shift** and dragging.
- **A red error appears in chat:** AmmoCount prints errors once so they're easy to spot. Include the text if you ask for help.

## Notes

- Counts ammo inside the quiver or pouch only (not the equipped ammo slot).
- Max ammo is the bag's slot count times the ammo stack size.
- Built for interface version 16001.
