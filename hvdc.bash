# -----------------------------------------------------------------------------
#                                                                             #
#                    /!\ HIGH VOLTAGE /!\ HIGH VOLTAGE /!\                    #
#              /\      __     .   .   .  .__  .____ .___       /\             #
#             / /     |  \   / \  |\  | /     |     |   \     / /             #
#            / /___   |   | |   | | \ | |     |     |   |    / /___           #
#           /___  /   |   | |___| |  \| | --. |--   |___/   /___  /           #
#              / /    |   | |   | |   | |   | |     |  \       / /            #
#             / /     |__/  |   | |   | \___. |____ |   \     / /             #
#             \/                                              \/              #
#                    /!\ HIGH VOLTAGE /!\ HIGH VOLTAGE /!\                    #
#                                                                             #
# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

### Set in your environment to the bg colour of your terminal (e.g. "black"),
#   or to "reset" for a default transparent background.
export HV_BG=${HV_BG:-reset}

### Set in your environment to temporarily disable fancy printing.
# export HV_DISABLE=true

# -----------------------------------------------------------------------------
# Setup
# -----------------------------------------------------------------------------

unset -v HV_LOADED

# Requires bash 4+
if (( ${BASH_VERSINFO[0]} < 4 )); then
  return 69
fi

# Get colour depth of terminal
if TERM_COLOURDEPTH="$(tput -T"$TERM" colors 2>/dev/null ||
                       tput -T"$TERM" Co 2>/dev/null)" \
  && [[ $TERM_COLOURDEPTH -ge 16 ]]
then
  export TERM_COLOURDEPTH
else
  export HV_DISABLE=1
fi

# -----------------------------------------------------------------------------

