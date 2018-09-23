# wtf.

HV_DIR=${BASH_SOURCE[0]%/*}
HV_DIR=$(cd ${HV_DIR:-.} && pwd -P)
. "$HV_DIR/hvdc.bash" || export HV_DISABLE=true

# -----------------------------------------------------------------------------
# Lesser functions
# -----------------------------------------------------------------------------

# Finds the source of a shell function.
hv::wtf::whence()
(
  # We need to enable advanced debugging behaviour to get function info
  # using only builtins, but it's not for everyday use, so this function is
  # executed in a (subshell) instead of as a { group }.
  shopt -s extdebug

  # Require at least one argument. (We will silently ignore $2 and beyond.)
  [[ $# -gt 0 ]] || return 64

  # With `extdebug` enabled, `declare -F function_name` prints the function
  # name, line number, and source file. We will capture the latter two
  # in BASH_REMATCH with the following regex:
  local regex="^${1}[[:space:]]([[:digit:]]+)[[:space:]](.+)$"

  local location
  if location=$(declare -F "$1") && [[ $location =~ $regex ]]; then
    local source_file=${BASH_REMATCH[2]/#$HOME/$'~'}
    local line_number=${BASH_REMATCH[1]}
  else
    return 66
  fi

  # If the function was declared at the command line, source_file will be
  # "main" (and "the [line number] is not guaranteed to be meaningful").
  # Otherwise, it will be the path to the file where the function was defined.
  ### TODO: Document and handle more edge cases.
  printf "%s:%d" "$source_file" "$line_number"
)

# Return a short description of a command.
hv::wtf::whatis()
{
  local -a results

  if type -P mandb >/dev/null; then
    # Versions of `whatis` distributed with `mandb` support the `-w` switch,
    # which expands globbing characters in the search term, but -- more useful
    # for our purposes -- also returns only exact matches.
    IFS=$'\n' read -ra results -d $'\004' \
      < <(whatis -w "$1" 2>/dev/null)
  else
    # Use `sed` to parse the results from non-mandb `whatis`.
    IFS=$'\n' read -ra results -d $'\004' \
      < <(whatis "$1" 2>/dev/null | sed -nE "/^$1[[:space:](].*/p")
  fi

  [[ ${#results[@]} -gt 0 ]] || return 70

  # Keep only the first result.
  local result=${results[0]}

  # Trim garbage from badly-formed description strings
  local regex='^(.+) co Copyright \[co\]'
  [[ $result =~ $regex ]] && result=${BASH_REMATCH[1]}

  # Keep only the description by removing everything before the separator.
  local desc=${result#* - }

  printf "$desc"
}

# Return a short description of, in practice, a non-executable library.
hv::wtf::apropos()
{
  local -a results

  IFS=$'\n' read -ra results -d $'\004' \
    < <(apropos "$1" 2>/dev/null)
}

# Describes a file.
hv::wtf::file()
{
  local desc=${1/#$HOME/$'~'}

  # `file -b` returns "brief" output (no leading filename), `-p` avoids
  # updating the file's access time if possible, and `h` doesn't follow
  # symlinks (we'll do that later if needed).
  local magic
  magic=$(command file -bph "$1")

  local regex='^(broken )?symbolic link to (.+)'

  if [[ $magic =~ $regex ]]; then
    local target=${BASH_REMATCH[2]}

    if [[ ${BASH_REMATCH[1]} == broken* ]]; then
      local colour="red"
      magic="broken link"
    else
      magic="$(command file -bpL "$1")"
    fi
  fi

  # Truncate magic for display
  magic=${magic%%:*}

  if [[ -n $HV_DISABLE ]]; then
    printf "%s: %s\n" "${desc}${target:+ → $target}:" "$magic"
  elif [[ -n $HV_SIMPLE ]]; then
    : ### TODO
  else
    hv::banner "$colour" "$desc" "$magic" "${target:+symlink to $target}"
  fi
}

# Describes a command in PATH.
hv::wtf::which()
{
  # Get a list of places $1 can be found.
  local -a places
  IFS=$'\n' read -ra places -d $'\004' < <(type -ap "$1")

  local extra_output=$extra_output
  local place; for place in "${places[@]}"; do
    place=${place/#$HOME/$'~'}
    local desc=""

    if [[ -n $extra_output ]]; then
      desc=$(hv::wtf::whatis "$1")
      # Don't display a description for any additional items.
      unset -v extra_output
    fi

    if [[ -n $HV_DISABLE ]]; then
      printf "%s is %s" "$1" "$place"
      [[ -n $desc ]] && printf ": %s" "$desc"
      printf "\n"
    elif [[ -n $HV_SIMPLE ]]; then
      : ### TODO
    else
      hv::banner "$colour" "$1" "$place" "$desc"
    fi

    [[ -n $one_and_done ]] && break
  done
}

# Describes a variable (or function).
hv::wtf::declare()
{
  local regex='^declare -([[:alpha:]-]+)( [^=]+=)?(.*)'

  if [[ $(declare -p "$1" 2>/dev/null) =~ $regex ||
        $(declare -Fp "$1" 2>/dev/null) =~ $regex ]]
  then
    local attribs="${BASH_REMATCH[1]}"

    if [[ ${BASH_REMATCH[0]} == *=* ]]; then
      local value="${BASH_REMATCH[0]#*=}"
    fi
  else
    return 66
  fi

  local -a props
  local form
  local kind="variable"

  case $attribs in
    *t*)  props+=("traced")
          ;;&
    *x*)  props+=("exported")
          ;;&
    *r*)  props+=("read-only")
          ;;&
    *i*)  form="integer"
          ;;&
    *l*)  form="lowercase"
          ;;&
    *u*)  form="uppercase"
          ;;&
    *a*)  kind="indexed array"
          ;;&
    *A*)  kind="associative array"
          ;;&
    *f*)  kind="function"
          ;;&
    *n*)  kind="nameref variable"
          ;;&
    *)  : ;;
  esac

  if [[ $value == '""' ]]; then
    props=("empty" "${props[@]}")
  elif [[ $value == "()" ]]; then
    props=("empty" "${props[@]}")
  elif [[ -z $value && $kind != "function" ]]; then
    props=("null" "${props[@]}")
  fi

  # concatenate with single spaces
  props+=($form $kind)
  printf "%s" "${props[*]}"
}

