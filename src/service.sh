#!/usr/bin/sh

### Utilities ###
ANSI="\x1b[";
ANSI_BOLD="${ANSI}1m";
ANSI_RED="${ANSI}38;5;1m";
ANSI_YELLOW="${ANSI}38;5;3m";
ANSI_GREEN="${ANSI}38;5;2m";
ANSI_RESET="${ANSI}0m";

WARN="${ANSI_BOLD}${ANSI_YELLOW}WARNING:${ANSI_RESET}";
ERROR="${ANSI_BOLD}${ANSI_RED}ERROR:${ANSI_RESET}";

tjq() {
  ### TJQ
  # Typed jq.
  ### Arguments
  # 1 = JSON to query.
  # 2 = Path of query, for logging.
  # 3 = Query to use.
  # 4 = If true, jq -r will be used.
  # 5... = accepted types.
  
  local JSON="";
  local QUERY="";
  local PATH_="";
  local RAW="false";
  local TYPES=();
  
  local I="$((1))";
  for ARG in "${@}"; do
    case "${I}" in
      "1" ) JSON="${ARG}" ;;
      "2" ) PATH_="${ARG}" ;;
      "3" ) QUERY="${ARG}" ;;
      "4" ) RAW="${ARG}" ;;
      *   ) TYPES+=("${ARG}") ;;
    esac;
    I="$((${I} + 1))";
  done;

  local VALUE="$(echo "${JSON}" | jq "${QUERY}")";
  local VALUE_TYPE="$(echo "${VALUE}" | jq -r 'type')";

  local OK="false";
  for TYPE in "${TYPES[@]}"; do
    [[ "${TYPE}" == "${VALUE_TYPE}" ]] && OK="true";
  done;

  if [[ "${OK}" == "true" ]]; then
    if [[ "${RAW}" == "true" ]]; then
      echo "$(echo "${VALUE}" | jq -r)";
    else
      echo "${VALUE}";
    fi;
  else
    local ACCEPTABLE_TYPES="";
    if [[ "${#TYPES}" == "$((1))" ]]; then
      ACCEPTABLE_TYPES="${TYPES[1]}";
    elif [[ "${#TYPES}" == "$((2))" ]]; then
      ACCEPTABLE_TYPES="${TYPES[1]} or ${TYPES[2]}";
    else
      local I="$((1))";
      for TYPE in "${TYPES[@]}"; do
        ACCEPTABLE_TYPES="${ACCEPTABLE_TYPES}${TYPE}";
        if [[ "${I}" != "$((${#TYPES} - 1))" ]]; then
          if [[ "${I}" != "${#TYPES}" ]]; then
            ACCEPTABLE_TYPES="${ACCEPTABLE_TYPES}, ";
          fi;
        else
          ACCEPTABLE_TYPES="${ACCEPTABLE_TYPES}, or ";
        fi;
        I="$((${I} + 1))";
      done;
    fi;

    printf "${ERROR} Invalid config: Expected ${PATH_} to be a value of ";
    printf "type ${ACCEPTABLE_TYPES}, got value of type ${VALUE_TYPE}.\n";
    exit 1;
  fi;
}

### Global variables ###
CONFIG="{}";
NAME="";
USER_="";
EXEC="";
TAKEOVER=false;
TAKEOVER_TAKE_PROCESSES="";
TAKEOVER_TAKE_SERVICES="";
TAKEOVER_RETURN_PROCESSES="";
TAKEOVER_RETURN_SERVICES="";

### Load arguments file ###
if [[ -f /tmp/seamless-kvm-args ]]; then
  source /tmp/seamless-kvm-args;
  rm /tmp/seamless-kvm-args;
fi;

### Load config file ###
if [[ -f /etc/seamless-kvm/config.json ]]; then
  CONFIG=$(cat /etc/seamless-kvm/config.json);
fi;

### Load config into global variables ###
load_default() {
  local DEFAULT="$(tjq "${CONFIG}" '.vms.default' '.vms.default' 'true' 'string' 'null')";
  if [[ ! -z "${DEFAULT}" ]]; then
    local VM="$(tjq "${CONFIG}" ".vms[\"${DEFAULT}\"]" ".vms[\"${DEFAULT}\"]" 'true' 'object' 'null')";
    if [[ ! -z "${VM}" ]]; then
      NAME="${DEFAULT}";
      USER_="$(tjq "${VM}" ".user" ".user // \"${USER}\"" "true" "string")";
      EXEC="$(tjq "${VM}" ".exec" ".exec // \"exit\"" "true" "string")";
      TAKEOVER="$(tjq "${VM}" | ".takeover" ".takeover // false" "true" "boolean")";
      TAKEOVER=[[ "${TAKEOVER}" == "true" ]];
    else
      printf "${ERROR} The default VM \"${DEFAULT}\" does not exist. Unable to continue.\n";
      exit 1;
    fi;
  fi;
}