# Usage:
#   hv::esc brightred
#   hv::esc bold bgblue black
#   hv::esc reset
hv::esc()
{
  [[ -n $HV_DISABLE ]] && return 78

  # Associative arrays in Bash have drawbacks, but we can search the keys for a
  # $string by testing ${!array[@]} *and* easily access the matching value via
  # ${array[$string]}, which would be much less trivial using an indexed array.
  local -A colours=([bla]=0  [red]=1 [gre]=2 [yel]=3
                    [blu]=4  [mag]=5 [cya]=6 [whi]=7
                    [def]=9 )
  local -A attribs=([bol]=1  [ita]=3  [ul]=4 [bli]=5 [inv]=7
                    [rev]=7  [und]=4 ) # <- optional aliases

  local regex_col="(br(ight)?)?(bla(ck)?|red|gre(en)?|yel(low)?|blu(e)?|mag(enta)?|cya(n)?|whi(te)?|def(ault)?)"
  local regex_att="^(bold|ital(ic)?|u(l|nder.*)|blink|(inv|rev)(erse)?)"

  local _fg _bg _attr _reset

  while [[ $# -gt 0 ]]; do
    if [[ $1 == "reset" || $1 == "bgreset" ]]; then
      _reset=$'\e[0m'
      shift
    elif [[ $1 =~ ^bg${regex_col} ]]; then
      _bg=${colours[${BASH_REMATCH[3]:0:3}]}
      if [[ ${BASH_REMATCH[1]} =~ br(ight)? ]]; then
        _bg="10${_bg}"
      else
        _bg="4${_bg}"
      fi
    elif [[ $1 =~ ^${regex_col} ]]; then
      _fg=${colours[${BASH_REMATCH[3]:0:3}]}
      if [[ ${BASH_REMATCH[1]} =~ br(ight)? ]]; then
        _fg="9${_fg}"
      else
        _fg="3${_fg}"
      fi
    elif [[ $1 =~ ${regex_att} ]]; then
      _attr+="${_attr+;}${attribs[${BASH_REMATCH[1]:0:3}]}"
    else
      printf >&2 "cannot parse input: %s\n" "$1"
      return 1
    fi
    shift
  done

  local sequence="${_attr+$_attr;}${_fg+$_fg;}${_bg+$_bg;}"
  [[ -n $_reset ]] && printf "%b" "${_reset}" 
  [[ -n $sequence ]] && printf "\e[%sm" "${sequence%;}"
  return 0
}

# Usage:
#   hv::print <colour args> -- "text"
hv::print()
{
  local args=()
  while [[ $# -gt 1 ]]; do
    if [[ $1 == "--" ]]; then
      shift
      break
    elif [[ $# -eq 1 ]]; then
      local text="$1"
      break
    else
      args+=("$1")
      shift
    fi
  done

  local text="$@"

  set -- "${args[@]}"

  hv::esc "$@" || return
  printf "%b" "$text"
  hv::esc reset
}

# Usage:
#   hv::chevron -f <fg_colour> -b <bg_colour> [-s <colour>] [-alnt] [--] "text"
# Options:
#   -a: Print arrowhead-style (i.e. w/ notch at start)
#   -l: Left-pointing chevron
#   -n: Print trailing newline
#   -t: Attempt to transition from previous chevron
#   -s: Transition from previous chyron with a thin <colour> separator
hv::chevron()
{
  [[ -n $HV_DISABLE ]] && return 78

  local arrow=false
  local direction=right
  local newline=false
  local transition=false
  local same=false

  # Initialize variables locally so we can use `getopts` inside a function.
  local OPT OPTIND OPTARG

  while getopts :f:b:s:alnt OPT; do
    case $OPT in
      f)  fg=$OPTARG
          ;;
      b)  bg=$OPTARG
          ;;
      s)  same=true
          sep_fg=$OPTARG
          ;;
      a)  arrow=true
          ;;
      l)  direction=left
          ;;
      n)  newline=true
          ;;
      t)  transition=true
          ;;
    '?')  printf >&2 "invalid option -- -%s\n" "$OPTARG"
          return 64
          ;;
    esac
  done
  
  # Remove options, leave arguments.
  shift $(( OPTIND - 1 ))

  local text="$@"

  # Start fresh.
  hv::esc reset

  # If `-n` is the only argument, print a newline and return immediately.
  if [[ $newline == true && $# -eq 0 ]]; then
    printf "\n"
    return
  fi

  # Easier than copying and pasting the Unicode characters every time.
  local arrow_left=""
  local arrow_right=""

  local sep_left=""
  local sep_right=""

  if [[ $same == true ]]; then
    transition=true
    bg=$HV_CHEVRON_OLDBG
  fi

  if [[ $direction == "right" ]]; then
    if [[ $transition == "true" && -n $HV_CHEVRON_OLDBG ]]; then
      # Backspace, then overprint last char of last chevron.
      hv::print reset -- $'\b'
      if [[ $same == true ]]; then
        hv::print "${sep_fg:-$HV_CHEVRON_OLDFG}" "bg${bg}" -- "$sep_right"
      else
        hv::print "$HV_CHEVRON_OLDBG" "bg${bg}" -- "$arrow_right"
      fi
    elif [[ $arrow == "true" ]]; then
      # Print a transparent "notch".
      hv::print "$bg" "bg${HV_BG}" inverse -- "$arrow_right"
    fi

    hv::print "$fg" "bg${bg}" -- " $text "
    hv::print "$bg" "bg${HV_BG}" -- "$arrow_right"
  elif [[ $direction == "left" ]]; then
    if [[ $transition == "true" && -n $HV_CHEVRON_OLDBG ]]; then
      if [[ $same == true ]]; then
        hv::print "${sep_fg:-$HV_CHEVRON_OLDFG}" "bg${bg}" -- "$sep_left"
      else
        hv::print "$bg" "bg${HV_CHEVRON_OLDBG}" -- "$arrow_left"
      fi
    else
      # Print leading arrowhead
      hv::print "$bg" "bg${HV_BG}" -- "$arrow_left"
    fi

    hv::print "$fg" "bg${bg}" -- " $text "

    if [[ $arrow == "true" ]]; then
      # Print a transparent "notch".
      hv::print inverse "$bg" "bg${HV_BG}" -- "$arrow_left"
    fi
  fi

  if [[ $newline == "true" ]]; then
    unset -v HV_CHEVRON_OLDBG
    hv::print reset -- "\n"
  else
    export HV_CHEVRON_OLDFG=$fg
    export HV_CHEVRON_OLDBG=$bg
  fi
}

# Usage:
#   hv::banner <colour> "1st chevron" ["2nd chevron" ["3rd chevron" ...]]
hv::banner()
{
  [[ -n $HV_DISABLE ]] && return 78

  local colour="$1"; shift

  # remove empty arguments
  local _v _vv=()
  for _v in "$@"; do [[ -n $_v ]] && _vv+=("$_v"); done
  set -- "${_vv[@]}"

  while true; do
    hv::chevron -f "bright$colour" -b "brightblack" -- "$1"
    shift; (($#)) || break

    hv::chevron -t -f "black" -b "$colour" -- "$1"
    shift; (($#)) || break

    hv::chevron -t -f "black" -b "bright$colour" -- "$1"
    shift; (($#)) || break

    while (($#)); do
      hv::chevron -t -s "$colour" -f "black" -- "$1"
      shift
    done

    shift $#; break
  done

  hv::chevron -n
}

hv::error()
{
  if [[ -z $HV_DISABLE && -t 1 ]]; then
    hv::banner red "$1" "$2" "$3"
  else
    printf "%s\n" "${2:+$1: }${2:-$1}${3:+: $3}"
  fi
} >&2

# -----------------------------------------------------------------------------

export HV_LOADED=${BASH_SOURCE[0]}

unset -v HV_LASTCHEV_BG
