import contextlib
import socket
from collections.abc import Sequence

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


def extract_host_from_cmdline(cmdline: Sequence[str] | None) -> str | None:
    """Extract destination host from an SSH or kitten ssh process command line."""
    if not cmdline:
        return None

    # 1. First scan for an ssh or kitten invocation
    ssh_idx = -1
    for idx, arg in enumerate(cmdline):
        if arg in ("ssh", "kitten") or arg.endswith(("/ssh", "/kitten")):
            ssh_idx = idx
            break

    if ssh_idx == -1:
        return None

    sub_cmdline = cmdline[ssh_idx + 1 :]

    # 2. Check for '--' delimiter occurring after ssh invocation
    if "--" in sub_cmdline:
        dash_idx = sub_cmdline.index("--")
        if dash_idx + 1 < len(sub_cmdline):
            candidate = sub_cmdline[dash_idx + 1]
            if (
                candidate
                and not candidate.startswith("-")
                and candidate not in ("exec", "sh", "bash", "zsh")
            ):
                return candidate.split("@")[-1].split(":")[0].split(".")[0]

    # 3. Complete set of OpenSSH argument-taking short and long options
    flags_with_val = {
        "-b",
        "-c",
        "-e",
        "-i",
        "-l",
        "-m",
        "-o",
        "-p",
        "-w",
        "-B",
        "-D",
        "-E",
        "-F",
        "-I",
        "-J",
        "-L",
        "-O",
        "-Q",
        "-R",
        "-S",
        "-W",
    }
    skip_next = False
    for arg in sub_cmdline:
        if skip_next:
            skip_next = False
            continue
        if arg in flags_with_val:
            skip_next = True
            continue
        if (
            arg.startswith("-")
            or "=" in arg
            or arg in ("ssh", "exec", "sh", "bash", "zsh")
        ):
            continue
        parts = arg.split("@")[-1].split(":")[0].split(".")[0].split()
        if parts:
            return parts[0]

    return None


def get_ssh_hostname() -> str:
    """Attempt to extract current hostname from active window process or title."""
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
                    host = extract_host_from_cmdline(cmdline)
                    if host:
                        return host

            # 2. Inspect active window title only when structured as user@host
            title = win.title.strip() if win.title else ""
            if title and "@" in title:
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
        draw_right_status(screen, draw_data, tab.is_active)

    return end


def draw_right_status(
    screen: Screen, draw_data: DrawData, last_tab_is_active: bool
) -> None:
    """Draw the hostname chip pinned to the right edge of the tab bar.

    The chip is positioned from the right edge rather than appended after the
    last tab, so a crowded bar can no longer drop it: once the tabs reach the
    edge the chip rewinds over the tail of the last tab instead of vanishing.
    """
    inactive_bg = as_rgb(color_as_int(draw_data.inactive_bg))
    hostname = get_ssh_hostname()

    if not hostname:
        gap = screen.columns - screen.cursor.x
        if gap > 0:
            screen.cursor.bg = inactive_bg
            screen.draw(" " * gap)
        return

    separator = "\ue0b2"
    status_text = f" {hostname} "
    cells_needed = len(status_text) + 1
    start = screen.columns - cells_needed

    if start < 0:
        # Bar is narrower than the chip itself. Paint what is left so window
        # background transparency cannot bleed through into the bar.
        remaining = screen.columns - screen.cursor.x
        if remaining > 0:
            screen.cursor.bg = inactive_bg
            screen.draw(" " * remaining)
        return

    if screen.cursor.x < start:
        # Room to spare: run the ribbon up to where the chip begins.
        screen.cursor.bg = inactive_bg
        screen.draw(" " * (start - screen.cursor.x))
        behind = inactive_bg
    else:
        # Bar is full: rewind over the tail of the last tab. The separator has
        # to sit on that tab's colour, not the ribbon's, or it leaves a notch.
        behind = (
            as_rgb(color_as_int(draw_data.active_bg))
            if last_tab_is_active
            else inactive_bg
        )
        screen.cursor.x = start

    # Use color5 (purple) for the hostname chip to distinguish it from the active tab
    fg = as_rgb(color_as_int(draw_data.active_fg))
    bg = as_rgb(color_as_int(opts.color5))

    # Draw left-pointing powerline separator
    screen.cursor.fg = bg
    screen.cursor.bg = behind
    screen.draw(separator)

    # Draw the hostname text
    screen.cursor.fg = fg
    screen.cursor.bg = bg
    screen.draw(status_text)
