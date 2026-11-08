#!/usr/bin/env bash
# Kit lint for skill and agent files (docs/contracts/kit-skills.md, "Lint").
# Usage: check-skills.sh [--root <dir>]   (default: git toplevel)
# Reads only. Needs bash, grep, sed, and coreutils. Walks directories with bash globs
# (a recursive function, because macOS bash 3.2 has no globstar).
set -euo pipefail
export LC_ALL=C
shopt -s nullglob dotglob

# Top-level SKILL.md frontmatter keys allowed besides name and description. Dave adds others.
ALLOWED_KEYS="paths"
# Skills whose references need a ## Sources section, and single reference paths under .claude/skills/.
SOURCED_SKILLS="security-engineering api-contract testing-strategy database-drizzle ui-ux-design refactoring-playbook git-workflow feature-recipes observability-and-debugging react-standards/references/17-nextjs-app-router.md"
MAX_SKILL_LINES=100
MAX_NAME_CHARS=64
MAX_DESCRIPTION_CHARS=1024

usage() {
  echo "Usage: check-skills.sh [--root <dir>]" >&2
  exit 2
}

root=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root)
      [ $# -ge 2 ] || usage
      root="$2"
      shift 2
      ;;
    *) usage ;;
  esac
done

if [ -z "$root" ]; then
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "check-skills.sh: not in a git repository; pass --root <dir>" >&2
    exit 2
  }
fi
root="${root%/}"
if [ ! -d "$root" ] || [ ! -r "$root" ] || [ ! -x "$root" ]; then
  echo "check-skills.sh: cannot read root '$root'" >&2
  exit 2
fi
skills_dir="$root/.claude/skills"
agents_dir="$root/.claude/agents"
if [ ! -d "$skills_dir" ] || [ ! -r "$skills_dir" ]; then
  echo "check-skills.sh: no readable .claude/skills under '$root'" >&2
  exit 2
fi

fail=0
report() {
  echo "FAIL: $*"
  fail=1
}

rel() {
  printf '%s' "${1#"$root"/}"
}

