#!/bin/bash

############ --- checking dependencies --- ############


# check if running in a terminal, with both stdin and stdout
if [ ! -t 0 ] || [ ! -t 1 ]; then
    echo "This script must be run in a terminal" >&2
    exit 1
fi

# bash version >= 4.4
req_major=4
req_minor=4
IFS='.'
read cur_major cur_minor <<< "${BASH_VERSION%%[^0-9.]*}"
if     [[ $cur_major -lt $req_major ]]\
    || [[ $cur_major -eq $req_major && $cur_minor -lt $req_minor ]]; then
    echo "This script requires Bash version >= $req_major.$req_minor" >&2
    exit 1
fi

# check if a command is available
check_dependency(){
    if ! type "$1" >/dev/null 2>&1; then
        echo "This script requires $1" >&2
        exit 1
    fi
}

check_dependency stty
check_dependency sed


############ --- initializing the terminal --- ############


# flush the screen, hide cursor and input
printf "\033[?25l\033[0;0H\0337\033[J"
stty -echo
# at the end, flush, go to 0, show cursor and input
trap "printf '\033[0;0H\033[J\0338\033[?25h'; stty echo; exit"\
        EXIT HUP INT TERM

# get terminal dimensions: W, H
printf "\033[999;999H\033[6n"
read -d R -t 1 s
# if s is empty, ANSI escape codes are not supported
if [ -z "$s" ]; then
    echo "This terminal does not support ANSI escape codes" >&2
    exit 1
fi
# parse the dimensions
IFS=';'
read -r H W <<< "${s:2}"

# initialize RNG
RANDOM=$(( ($$ + $SECONDS) % 32768 ))


############ --- program variables --- ############


highScore=0 # don't edit this, you cheater! >:(
length=3 # snake length
direction=left # direction of motion
deltat=0.1 # 1/speed

# We don't shift all the snake segments with every frame,
# instead we keep track of the index corresponding to the head,
# tail, and previous head:
curTail=0
prevHead=1
curHead=2

gameOverFlag=0
foodCache=0 # consumed food that hasn't been added to the snake yet

# screen buffer:
declare -a buffer
for ((i=0; i<W*H; i++)); do
    buffer[i]=0
done
# snake segments x positions
declare -a snakeX=( $(( W/2 - 1 )) $(( W/2 )) $(( W/2 + 1 )) )
# snake segments y positions
declare -a snakeY=( $(( H/2 ))     $(( H/2 )) $(( H/2 ))     )
foodX=0 # food x
foodY=0 # food y

keystroke= # pressed key. 


############ -- draw edge of the screen --- ############


output(){
    #output x y c: output character c at position x,y
    printf "\033[%d;%dH%s" "$(($2+1))" "$(($1+1))" "$3" 2>/dev/null
}

output $((W/2 -27)) 0 "USE ARROW KEYS TO MOVE. USE SPACE TO PAUSE AND RESUME."

for ((i=0; i<W; i++)); do
    output $i 2   '█'
    output $i $((H-3)) '█'
done
for ((i=2; i<H-2; i++)); do
    output 0   $i '█'
    output $((W-1)) $i '█'
done

output $((W -20)) $((H-1)) "HIGH-SCORE: $highScore"
output 2 $((H-1)) "SCORE: $(( length - 3 ))"


############ --- define game functions --- ############


update_score(){
    output 2 $((H-1)) "SCORE: $(( length + foodCache - 3 ))"
    if [ $(( length + foodCache - 3 )) -gt $highScore ]; then
        output $((W -20)) $((H-1)) "HIGH-SCORE: $(( length + foodCache - 3 ))"
    fi
}


place_food(){
    # select a random cell that is not occupied by the snake or the frame
    r=$(( RANDOM % ((W-2)*(H-6) - length) ))
    q=$(( W*3 + 1 )) # start searching after the top and left edges
    for (( p=0; p < r; p++ )); do
        ((q++))
        while  [[ ${buffer[q]} -eq 1 ]]\
            || [[ $((q % W)) -eq 0 ]]\
            || [[ $((q % W)) -eq $((W-1)) ]]
        do
            ((q++))
        done
    done
    foodX=$((q % W))
    foodY=$((q / W))
    output $foodX $foodY $
}

