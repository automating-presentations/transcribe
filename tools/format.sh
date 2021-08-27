#!/bin/bash

INPUT_TXT="$1"

# Break lines at a width of 100 single-byte characters, and insert a new line every three lines.
fold -100 "$INPUT_TXT" |awk '{print $0 ((NR%3)? "" : "\n")}'

