#!/usr/bin/env bash
set -e

while getopts t:r: flag
do
    case "${flag}" in
        t) test=${OPTARG};;
        r) runs=${OPTARG};;
    esac
done

runs=$([ -z "$runs" ] && echo "100" || echo "$runs")

export PROPTEST_CASES=$runs

if [ -z "$test" ]; then match="[src/test/*.t.sol]"; else match=$test; fi

rm -rf out

forge test --match "$match" -vvv