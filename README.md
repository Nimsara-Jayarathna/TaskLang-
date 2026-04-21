# TaskLang++

TaskLang++ is a Domain-Specific Language (DSL) designed for defining and managing task scheduling and automation workflows. This project is developed as part of the SE2052 – Programming Paradigms module.

## Overview

Modern systems rely on scheduling mechanisms such as cron jobs, CI/CD pipelines, and automated scripts. TaskLang++ simplifies these by providing a concise and expressive syntax to define:

- Tasks
- Time-based scheduling
- Task dependencies
- Conditional execution

## Features

- Define tasks using a simple structured syntax
- Support for scheduling:
  - `EVERY DAY`
  - `AT <time>`
- Define dependencies between tasks using `AFTER`
- Conditional execution using `IF success`
- Lexer and parser implementation using Flex (Lex) and Bison (Yacc)
- Validation of both valid and invalid programs

## Example

```txt
TASK backupDB {
  RUN "backup.sh"
  EVERY DAY AT 02:00
}

TASK sendReport {
  RUN "report.py"
  AFTER backupDB
  IF success
}
