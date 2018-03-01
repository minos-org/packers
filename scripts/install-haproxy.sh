#!/bin/sh

_seconds2human() {
    [ -z "${1}" ] && return 1
    printf "%s\\n" "${1}" | grep -v "[^0-9]" >/dev/null || return 1;

    _s2h__num="${1}"
    _s2h__min="0"
    _s2h__hour="0"
    _s2h__day="0"
    if [ "${_s2h__num}" -gt "59" ]; then
        _s2h__sec="$((${_s2h__num} % 60))"
        _s2h__num="$((${_s2h__num} / 60))"
        if [ "${_s2h__num}" -gt "59" ]; then
            _s2h__min="$((${_s2h__num} % 60))"
            _s2h__num="$((${_s2h__num} / 60))"
            if [ "${_s2h__num}" -gt "23" ]; then
                _s2h__hour="$((${_s2h__num} % 24))"
                _s2h__day="$((${_s2h__num} / 24))"
            else
                _s2h__hour="${_s2h__num}"
            fi
        else
            _s2h__min="${_s2h__num}"
        fi
    else
        _s2h__sec="${_s2h__num}"
    fi

    [ "${_s2h__day}"  -gt 0 ] && printf "%s" "${_s2h__day}d "
    [ "${_s2h__hour}" -gt 0 ] && printf "%s" "${_s2h__day}h "
    [ "${_s2h__min}"  -gt 0 ] && printf "%s" "${_s2h__min}m "
    printf "%s" "${_s2h__sec}s"
    printf "\\n"
}

_apt_update() {
    [ -z "${1}" ] && _aupdate__cache_seconds="3600" || _aupdate__cache_seconds="${1}"
    _aupdate__cache_file="/var/cache/apt/pkgcache.bin"

    if [ -f "${_aupdate__cache_file}" ]; then
        _aupdate__last="$(stat -c %Y "${_aupdate__cache_file}")"
        _aupdate__now="$(date +'%s')"
        _aupdate__diff="$(($_aupdate__now - $_aupdate__last))"
        if [ "${_aupdate__diff}" -lt "${_aupdate__cache_seconds}" ]; then
            printf "%s\\n" "apt-get update was recently used ($(_seconds2human "${_aupdate__diff}") ago), skipping ..."
        else
            apt-get update
        fi
    else
        apt-get update
    fi
}

_apt_update 3600 #only update index if older than 1hr
apt-get install -y haproxy
