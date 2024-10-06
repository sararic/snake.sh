#!/bin/bash


############ --- initializing the terminal --- ############


# flush the screen, hide cursor and input
printf "\033[?25l\033[0;0H\0337\033[J"
stty -echo
# at the end, flush, go to 0, show cursor and input
trap "printf '\033[0;0H\033[J\0338\033[?25h'; stty echo; exit"\
        EXIT HUP INT TERM
# get terminal dimensions: W, H
printf "\033[999;999H\033[6n"
read -d R s
IFS=';'
read -r H W <<< "${s:2}"

# initialize RNG
RANDOM=$(( $(date +%s) % 32768 ))


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
growingFlag=0 # whether the snake is growing

# screen buffer:
declare -a buffer
for ((i=0; i<W*H; i++)); do
    buffer[i]=0
done
# snake segments x positions
declare -a snakeX=( $(( W/2 - 1 )) $(( W/2 )) $(( W/2 + 1 )) )
# snake segments y positions
declare -a snakeY=( $(( H/2 )) $(( H/2 )) $(( H/2 )) )
foodX=0 # food x
foodY=0 # food y

keystroke= # pressed key. 


############ --- defining functions --- ############


output(){
    #output x y c: output character c at position x,y
    printf "\033[%d;%dH%s" "$(($2+1))" "$(($1+1))" "$3" 2>/dev/null
}

place_food(){
    # select a random cell that is not occupied by the snake
    r=$(( RANDOM % (W*H - length) ))
    q=0
    p=0
    while [ $p -lt $r ] || [[ ${buffer[q]} -eq 1 ]]; do
        ((p += 1 - buffer[q]))
        ((q++))
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
        A) if [ $direction != down ]; then direction=up; fi;;
        B) if [ $direction != up ]; then direction=down; fi;;
        C) if [ $direction != left ]; then direction=right; fi;;
        D) if [ $direction != right ]; then direction=left; fi;;
        *);;
    esac
}

move_snake(){
    # with each move, the frame index increments, and
    # the tail of the snake becomes the new head. In pseudo-code:
    # segments[current tail] = segments[current head] + increment.
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
    if [ ${snakeX[curHead]} -lt 0 ]\
        || [ ${snakeY[curHead]} -lt 0 ]\
        || [ ${snakeX[curHead]} -ge $W ]\
        || [ ${snakeY[curHead]} -ge $H ]\
        || [[ ${buffer[snakeY[curHead]*W + snakeX[curHead]]} -eq 1 ]]
    then
        gameOverFlag=1
    fi
}

frame(){
    # to be executed every frame
    if [ ${snakeX[curHead]} -eq $foodX ]\
        && [ ${snakeY[curHead]} -eq $foodY ]
    then
        ((growingFlag++))
        place_food
    fi

    if [ $growingFlag -ne 0 ] && [ $curTail -eq 0 ]; then
    # we only increment the length of the snake when the frame index hits
    # 0 to avoid issues with addressing array entries that don't exist.
        ((length += growingFlag))
        growingFlag=0
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
    curHead=$(( (prevHead + 1) % length ))

    parse_input
    move_snake
    check_collision

    # print the new head    
    output ${snakeX[prevHead]} ${snakeY[prevHead]} o
    output ${snakeX[curHead]} ${snakeY[curHead]} @
    buffer[snakeY[curHead]*W + snakeX[curHead]]=1
}


############ --- main loop --- ############


place_food
while true
do
    if [ $gameOverFlag -ne 0 ]; then
        if [ $(( length - 3 )) -gt $highScore ]; then
            highScore=$(( length - 3 ))
            sed -i -e "s/^highScore=[0-9]\+/highScore=$highScore/" "$0"
        fi
        output $((W/2 - 6)) $((H/2-1)) " GAME OVER!! "
        output $((W/2 - 6)) $((H/2)) " Score: $(( length - 3 )) "
        output $((W/2 - 6)) $((H/2+1)) " High-score: $highScore "
        read -n1 _
        exit
    else
        frame
        read -t $deltat -N3 keystroke
        # implement a pause button (space bar)
        if [ "$keystroke" = ' ' ]; then read -n1 _; fi
    fi
done