# Collect regular files under a directory into FILES. Does not follow directory symlinks.
FILES=()
walk() {
  local entry
  for entry in "$1"/*; do
    if [ -d "$entry" ] && [ ! -L "$entry" ]; then
      walk "$entry"
    elif [ -f "$entry" ]; then
      FILES+=("$entry")
    fi
  done
}

# Read a file with \r stripped into LINES (index 0 is line 1).
LINES=()
read_lines() {
  local line
  LINES=()
  while IFS= read -r line || [ -n "$line" ]; do
    LINES+=("$line")
  done < <(tr -d '\r' < "$1")
}

trim() {
  local v="$1"
  v="${v#"${v%%[![:space:]]*}"}"
  v="${v%"${v##*[![:space:]]}"}"
  printf '%s' "$v"
}

unquote() {
  local v
  v="$(trim "$1")"
  case "$v" in
    \"*\") v="${v#\"}"; v="${v%\"}" ;;
    \'*\') v="${v#\'}"; v="${v%\'}" ;;
  esac
  printf '%s' "$v"
}

# Character count of UTF-8 text: bytes minus continuation bytes.
char_count() {
  local n
  n="$(printf '%s' "$1" | tr -d '\200-\277' | wc -c)"
  printf '%s' "$((n))"
}

re_key='^([A-Za-z0-9_][A-Za-z0-9_-]*):(.*)$'
re_name='^[a-z0-9]+(-[a-z0-9]+)*$'
re_fence='^[[:space:]]*```'
re_link='[]][(]([^)]*)[)]'
re_tick='`([^`]*)`'
re_ref_token='^[0-9][0-9]-[a-z0-9-]+\.md$'
re_check='^- \[ \] ((SEC|DB-MIG)-[A-Za-z0-9-]*[A-Za-z0-9])'
re_uses='^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*(.*)$'
re_sha='^[0-9a-fA-F]{40}$'
dash_bytes=$'\xe2\x80(\x93|\x94)'
# K6 attribution, matched case-insensitively: any Co-Authored-By; "Generated with" only when an
# agent or AI name follows (plain or as a [link]), so prose such as "generated with drizzle-kit"
# passes; and the robot-emoji form. The emoji is U+1F916, matched as its UTF-8 bytes.
attribution_ai='claude|anthropic|chatgpt|openai|copilot|cursor|gemini|codex|(an?[[:space:]]+)?ai([^[:alnum:]]|$)'
attribution='co-authored-by|generated with[[:space:]]+[[]?[[:space:]]*('"$attribution_ai"')|'$'\xf0\x9f\xa4\x96''[[:space:]]*generated'

# K1 and K5: frontmatter and size of one SKILL.md.
check_skill_md() {
  local file="$1" folder="$2" path n close i line key value
  local name_count=0 desc_count=0 name="" desc="" desc_line=0 next
  path="$(rel "$file")"
  read_lines "$file"
  n=${#LINES[@]}

  if [ "$n" -gt "$MAX_SKILL_LINES" ]; then
    report "K5 $path has $n lines, cap $MAX_SKILL_LINES"
  fi

  if [ "$n" -eq 0 ] || [ "${LINES[0]}" != "---" ]; then
    report "K1 $path:1 line 1 is not ---"
    return 0
  fi
  close=0
  i=1
  while [ "$i" -lt "$n" ]; do
    if [ "${LINES[$i]}" = "---" ]; then
      close=$i
      break
    fi
    i=$((i + 1))
  done
  if [ "$close" -eq 0 ]; then
    report "K1 $path has no closing --- for its frontmatter"
    return 0
  fi

  i=1
  while [ "$i" -lt "$close" ]; do
    line="${LINES[$i]}"
    if [[ $line =~ $re_key ]]; then
      key="${BASH_REMATCH[1]}"
      value="${BASH_REMATCH[2]}"
      case "$key" in
        name)
          name_count=$((name_count + 1))
          name="$(unquote "$value")"
          ;;
        description)
          desc_count=$((desc_count + 1))
          desc="$(unquote "$value")"
          desc_line=$((i + 1))
          next=$((i + 1))
          if [ "$next" -lt "$close" ] && [ -n "$(trim "${LINES[$next]}")" ] \
            && ! [[ ${LINES[$next]} =~ $re_key ]]; then
            report "K1 $path:$desc_line description spans more than one line"
          else
            case "$desc" in
              '>'* | '|'*) report "K1 $path:$desc_line description spans more than one line" ;;
            esac
          fi
          ;;
        *)
          case " $ALLOWED_KEYS " in
            *" $key "*) ;;
            *) report "K1 $path:$((i + 1)) key '$key' is not in ALLOWED_KEYS" ;;
          esac
          ;;
      esac
    fi
    i=$((i + 1))
  done

  if [ "$name_count" -ne 1 ]; then
    report "K1 $path name: appears $name_count times, expected once"
  else
    if ! [[ $name =~ $re_name ]]; then
      report "K1 $path name '$name' is not lowercase letters, digits, and single hyphens"
    fi
    if [ "$(char_count "$name")" -gt "$MAX_NAME_CHARS" ]; then
      report "K1 $path name has $(char_count "$name") characters, cap $MAX_NAME_CHARS"
    fi
    if [ "$name" != "$folder" ]; then
      report "K1 $path name '$name' does not equal folder '$folder'"
    fi
  fi

  if [ "$desc_count" -ne 1 ]; then
    report "K1 $path description: appears $desc_count times, expected once"
  elif [ -z "$desc" ]; then
    report "K1 $path:$desc_line description is empty"
  elif [ "$(char_count "$desc")" -gt "$MAX_DESCRIPTION_CHARS" ]; then
    report "K1 $path:$desc_line description has $(char_count "$desc") characters, cap $MAX_DESCRIPTION_CHARS"
  fi
}

# K3 and K9: links, reference names, and checklist items in one .md under .claude/skills/.
CHECK_IDS=""
check_skill_doc() {
  local file="$1" is_skill_md="$2" path dir n i line scan target matches next id in_fence=0
  path="$(rel "$file")"
  dir="${file%/*}"
  read_lines "$file"
  n=${#LINES[@]}
  i=0
  while [ "$i" -lt "$n" ]; do
    line="${LINES[$i]}"
    if [[ $line =~ $re_fence ]]; then
      in_fence=$((1 - in_fence))
      i=$((i + 1))
      continue
    fi
    if [ "$in_fence" -eq 1 ]; then
      i=$((i + 1))
      continue
    fi

    # K3 backticked reference names, SKILL.md only.
    if [ "$is_skill_md" -eq 1 ]; then
      scan="$line"
      while [[ $scan =~ $re_tick ]]; do
        target="${BASH_REMATCH[1]}"
        scan="${scan#*"${BASH_REMATCH[0]}"}"
        if [[ $target =~ $re_ref_token ]]; then
          matches=("$skills_dir"/*/references/"$target")
          if [ ${#matches[@]} -eq 0 ]; then
            report "K3 $path:$((i + 1)) $target does not exist"
          fi
        fi
      done
    fi

    # K3 relative links, with inline code spans removed first.
    scan="$line"
    while [[ $scan =~ $re_tick ]]; do
      scan="${scan%%"${BASH_REMATCH[0]}"*} ${scan#*"${BASH_REMATCH[0]}"}"
    done
    while [[ $scan =~ $re_link ]]; do
      target="$(trim "${BASH_REMATCH[1]}")"
      scan="${scan#*"${BASH_REMATCH[0]}"}"
      target="${target%% *}"
      target="${target#<}"
      target="${target%>}"
      case "$target" in
        http:* | https:* | mailto:* | '#'*) continue ;;
      esac
      target="${target%%#*}"
      if [ -z "$target" ] || [ ! -e "$dir/$target" ]; then
        report "K3 $path:$((i + 1)) ${target:-()} does not exist"
      fi
    done

    # K9 checklist items.
    if [[ $line =~ $re_check ]]; then
      id="${BASH_REMATCH[1]}"
      next=$((i + 1))
      case "$line" in
        *Verify:*) ;;
        *)
          if [ "$next" -ge "$n" ] || [[ ${LINES[$next]} != *Verify:* ]]; then
            report "K9 $path:$((i + 1)) $id has no Verify:"
          fi
          ;;
      esac
      CHECK_IDS="$CHECK_IDS$id"$'\t'"$path:$((i + 1))"$'\n'
    fi
    i=$((i + 1))
  done
}

