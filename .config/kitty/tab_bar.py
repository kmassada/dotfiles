import contextlib
import socket

from kitty.boss import get_boss
from kitty.fast_data_types import Screen, get_options
from kitty.tab_bar import (
    DrawData,
    ExtraData,
    TabBarData,
    as_rgb,
    draw_title,
)
from kitty.utils import color_as_int

opts = get_options()


def get_ssh_hostname() -> str:
    """Attempt to extract the current hostname from the active kitty window or process."""
    with contextlib.suppress(Exception):
        boss = get_boss()
        if boss is not None and boss.active_window is not None:
            win = boss.active_window

            # 1. Inspect active foreground processes for ssh / kitten ssh
            if hasattr(win, "child") and win.child is not None:
                fg_procs = getattr(win.child, "foreground_processes", []) or []
                for proc in fg_procs:
                    cmdline = (
                        proc.get("cmdline", [])
                        if isinstance(proc, dict)
                        else getattr(proc, "cmdline", [])
                    )
                    if not cmdline:
                        continue
                    for idx, arg in enumerate(cmdline):
                        if (arg == "ssh" or arg.endswith("/ssh")) and idx + 1 < len(
                            cmdline
                        ):
                            for next_arg in cmdline[idx + 1 :]:
                                if next_arg.startswith("-") or next_arg == "exec":
                                    continue
                                target = next_arg.split("@")[-1]
                                cleaned = target.split(":")[0].split(".")[0]
                                if cleaned:
                                    return cleaned

            # 2. Inspect active window title (e.g. "Kenneths-Mac-mini: ~", "user@host: ~")
            title = win.title.strip() if win.title else ""
            if title:
                if ":" in title:
                    host_part = title.split(":", 1)[0].strip()
                    if "@" in host_part:
                        host_part = host_part.split("@", 1)[1].strip()
                    cleaned = host_part.split(".")[0].split()[0]
                    if cleaned:
                        return cleaned
                if "@" in title:
                    host_part = title.split("@", 1)[1].strip()
                    cleaned = host_part.split(":")[0].split(".")[0].split()[0]
                    if cleaned:
                        return cleaned

    # Fallback to local machine hostname
    return socket.gethostname().split(".")[0]


def draw_tab(
    draw_data: DrawData,
    screen: Screen,
    tab: TabBarData,
    before: int,
    max_title_length: int,
    index: int,
    is_last: bool,
    extra_data: ExtraData,
) -> int:
    """Draw a single tab with powerline styling and bounded title length."""
    # Colors
    active_bg = as_rgb(color_as_int(draw_data.active_bg))
    active_fg = as_rgb(color_as_int(draw_data.active_fg))
    inactive_fg = as_rgb(color_as_int(draw_data.inactive_fg))
    inactive_bg = as_rgb(color_as_int(draw_data.inactive_bg))
    white = as_rgb(color_as_int(opts.color15))
    lighter_gray = as_rgb(0x3A3A3A)

    # 1. Always draw the white separator between tabs
    if index > 1:
        screen.cursor.fg = white
        screen.cursor.bg = inactive_bg
        screen.draw("  ")

    if tab.is_active:
        if index == 1:
            screen.cursor.fg = active_bg
            screen.cursor.bg = active_bg
            screen.draw("")
        else:
            # Active Tab Head: Grey wedge on Green background
            screen.cursor.fg = inactive_bg
            screen.cursor.bg = active_bg
            screen.draw("")

        # Body
        screen.cursor.fg = active_fg
        screen.cursor.bg = active_bg
        screen.draw(" ")
        draw_title(draw_data, screen, tab, index, max_title_length=max_title_length)
        screen.draw(" ")

        # Active Tab Tail: Green wedge on Grey background
        screen.cursor.fg = active_bg
        screen.cursor.bg = inactive_bg
        screen.draw("")
    else:
        if index == 1:
            screen.cursor.fg = lighter_gray
            screen.cursor.bg = inactive_bg
            screen.draw("")

        # Body
        screen.cursor.bg = inactive_bg
        screen.cursor.fg = inactive_fg
        screen.draw(" ")
        draw_title(draw_data, screen, tab, index, max_title_length=max_title_length)
        screen.draw(" ")

    # Save the cursor position for the end of the tab's clickable area
    end = screen.cursor.x

    if is_last:
        draw_right_status(screen, draw_data)

    return end


def draw_right_status(screen: Screen, draw_data: DrawData) -> None:
    """Draws the hostname block on the far right of the tab bar."""
    inactive_bg = as_rgb(color_as_int(draw_data.inactive_bg))
    hostname = get_ssh_hostname()

    if not hostname:
        gap = screen.columns - screen.cursor.x
        if gap > 0:
            screen.cursor.bg = inactive_bg
            screen.draw(" " * gap)
        return

    separator = ""
    status_text = f" {hostname} "
    cells_needed = len(status_text) + 1

    # Calculate available space between the last tab and the right edge
    gap = screen.columns - screen.cursor.x - cells_needed

    if gap >= 0:
        if gap > 0:
            # Fill intermediate empty space with the firm background color
            screen.cursor.bg = inactive_bg
            screen.draw(" " * gap)

        # Use color5 (purple) for the hostname chip to distinguish it from the active tab
        fg = as_rgb(color_as_int(draw_data.active_fg))
        bg = as_rgb(color_as_int(opts.color5))

        # Draw left-pointing powerline separator
        screen.cursor.fg = bg
        screen.cursor.bg = inactive_bg
        screen.draw(separator)

        # Draw the hostname text
        screen.cursor.fg = fg
        screen.cursor.bg = bg
        screen.draw(status_text)
    else:
        # Tab bar is too crowded for the hostname block.
        # Guarantee all remaining columns are painted with inactive_bg so that
        # window background transparency never bleeds through into the bar.
        remaining = screen.columns - screen.cursor.x
        if remaining > 0:
            screen.cursor.bg = inactive_bg
            screen.draw(" " * remaining)
