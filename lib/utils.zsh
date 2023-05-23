#!/usr/bin/env zsh

# ------------------------------------------------------------------------------
# UTILS
# Utils for common used actions
# This file is used as a API for sections developers
# ------------------------------------------------------------------------------

# Check if command exists in $PATH
# USAGE:
#   spaceship::exists <command>
spaceship::exists() {
  command -v $1 > /dev/null 2>&1
}

# Check if function is defined
# USAGE:
#   spaceship::defined <function>
spaceship::defined() {
  typeset -f + "$1" &> /dev/null
}

# Check if array includes and item
# USAGE:
#  spaceship::includes <array_name> <item>
spaceship::includes() {
  local array_name="$1" item="$2"
  local array=("${(@P)array_name}")

  (( $array[(Ie)$item] ))
}

# Precompile zsh file to ZWC (zsh word code)
# USAGE:
#  spaceship::precomile <file>
spaceship::precompile() {
  spaceship::exists zcompile || return 1

  local file="$1"

  if [[ ! $file.zwc -nt $file && -w "$(dirname $1)" ]]; then
    zcompile -R -- $file.zwc $file
  fi
}

# Check if the current directory is in a Git repository.
# USAGE:
#   spaceship::is_git
spaceship::is_git() {
  # See https://git.io/fp8Pa for related discussion
  [[ $(command git rev-parse --is-inside-work-tree 2>/dev/null) == true ]]
}

# Check if the current directory is in a Mercurial repository.
# USAGE:
#   spaceship::is_hg
spaceship::is_hg() {
  local hg_root="$(spaceship::upsearch .hg)"
  [[ -n "$hg_root" ]] &>/dev/null
}

# Checks if the section is async or not
# USAGE:
#   spaceship::is_section_async <section>
spaceship::is_section_async() {
  local section="$1"
  local sync_sections=(
    user
    dir
    host
    exec_time
    async
    line_sep
    jobs
    exit_code
    char
  )

  # Some sections must be always sync
  if spaceship::includes sync_sections "$section"; then
    return 1
  fi

  # If user disabled async rendering for whole prompt
  if [[ "$SPACESHIP_PROMPT_ASYNC" != true ]]; then
    return 1
  fi

  local async_option="SPACESHIP_${(U)section}_ASYNC"
  [[ "${(P)async_option}" == true ]]
}

# Check if async is available and there is an async section
# USAGE:
#   spaceship::is_prompt_async
spaceship::is_prompt_async() {
  [[ "$SPACESHIP_PROMPT_ASYNC" == true ]] && (( ASYNC_INIT_DONE ))
}

# Print message backward compatibility warning
# USAGE:
#  spaceship::deprecated <deprecated> [message]
spaceship::deprecated() {
  [[ -n $1 ]] || return
  local deprecated=$1 message=$2
  local deprecated_value=${(P)deprecated} # the value of variable name $deprecated
  [[ -n $deprecated_value ]] || return
  print -P "%B$deprecated%b is deprecated. $message"
}

# Display seconds in human readable format
# For that use `strftime` and convert the duration (float) to seconds (integer).
# USAGE:
#   spaceship::displaytime <seconds> [precision]
spaceship::displaytime() {
  local duration="$1" precision="$2"

  [[ -z "$precision" ]] && precision=1

  integer D=$((duration/60/60/24))
  integer H=$((duration/60/60%24))
  integer M=$((duration/60%60))
  local S=$((duration%60))

  [[ $D > 0 ]] && printf '%dd ' $D
  [[ $H > 0 ]] && printf '%dh ' $H
  [[ $M > 0 ]] && printf '%dm ' $M
  printf %.${precision}f%s $S s
}

# Union of two or more arrays
# USAGE:
#   spaceship::union [arr1[ arr2[ ...]]]
# EXAMPLE:
#   $ arr1=('a' 'b' 'c')
#   $ arr2=('b' 'c' 'd')
#   $ arr3=('c' 'd' 'e')
#   $ spaceship::union $arr1 $arr2 $arr3
#   > a b c d e
spaceship::union() {
  typeset -U sections=("$@")
  echo $sections
}

# Upsearch for specific file or directory
# Returns the path to the first found file or fails
# USAGE:
#   spaceship::upsearch <paths...>
# EXAMPLE:
#   $ spaceship::upsearch package.json node_modules
#   > /home/username/path/to/project/node_modules
spaceship::upsearch() {
  # Parse CLI options
  zparseopts -E -D \
    s=silent -silent=silent

  local files=("$@")
  local root="$(pwd -P)"

  # Go up to the root
  while [ "$root" ]; do
    # For every file as an argument
    for file in "${files[@]}"; do
      local find_match="$(find $root -maxdepth 1 -name $file -print -quit 2>/dev/null)"
      local filename="$root/$file"
      if [[ -n "$find_match" ]]; then
        [[ -z "$silent" ]] && echo "$find_match"
        return 0
      elif [[ -e "$filename" ]]; then
        [[ -z "$silent" ]] && echo "$filename"
        return 0
      fi
    done

    if [[ -d "$root/.git" || -d "$root/.hg" ]]; then
      # If we reached the root of repo, return non-zero
      return 1
    fi

    # Go one level up
    root="${root%/*}"
  done

  # If we reached the root, return non-zero
  return 1
}