# K2: skills: list of one agent file.
check_agent() {
  local file="$1" path n i line in_list=0 item value
  path="$(rel "$file")"
  read_lines "$file"
  n=${#LINES[@]}
  if [ "$n" -eq 0 ] || [ "${LINES[0]}" != "---" ]; then
    return 0
  fi
  i=1
  while [ "$i" -lt "$n" ] && [ "${LINES[$i]}" != "---" ]; do
    line="${LINES[$i]}"
    if [[ $line =~ $re_key ]]; then
      in_list=0
      if [ "${BASH_REMATCH[1]}" = "skills" ]; then
        in_list=1
        value="$(trim "${BASH_REMATCH[2]}")"
        if [ -n "$value" ]; then
          # Inline form: skills: [a, b] or skills: a
          value="${value#[}"
          value="${value%]}"
          value="${value//,/ }"
          for item in $value; do
            check_agent_skill "$path" "$(unquote "$item")"
          done
          in_list=0
        fi
      fi
    elif [ "$in_list" -eq 1 ] && [[ $line =~ ^[[:space:]]*-[[:space:]]+(.*)$ ]]; then
      check_agent_skill "$path" "$(unquote "${BASH_REMATCH[1]}")"
    fi
    i=$((i + 1))
  done
}

check_agent_skill() {
  local path="$1" item="$2"
  if ! [[ $item =~ $re_name ]] || [ ! -f "$skills_dir/$item/SKILL.md" ]; then
    report "K2 $path skills: $item has no .claude/skills/$item/SKILL.md"
  fi
}

# K4 and K6 over one file.
check_text() {
  local file="$1" path num
  path="$(rel "$file")"
  while IFS=: read -r num _; do
    report "K4 $path:$num em or en dash"
  done < <(tr -d '\r' < "$file" | grep -anE "$dash_bytes" || true)
  while IFS=: read -r num _; do
    report "K6 $path:$num attribution line"
  done < <(tr -d '\r' < "$file" | grep -aniE "$attribution" || true)
}

# K7: one reference needs ## Sources followed by a non-empty line before the next heading.
check_sources() {
  local file="$1" path n i found=0 filled=0
  path="$(rel "$file")"
  read_lines "$file"
  n=${#LINES[@]}
  i=0
  while [ "$i" -lt "$n" ]; do
    if [ "$found" -eq 0 ]; then
      if [ "$(trim "${LINES[$i]}")" = "## Sources" ]; then
        found=1
      fi
    elif [[ ${LINES[$i]} == '#'* ]]; then
      break
    elif [ -n "$(trim "${LINES[$i]}")" ]; then
      filled=1
      break
    fi
    i=$((i + 1))
  done
  if [ "$found" -eq 0 ]; then
    report "K7 $path has no ## Sources section"
  elif [ "$filled" -eq 0 ]; then
    report "K7 $path has an empty ## Sources section"
  fi
}

# K8: uses: pins in one asset workflow template.
check_pins() {
  local file="$1" path n i value ref
  path="$(rel "$file")"
  read_lines "$file"
  n=${#LINES[@]}
  i=0
  while [ "$i" -lt "$n" ]; do
    if [[ ${LINES[$i]} =~ $re_uses ]]; then
      value="${BASH_REMATCH[2]}"
      value="${value%%[[:space:]]#*}"
      value="$(unquote "$value")"
      case "$value" in
        ./*) ;;
        *@*)
          ref="${value##*@}"
          if ! [[ $ref =~ $re_sha ]]; then
            report "K8 $path:$((i + 1)) uses: $value is not pinned to a SHA"
          fi
          ;;
        *) report "K8 $path:$((i + 1)) uses: $value is not pinned to a SHA" ;;
      esac
    fi
    i=$((i + 1))
  done
}

# Skills: K1, K5.
skill_count=0
for folder in "$skills_dir"/*; do
  [ -d "$folder" ] || continue
  skill_count=$((skill_count + 1))
  if [ -f "$folder/SKILL.md" ]; then
    check_skill_md "$folder/SKILL.md" "${folder##*/}"
  else
    report "K1 $(rel "$folder") has no SKILL.md"
  fi
done

# Every file under .claude/skills/: K3, K9 for .md; K4, K6 for all.
FILES=()
walk "$skills_dir"
for file in ${FILES[@]+"${FILES[@]}"}; do
  case "$file" in
    *.md)
      if [ "${file##*/}" = "SKILL.md" ] && [ "${file%/*/SKILL.md}" = "$skills_dir" ]; then
        check_skill_doc "$file" 1
      else
        check_skill_doc "$file" 0
      fi
      ;;
  esac
  check_text "$file"
done

# K9 uniqueness across the kit.
prev_id=""
prev_loc=""
while IFS=$'\t' read -r id loc; do
  [ -n "$id" ] || continue
  if [ "$id" = "$prev_id" ]; then
    report "K9 $loc $id appears twice, first at $prev_loc"
  else
    prev_id="$id"
    prev_loc="$loc"
  fi
done < <(printf '%s' "$CHECK_IDS" | sort -s -t $'\t' -k1,1)

# Agents: K2 for top-level .md; K4, K6 for every file.
agent_count=0
if [ -d "$agents_dir" ]; then
  for file in "$agents_dir"/*.md; do
    [ -f "$file" ] || continue
    agent_count=$((agent_count + 1))
    check_agent "$file"
  done
  FILES=()
  walk "$agents_dir"
  for file in ${FILES[@]+"${FILES[@]}"}; do
    check_text "$file"
  done
fi

# K7: references of sourced skills.
for entry in $SOURCED_SKILLS; do
  case "$entry" in
    */*)
      if [ -f "$skills_dir/$entry" ]; then
        check_sources "$skills_dir/$entry"
      fi
      ;;
    *)
      if [ -d "$skills_dir/$entry/references" ]; then
        FILES=()
        walk "$skills_dir/$entry/references"
        for file in ${FILES[@]+"${FILES[@]}"}; do
          case "$file" in
            *.md) check_sources "$file" ;;
          esac
        done
      fi
      ;;
  esac
done

# K8: workflow templates under each skill's assets/.
for assets in "$skills_dir"/*/assets; do
  [ -d "$assets" ] || continue
  FILES=()
  walk "$assets"
  for file in ${FILES[@]+"${FILES[@]}"}; do
    case "$file" in
      *.yml | *.yaml) check_pins "$file" ;;
    esac
  done
done

[ "$fail" -eq 0 ] && echo "OK: $skill_count skills, $agent_count agents consistent"
exit "$fail"