# Describes a shell builtin or keyword.
hv::wtf::shell()
{
  # This function uses extended globbing patterns like `@(foo|bar)`, and so
  # requires the shell option `extglob` to be enabled.
  shopt -q extglob || shopt -s extglob

  local name=$1
  local desc

  if desc=$(help -d "$1" 2>/dev/null); then
    # Capture "canonical" name.
    name=${desc%% - *}
    # Trim name from beginning of string.
    desc=${desc#* - }

  elif [[ $1 == @(\!|}|]]|in|do|done|esac|then|elif|else|fi) ]]; then
    ### This `extglob` pattern identifies reserved shell words/keywords with
    #   no `help -d` entry as of bash-4.4, but which have a "parent" keyword
    #   (`for`, `case`, `if`, `while`, etc.)

    name="… $1"

    case $1 in
      "!")
        name=$1
        desc="Invert the return value of a command."
        ;;
      "}")
        name="{ … }"
        desc=$(help -d "{"); desc=${desc#* - }
        ;;
      "]]")
        name="[[ … ]]"
        desc=$(help -d "[["); desc=${desc#* - }
        ;;
      "in")
        name="… $1 …"
        desc="Define a list of items within a compound command."
        ;;
      "do")
        name="… $1 …"
        desc="Define a list of commands to be executed."
        ;;
      "done")
        name="… $1"
        desc="End a ‘for’, ‘select’, ‘while’, or ‘until’ statement."
        ;;
      "esac")
        name="… $1"
        desc="End a ‘case’ statement."
        ;;
      "then"|"elif"|"else")
        name="… $1 …"
        desc="Execute commands conditionally."
        ;;
      "fi")
        desc="End an ‘if’ statement."
        ;;
    esac
  fi

  if [[ -n $HV_DISABLE ]]; then
    printf "%s (shell %s)" "$name" "$type"
    [[ -n $extra_output ]] && printf ": %s" "$desc"
    printf "\n"
  elif [[ -n $HV_SIMPLE ]]; then
    : ### TODO
  else
    hv::banner "$colour" "$name" "$type" "$desc"
  fi
}