spaceship::datafile::python() {
  local imports=$1 load=$2; shift 2
  local keys=("$@")
  python -c "import $imports, functools; data=$load; print(next(filter(None, map(lambda key: functools.reduce(lambda obj, key: obj[key] if key in obj else {}, key.split('.'), data), ['${(j|','|)keys}'])), None))" 2>/dev/null
}

spaceship::datafile::python::yaml() {
  local file=$1; shift
  spaceship::datafile::python yaml "yaml.safe_load(open('$file'))" "$@"
}

spaceship::datafile::python::json() {
  local file=$1; shift
  spaceship::datafile::python json "json.load(open('$file'))" "$@"
}

spaceship::datafile::python::toml() {
  local file=$1; shift
  local import py_version="${(@)$(python3 -V 2>&1)[2]}"
  autoload is-at-least
  # Python 3.11 added tomllib in the stdlib.
  # Previous versions require the tomli package
  if is-at-least 3.11 "$py_version" ]]; then
    import=tomllib
  else
    import=tomli
  fi
  spaceship::datafile::python "$import" "$import.load(open('$file', 'rb'))" "$@"
}

spaceship::datafile::jq() {
  local exe=$1 file=$2; shift 2
  local keys=("$@")
  "$exe" -r ".${(j| // .|)keys}" "$file" 2>/dev/null
}

spaceship::datafile::ruby() {
  local import=$1 load=$2; shift 2
  local keys=("$@")
  ruby -r "$import" -e "puts ['${(j|','|)keys}'].map { |key| key.split('.').reduce($load) { |obj, key| obj[key] } }.find(&:itself)" 2>/dev/null
}

spaceship::datafile::ruby::yaml() {
  local file=$1; shift
  spaceship::datafile::ruby 'yaml' "YAML::load_file('$file')" "$@"
}
spaceship::datafile::ruby::yaml() {
  local file=$1; shift
  spaceship::datafile::ruby 'json' "JSON::load(File.read('$file'))" "$@"
}

spaceship::datafile::node::json() {
  local file=$1; shift
  local keys=("$@")
  node -p "['${(j|','|)keys}'].map(s => s.split('.').reduce((obj, key) => obj[key], require('./$file'))).find(Boolean)" 2>/dev/null
}

# Read data file with dot notation (JSON, YAML, TOML, XML). Additional keys
# will be used as alternatives.
# USAGE:
#   spaceship::datafile --<type> <file> [...keys]
# EXAMPLE:
#  $ spaceship::datafile --json package.json "author.name"
#  > "John Doe"
#  $ spaceship::datafile --toml pyproject.toml "project.version" "tool.poetry.version"
spaceship::datafile() {
  # Parse CLI options
  zparseopts -E -D \
    -json=json \
    -yaml=yaml \
    -toml=toml \
    -xml=xml

  local file="$1"; shift

  if [[ -n "$yaml" ]]; then
    if spaceship::exists yq; then
      spaceship::datafile::jq yq "$file" "$@"
    elif spaceship::exists ruby; then
      spaceship::datafile::ruby::yaml "$file" "$@"
    elif spaceship::exists python3; then
      spaceship::datafile::python::yaml "$file" "$@"
    else
      return 1
    fi
  fi

  if [[ -n "$json" ]]; then
    if spaceship::exists jq; then
      spaceship::datafile::jq jq "$file" "$@"
    elif spaceship::exists yq; then
      spaceship::datafile::jq yq "$file" "$@"
    elif spaceship::exists ruby; then
      spaceship::datafile::ruby::json "$file" "$@"
    elif spaceship::exists python3; then
      spaceship::datafile::python::json "$file" "$@"
    elif spaceship::exists node; then
      spaceship::datafile::node::json "$file" "$@"
    else
      return 1
    fi
  fi

  if [[ -n "$toml" ]]; then
    if spaceship::exists tomlq; then
      spaceship::datafile::jq tomlq "$file" "$@"
    elif spaceship::exists python3; then
      spaceship::datafile::python::toml "$file" "$@"
    else
      return 1
    fi
  fi

  if [[ -n "$xml" ]]; then
    if spaceship::exists xq; then
      spaceship::datafile::jq xq "$file" "$@"
    else
      return 1
    fi
  fi

  # todo: grep by regexp?
  return 1
}

# grep with --color=never or not
# USAGE:
#   spaceship::grep [options] [pattern] [file ...]
spaceship::grep() {
  local GREP_OPTIONS=""
  if command grep --color=never "" &>/dev/null <<< ""; then
    GREP_OPTIONS="--color=never"
  fi
  command grep $GREP_OPTIONS "$@"
}
