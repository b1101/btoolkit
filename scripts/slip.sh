#! /usr/bin/env bash

set -eo pipefail

# Sane defaults in case of not being set in the config / config not existing.

RECORD_PIDFILE="/tmp/slip_record.pid"
PICTURES="$HOME/Pictures"
VIDEOS="$HOME/Videos"

if type xdg-user-dir > /dev/null; then
    PICTURES=`xdg-user-dir PICTURES`
    VIDEOS=`xdg-user-dir VIDEOS`
fi


DMENU_PROMPT="slip"

# Load config.
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/slip/config"
[ -f $CONFIG ] && source $CONFIG

DMENU_CMD="dmenu -f -i -p $DMENU_PROMPT"

# Dmenu prompts.
DMENU_OPTS="screenshot
record
nothing"
DMENU_RECORD_OPTS="stop
nothing"

function usage() {
    echo "  slip [ -h | -v ]"
    echo "      Uploads images taken with ffmpeg via slop to imgur.  Quick video recording."
    echo "      That's all."
    echo ""
    echo "      -h  show this help"
    echo "      -v  show version"
    echo ""
}

# Imgur needs to know what program is using its services.
function curl_imgur() {
    curl -sH "Authorization: Client-ID abd3a90bbfb65e9" "$@"
}

function upload() {
    file="$1"

    if [ -f "$file" ]; then
        curl_imgur -F "image=@$file" "https://api.imgur.com/3/upload"
    else
        echo "File does not exist, what happened?"
    fi
}

function clip_clear() {
    # Clear x cliboard selection.
    xsel -bc    # Ctrl-v / Shift-Insert.
    # xsel -pc  # Middle click.
}

# Run slop and get the geometry line.
function slop_geom() {
    if [ "$1" = "image" ]; then
        slop | sed -n 5p | sed -e s/G=// #-e s/+/\|/ #-e s/+/,/
    elif [ "$1" = "video" ]; then
        slop | sed -n 5p | sed -e s/G=// -e s/+/\|/ -e s/+/,/
    fi
}

# Take the shot (or start the video.)
function shot() {
    if [ "$1" = "image" ]; then
        extension=".png"    # img-2016-16-04-153906.png
        filename="$PICTURES/img-`date +%Y-%d-%m-%H%M%S`$extension"    # .png, .jpg
        maim -g "$2" $filename
        # TODO, do we want more dependencies? (optional dependencies?)
        #ffmpeg -f x11grab -video_size "$2" -i "$DISPLAY+$3" -vframes 1 $filename &> /dev/null
    elif [ "$1" = "video" ]; then
        extension=".mkv"    # vid-2016-16-04-153906.mkv
        filename="$VIDEOS/vid-`date +%Y-%d-%m-%H%M%S`$extension"    # .mkv, .mp4
        ffmpeg -f x11grab -video_size "$2" -framerate 60 -i "$DISPLAY+$3" -c:v libx264 -preset ultrafast $filename &> /dev/null &
        echo "$!" > "$RECORD_PIDFILE"
    fi
}

# Parse x,y -- but also imgur.
function parse() {
    if [ "$1" = "geometryx" ]; then
        awk -F"|" '{ print $1 }' <<< "$2" 
    elif [ "$1" = "geometry+" ]; then
        awk -F"|" '{ print $2 }' <<< "$2"
    elif [ "$1" = "imgur" ]; then
        sed -e 's/.*\"link\":"\([^"]*\).*/\1/' -e 's/\\//g' <<< "$2"
    fi
}

function notify() {
    notify-send -t 5 "slip" "$1"
}

# Delete a file.
function remove() {
    rm "$filename"
}

function main() {
    if [ "$1" = "screenshot" ]; then
        # Clear cliboard before doing anything.
        clip_clear
        # Run slop and get geometry from it.
        # maim naturally supports slop's output coordinates.
        geometry=$(slop_geom "image")
        # Take the shot.
        shot "image" "$geometry"
        # Parse imgur json into link.
        output=$(upload "$filename")
        url=$(parse "imgur" "$output")
        # Notify user that upload has finished.
        notify "$url"
        # Delete the file.
        # remove
        echo "$url"
        echo "$url" | xsel -bi  # Read to clipboard.
        # echo "$url" | xsel -pi  # Read to primary.
    elif [ "$1" = "record" ]; then
        geometry=$(slop_geom "video")
        wxh=$(parse "geometryx" $geometry)
        off=$(parse "geometry+" $geometry)
        shot "video" "$wxh" "$off"
    elif [ "$1" = "stop" ]; then
        # Get pid of ffmpeg process.
        local pid
        pid=$(cat "$RECORD_PIDFILE")
        # Kill ffmpeg (stopping the recording.)
        kill $pid
        # Notify that the recording has finished.
        notify "finished recording."
        # Remove the pid file so that slip can be used as normal again.
        rm "$RECORD_PIDFILE"
        exit 0
    else
        exit 0
    fi
}

# Dependencies.
depends="curl
maim
slop
ffmpeg"
while read line
do
    if ! type $line &> /dev/null ; then
        echo "$line not found, expect unexpected."
    fi
done <<< "$depends"

# Main.
if [ "$1" = "-h" -o "$1" = "--help" ]; then
    usage
    exit 0
elif [ "$1" = "-v" -o "$1" = "--version" ]; then
    echo "Version: $version"
    exit 0
elif [ $# == 0 ]; then
    if [ -a "$RECORD_PIDFILE" ]; then
        main $($DMENU_CMD <<< "$DMENU_RECORD_OPTS")
    else
        main $($DMENU_CMD <<< "$DMENU_OPTS")
    fi
fi