# Describes a currently executing process managed by the shell.
hv::wtf::jobs()
{
  local jobspec=$1
  local info
  if ! info=$(builtin jobs -l "$jobspec" 2>&1); then
    local error=${info#*jobs: }
    hv::error "Error" "${error%%:*}" "${error##*: }"
    return 65
  else
    local regex='\[([[:digit:]]+)\]([ +-])[[:space:]]+([[:digit:]]+) (Running|Stopped|Suspended: [[:digit:]]+)[[:space:]]+(.*)'
    [[ $info =~ $regex ]] || return 70
    local number=${BASH_REMATCH[1]}
    local flag=${BASH_REMATCH[2]}
    local pid=${BASH_REMATCH[3]}
    local status=${BASH_REMATCH[4]}
    local cmd=${BASH_REMATCH[5]}

    if [[ -n $HV_DISABLE ]]; then
      builtin jobs -l "$1"
    elif [[ -n $HV_SIMPLE ]]; then
      : ### TODO
    else
      hv::banner "$colour" "%$number" "$pid  ${status,,}" "$cmd"
    fi
  fi
}

# -----------------------------------------------------------------------------
# wtf -- Explains what a thing is.
# -----------------------------------------------------------------------------

wtf()
{
  local opts="afvhsx"
  # -a = display all results
  # -f = skip shell function lookup (like `type -f`)
  # -s = display less information
  # -v = display more information (like `declare -f`)
  # -x = suppress fancy output
  # -h = help

  local usage="$FUNCNAME [-${opts}] <thing>"

  # This function uses extended globbing patterns like `@(foo|bar)`,.
  shopt -s extglob

  # By default, `wtf` displays only the first result. Use `-a` to display all.
  local one_and_done="true"

  # By default, `wtf` displays extra information. Use `-s` for short output.
  local extra_output="true"

  # Suppress fancy output if not connected to a terminal.
  [[ -t 1 ]] || local HV_DISABLE="true"

  local OPT OPTIND OPTARG OPTERR=0
  while getopts ":l${opts}" OPT; do
    case $OPT in
      a)  unset -v one_and_done   ;;
      f)  local skip_func="true"  ;;
      s)  unset -v extra_output   ;;
      [lv]) local verbose="true"  ;; # -l is a secret synonym for -v
      x)  local HV_DISABLE="true" ;;
      h)  printf "Usage: %s\n" "$usage"
          return 0
          ;;
    '?')  hv::error "-$OPTARG" "invalid option" "Usage: $usage"
          return 64 ;;
    esac
  done
  shift $(( OPTIND - 1 ))

  # Accept only one subject term.
  if [[ $# -ne 1 ]]; then
    case $# in
      0)  local error="missing <thing>" ;;
      *)  local error="too many parameters" ;;
    esac
    hv::error "syntax error" "$error" "Usage: $usage"
    return 64
  fi

  # `type -at` displays the type of every available executable named $1 in a
  # short format: "alias", "keyword", "function", "builtin", or "file".
  # Then `uniq` collapses multiple consecutive types, which only ever occurs
  # for files -- all other types are always singular.
  local -a types
  types=( $(type -at "$1" | uniq) )

  if declare -p "$1" &>/dev/null; then
    types+=(variable)
  fi

  if [[ ${#types[@]} -eq 0 ]]; then
    if [[ -e $1 || -L $1 ]]; then
      types=(file)
    elif [[ $1 == %[[:digit:]+-] ]] && builtin jobs "$1" &>/dev/null; then
      types=(job)
    else
      hv::error "$1" "not a thing"
      return 1
    fi
  fi

  for type in "${types[@]}"; do
    local output=""
    local desc=""
    local colour=""

    case $type in
      file)
        # Are we querying a file directly? If so, it will have a slash in the
        # path (`type` will also return "/path/to/foo is /path/to/foo").
        if [[ $1 =~ / ]]; then
          colour="green"
          hv::wtf::file "$1"
        else
          colour="yellow"
          hv::wtf::which "$1"
        fi
        ;;

      alias)
        colour="cyan"
        local def=${BASH_ALIASES[$1]}
        def=${def//\\/\\\\}

        if [[ -n $HV_DISABLE ]]; then
          printf "%s is aliased to ‘%s’\n" "$1" "$def"
        elif [[ -n $HV_SIMPLE ]]; then
          : ### TODO
        else
          hv::banner "$colour" "$1" "$type" "$def"
        fi
        ;;

      builtin|keyword)
        colour="magenta"
        hv::wtf::shell "$1"
        ;;

      function)
        [[ -n $skip_func ]] && continue
        colour="blue"

        desc=$(hv::wtf::declare "$1")
        output="$1 is a $desc"

        local src; if src=$(hv::wtf::whence "$1"); then
          output+=" ($src)"
        fi

        if [[ -n $HV_DISABLE ]]; then
          printf "%s\n" "$output"
        elif [[ -n $HV_SIMPLE ]]; then
          : ### TODO
        else
          hv::banner "$colour" "$1" "$desc" "$src"
        fi

        if [[ -n $FXDOC_LOADED ]]; then
          if [[ -n $extra_output ]]; then
            fxdoc "$1" 2>/dev/null
          else
            fxdoc --short "$1" 2>/dev/null
          fi
        fi

        if [[ -n $verbose ]]; then
          # Also output function source.
          if [[ -z $HV_DISABLE ]] && type -P source-highlight >/dev/null; then
            declare -f "$1" | source-highlight -s bash -f esc
          else
            declare -f "$1"
          fi
        fi
        ;;

      variable)
        colour="blue"

        desc=$(hv::wtf::declare "$1")
        output="$1: $desc"

        if [[ $desc != *array ]]; then
          local value
          printf -v value "%q" "${!1}"
          output+=": ‘${value//\\/\\\\}’"
        fi

        if [[ -n $HV_DISABLE ]]; then
          printf "%s\n" "$output"
        elif [[ -n $HV_SIMPLE ]]; then
          : ### TODO
        else
          hv::banner "$colour" "$1" "$desc" "$value"
        fi
        ;;

      job)
        colour="yellow"
        hv::wtf::jobs "$1"
        ;;
    esac

    if [[ -n $one_and_done ]]; then
      break
    fi
  done

  return 0
} # /wtf()

# set up bash completion
complete -dfabck -j -ev \
         -A function -A helptopic \
         -o bashdefault -o nospace \
         -- wtf