load_specified() {
  local VM="$(tjq "${CONFIG}" ".vms[\"${1}\"]" ".vms[\"${1}\"]" 'true' 'object' 'null')";
  if [[ ! -z "${VM}" ]]; then
    NAME="${1}";
    USER_="$(tjq "${VM}" ".user" ".user // \"${USER}\"" "true" "string")";
    EXEC="$(tjq "${VM}" ".exec" ".exec // \"exit\"" "true" "string")";
    TAKEOVER="$(tjq "${VM}" | ".takeover" ".takeover // false" "true" "boolean")";
    TAKEOVER=[[ "${TAKEOVER}" == "true" ]];
  else
    printf "${WARN} The specified VM \"${1}\" does not exist. Attempting to "
    printf "fall back to the default VM.\n";
    load_default;
  fi;
}

# If number of arguments >= 1...
[[ "${ARG_N}" -ge 1 ]] \
  && load_specified "${ARG_1}" \
  || load_default;

# If the VM is configured to take over the system, load the relevant config.
if [[ "${TAKEOVER}" ]]; then
  TAKEOVER_="$(tjq "${TAKEOVER}" '.takeover' '.takeover' 'true' 'object' 'null')";
  if [[ ! -z "${TAKEOVER_}" ]]; then
    TAKE="$(tjq "${TAKEOVER_}" '.take' '.take' 'true' 'object' 'null')";
    if [[ ! -z "${TAKE}" ]]; then
      PROCESS="$(tjq "${TAKE}" '.process' '.process' 'true' 'array' 'null')";
      if [[ ! -z "${PROCESS}" ]]; then
        while read LINE; do
          if [[ "${LINE}" != "string" ]] && [[ "${LINE}" != "" ]]; then
            printf "${ERROR} Invalid configuration: Expected ";
            printf ".takeover.take.process[*] to be of type string, got ";
            printf "value of type ${LINE}.\n";
            exit 1;
          fi;
        done <<< $(echo "${PROCESS}" | jq -r '.[] | type');
        TAKEOVER_TAKE_PROCESSES="$(echo "${PROCESS}" | jq -r 'join("\n")')";
      fi;
      SERVICE="$(tjq "${TAKE}" '.service' '.service' 'true' 'array' 'null')";
      if [[ ! -z "${SERVICE}" ]]; then
        while read LINE; do
          if [[ "${LINE}" != "string" ]] && [[ "${LINE}" != "" ]]; then
            printf "${ERROR} Invalid configuration: Expected ";
            printf ".takeover.take.service[*] to be of type string, got ";
            printf "value of type ${LINE}.\n";
            exit 1;
          fi;
        done <<< $(echo "${SERVICE}" | jq -r '.[] | type');
        TAKEOVER_TAKE_SERVICES="$(echo "${SERVICE}" | jq -r 'join("\n")')";
      fi;
    fi;
    RETURN="$(tjq "${TAKEOVER_}" '.return' '.return' 'true' 'object' 'null')";
    if [[ ! -z "${RETURN}" ]]; then
      PROCESS="$(tjq "${RETURN}" '.process' '.process' 'true' 'array' 'null')";
      if [[ ! -z "${PROCESS}" ]]; then
        while read LINE; do
          if [[ "${LINE}" != "string" ]] && [[ "${LINE}" != "" ]]; then
            printf "${ERROR} Invalid configuration: Expected ";
            printf ".takeover.return.process[*] to be of type string, got ";
            printf "value of type ${LINE}.\n";
            exit 1;
          fi;
        done <<< $(echo "${PROCESS}" | jq -r '.[] | type');
        TAKEOVER_RETURN_PROCESSES="$(echo "${PROCESS}" | jq -r 'join("\n")')";
      fi;
      SERVICE="$(tjq "${RETURN}" '.service' '.service' 'true' 'array' 'null')";
      if [[ ! -z "${SERVICE}" ]]; then
        while read LINE; do
          if [[ "${LINE}" != "string" ]] && [[ "${LINE}" != "" ]]; then
            printf "${ERROR} Invalid configuration: Expected ";
            printf ".takeover.return.service[*] to be of type string, got ";
            printf "value of type ${LINE}.\n";
            exit 1;
          fi;
        done <<< $(echo "${SERVICE}" | jq -r '.[] | type');
        TAKEOVER_RETURN_SERVICES="$(echo "${SERVICE}" | jq -r 'join("\n")')";
      fi;
    fi;
  fi;
fi;

### Set up take and return handlers ###
take() {
  while read LINE; do
    [[ "${LINE}" != "" ]] && pkill "${LINE}";
  done <<< $(echo "${TAKEOVER_TAKE_PROCESSES}");
  while read LINE; do
    [[ "${LINE}" != "" ]] && systemctl stop "${LINE}";
  done <<< $(echo "${TAKEOVER_TAKE_SERVICES}");
}

ret() {
  # TODO: Set up returning processes.
  while read LINE; do
    [[ "${LINE}" != "" ]] && systemctl start "${LINE}";
  done <<< $(echo "${TAKEOVER_RETURN_SERVICES}");
}

### Set up signal handlers ###
gracefulexit() {
  pkill "${EXEC}";
  while [[ "$(ps aux | grep "${EXEC}" -c)" -gt 1 ]]; do sleep 1; done; 
  ret;
  exit 0;
}
trap gracefulexit SIGTERM SIGHUP;

### Take ###
take;

### Start up the VM and wait for it to exit ###
sudo --user "${USER_}" "${EXEC}";

### Return ###
ret;

### Exit ###
exit 0;
