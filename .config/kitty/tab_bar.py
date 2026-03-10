import socket
from kitty.fast_data_types import Screen, get_options
from kitty.tab_bar import (
    DrawData, ExtraData, TabBarData,
    as_rgb, draw_title, draw_tab_with_powerline
)
from kitty.utils import color_as_int
from kitty.boss import get_boss

opts = get_options()

def get_ssh_hostname():
    """Attempt to extract the current hostname from the active kitty window title."""
    try:
        boss = get_boss()
        if boss is not None and boss.active_window is not None:
            title = boss.active_window.title
            # Look for a typical user@host pattern in the window title
            if "@" in title:
                host_part = title.split("@", 1)[1]
                # Strip out trailing paths, spaces, or terminal bell characters
                host = host_part.split(":")[0].split(" ")[0].split("\x07")[0]
                return host
    except Exception:
        pass
    
    # Fallback to local machine hostname
    return socket.gethostname().split('.')[0]

def draw_tab(
    draw_data: DrawData, screen: Screen, tab: TabBarData,
    before: int, max_title_length: int, index: int, is_last: bool,
    extra_data: ExtraData
) -> int:
    # Colors
    active_bg = as_rgb(color_as_int(draw_data.active_bg))
    active_fg = as_rgb(color_as_int(draw_data.active_fg))
    inactive_fg = as_rgb(color_as_int(draw_data.inactive_fg))
    inactive_bg = as_rgb(color_as_int(draw_data.inactive_bg))
    white = as_rgb(color_as_int(opts.color15))
    lighter_gray = as_rgb(0x3a3a3a)

    # 1. Always draw the white separator between tabs
    if index > 1:
        screen.cursor.fg = white
        screen.cursor.bg = inactive_bg
        screen.draw('  ')

    if tab.is_active:
        if index == 1: 
            screen.cursor.fg = active_bg
            screen.cursor.bg = active_bg
            screen.draw('')
        else:
            # Active Tab Head: Grey wedge on Green background
            screen.cursor.fg = inactive_bg
            screen.cursor.bg = active_bg
            screen.draw('')
        
        # Body
        screen.cursor.fg = active_fg
        screen.cursor.bg = active_bg
        screen.draw(' ')
        draw_title(draw_data, screen, tab, index)
        screen.draw(' ')
        
        # Active Tab Tail: Green wedge on Grey background
        screen.cursor.fg = active_bg
        screen.cursor.bg = inactive_bg
        screen.draw('')
    else:
        if index == 1:
            screen.cursor.fg = lighter_gray
            screen.cursor.bg = inactive_bg
            screen.draw('')

        # Body
        screen.cursor.bg = inactive_bg
        screen.cursor.fg = inactive_fg
        screen.draw(' ')
        draw_title(draw_data, screen, tab, index)
        screen.draw(' ')

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
        # Paint the remaining empty bar with firm background color
        gap = screen.columns - screen.cursor.x
        if gap > 0:
            screen.cursor.bg = inactive_bg
            screen.draw(' ' * gap)
        return
        
    separator = ""
    status_text = f" {hostname} "
    cells_needed = len(status_text) + 1
    
    # Calculate available space between the last tab and the right edge
    gap = screen.columns - screen.cursor.x - cells_needed
    
    if gap > 0:
        # Fill the intermediate empty space with the firm background color
        screen.cursor.bg = inactive_bg
        screen.draw(' ' * gap)
    elif gap < 0:
        return # Tab bar is too crowded, skip right status
        
    # Match the right status colors to the active tab's colors
    fg = as_rgb(color_as_int(draw_data.active_fg))
    bg = as_rgb(color_as_int(draw_data.active_bg))
    
    # Draw left-pointing powerline separator
    screen.cursor.fg = bg
    screen.cursor.bg = inactive_bg
    screen.draw(separator)

    # Draw the hostname text
    screen.cursor.fg = fg
    screen.cursor.bg = bg
    screen.draw(status_text)