parse_input(){
    # parse keyboard input. Arrow keys take values in:
    # \033[A : up arrow
    # \033[B : down arrow
    # \033[C : right arrow
    # \033[D : left arrow
    if [[ ! ${keystroke} =~ $'\033['[ABCD] ]]; then return; fi;
    case ${keystroke:2} in
        A) if [ $direction != down  ]; then direction=up;    fi;;
        B) if [ $direction != up    ]; then direction=down;  fi;;
        C) if [ $direction != left  ]; then direction=right; fi;;
        D) if [ $direction != right ]; then direction=left;  fi;;
        *);;
    esac
}

move_snake(){
    # with each move, the frame index increments, and
    # we replace the new head. In pseudo-code:
    # segments[current head] = segments[previous head] + increment.
    case $direction in
        up)
            snakeY[curHead]=$(( snakeY[prevHead] - 1 ));
            snakeX[curHead]=${snakeX[prevHead]};;
        down)
            snakeY[curHead]=$(( snakeY[prevHead] + 1 ));
            snakeX[curHead]=${snakeX[prevHead]};;
        right)
            snakeX[curHead]=$(( snakeX[prevHead] + 1 ));
            snakeY[curHead]=${snakeY[prevHead]};;
        left)
            snakeX[curHead]=$(( snakeX[prevHead] - 1 ));
            snakeY[curHead]=${snakeY[prevHead]};;
        *);;
    esac
}

check_collision(){
    if     [  ${snakeX[curHead]} -lt 1  ]\
        || [  ${snakeY[curHead]} -lt 3  ]\
        || [  ${snakeX[curHead]} -ge $((W-1)) ]\
        || [  ${snakeY[curHead]} -ge $((H-3)) ]\
        || [[ ${buffer[snakeY[curHead]*W + snakeX[curHead]]} -eq 1 ]]
    then
        gameOverFlag=1
    fi
}

frame(){
    # to be executed every frame
    if     [ ${snakeX[curHead]} -eq $foodX ]\
        && [ ${snakeY[curHead]} -eq $foodY ]
    then
        ((foodCache++))
        place_food
        update_score
    fi

    if [ $foodCache -ne 0 ] && [ $curTail -eq 0 ]; then
    # we only increment the length of the snake when the tail index hits
    # 0 to avoid issues with addressing array entries that don't exist.
        ((length++))
        ((foodCache--))
    else
        # erase the old tail
        output ${snakeX[curTail]} ${snakeY[curTail]} ' '
        buffer[snakeY[curTail]*W + snakeX[curTail]]=0
        # increment the indices
        ((curTail++))
        ((curTail %= length))
    fi

    # define the new positions for head and previous head
    prevHead=$(( (curTail + length - 2) % length ))
    curHead=$((  (prevHead + 1)         % length ))

    parse_input
    move_snake
    check_collision

    # print the new head    
    output ${snakeX[prevHead]} ${snakeY[prevHead]} o
    output ${snakeX[curHead]}  ${snakeY[curHead]}  @
    buffer[snakeY[curHead]*W + snakeX[curHead]]=1
}


############ --- main loop --- ############


place_food
while true
do
    if [ $gameOverFlag -ne 0 ]; then
        if [ $(( length + foodCache - 3 )) -gt $highScore ]; then
            output $((W/2 - 9)) $((H/2)) " NEW HIGH-SCORE!! "
            highScore=$(( length + foodCache - 3 ))
            sed -i -e "s/^highScore=[0-9]\+/highScore=$highScore/" "$0"
        else
            output $((W/2 - 6)) $((H/2)) " GAME OVER!! "
        fi
        read -n1 _
        exit
    else
        frame
        read -t $deltat -N3 keystroke
        # implement a pause button (space bar)
        if [ "$keystroke" = ' ' ]; then read -n1 _; fi
    fi
done

