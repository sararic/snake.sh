#!/bin/bash


############ --- initializing the terminal --- ############


# flush the screen, hide cursor and input
printf "\033[?25l\033[0;0H\0337\033[J"
stty -echo
# at the end, flush, go to 0, show cursor and input
trap "printf '\033[0;0H\033[J\0338\033[?25h'; stty echo; exit"\
        EXIT HUP INT TERM
# get terminal dimensions
printf "\033[999;999H\033[6n"
read -d R s
IFS=\;
read -r H W <<< ${s:2}
IFS= #

# initialize RNG
RANDOM=$(( $(date +%s) % 32768 ))


############ --- program variables --- ############


highScore=0 # don't edit this, you cheater! >:(

length=3 # snake length
# We don't shift all the snake segments with every frame,
# instead we keep track of the index corresponding to the head,
# tail, and previous head:
tail=0
head=0
prevHead=0

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

keystroke=$'\033[D' # pressed key. Can take values in:
            # '\033[A' : up arrow
            # '\033[B' : down arrow
            # '\033[C' : right arrow
            # '\033[D' : left arrow
activeKeystroke=$keystroke # active key stroke
                           # (may be different from pressed key if 
                           # illicit move)


############ --- defining functions --- ############


#output x y c: output character c at position x,y
output(){
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
place_food

move_snake(){
    # check if the current key press is an illicit move
    # (snake cannot move backwards)
    case $keystroke in
        $'\033[A')
            if [ $activeKeystroke != $'\033[B' ];
                then activeKeystroke=$keystroke; fi;;
        $'\033[B')
            if [ $activeKeystroke != $'\033[A' ];
                then activeKeystroke=$keystroke; fi;;
        $'\033[C')
            if [ $activeKeystroke != $'\033[D' ];
                then activeKeystroke=$keystroke; fi;;
        $'\033[D')
            if [ $activeKeystroke != $'\033[C' ];
                then activeKeystroke=$keystroke; fi;;
        *);;
    esac
    # with each move, the frame index increments, and
    # the tail of the snake becomes the new head. In pseudo-code:
    # segments[current tail] = segments[current head] + increment.
    case $activeKeystroke in
        $'\033[A')
            snakeY[head]=$(( snakeY[prevHead] - 1 ));
            snakeX[head]=${snakeX[prevHead]};;
        $'\033[B')
            snakeY[head]=$(( snakeY[prevHead] + 1 ));
            snakeX[head]=${snakeX[prevHead]};;
        $'\033[C')
            snakeX[head]=$(( snakeX[prevHead] + 1 ));
            snakeY[head]=${snakeY[prevHead]};;
        $'\033[D')
            snakeX[head]=$(( snakeX[prevHead] - 1 ));
            snakeY[head]=${snakeY[prevHead]};;
        *);;
    esac
}

check_collision(){
    if [ ${snakeX[head]} -lt 0 ]\
        || [ ${snakeY[head]} -lt 0 ]\
        || [ ${snakeX[head]} -ge $W ]\
        || [ ${snakeY[head]} -ge $H ]\
        || [[ ${buffer[snakeY[head]*W + snakeX[head]]} -eq 1 ]]
    then
        gameOverFlag=1
    fi
}

# to be executed every frame
frame(){
    if [ ${snakeX[head]} -eq $foodX ] && [ ${snakeY[head]} -eq $foodY ]
    then
        growingFlag=1
        place_food
    fi

    if [ $growingFlag -eq 1 ] && [ $tail -eq 0 ]; then
    # we only increment the length of the snake when the frame index hits
    # 0 to avoid issues.
        ((length++))
        growingFlag=0
    else
        # erase the old tail
        output ${snakeX[tail]} ${snakeY[tail]} ' '
        buffer[snakeY[tail]*W + snakeX[tail]]=0
        # increment the indices
        ((tail++))
        ((tail %= length))
    fi

    # define the new positions for head and previous head
    prevHead=$(( (tail + length - 2) % length ))
    head=$(( (prevHead + 1) % length ))

    move_snake
    check_collision

    # print the new head    
    output ${snakeX[prevHead]} ${snakeY[prevHead]} o
    output ${snakeX[head]} ${snakeY[head]} @
    buffer[snakeY[head]*W + snakeX[head]]=1
}


############ --- main loop --- ############


while true
do
    if [ $gameOverFlag -eq 1 ]; then
        if [ $(( length - 3 )) -gt $highScore ]; then
            highScore=$(( length - 3 ))
            sed -i -e "s/^highScore=[0-9]\+/highScore=$highScore/" $0
        fi
        output $((W/2 - 6)) $((H/2-1)) " GAME OVER!! "
        output $((W/2 - 6)) $((H/2)) " Score: $(( length - 3 )) "
        output $((W/2 - 6)) $((H/2+1)) " High-score: $highScore "
        read -N 1 _;
        exit
    else
        frame
        read -t 0.1 -N 3 keystroke
        # implement a pause button (space bar)
        if [ "$keystroke" = ' ' ]; then read -N 1 _; fi
    fi
done

