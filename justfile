# TTY and ANSI color-support detection for Gleam

# === ALIASES ===
alias b := build
alias t := test
alias f := format
alias l := lint
alias c := clean

# Default recipe
default:
    @just --list

# === STANDARD RECIPES ===

# Compile the project
build:
    gleam build

# Run tests
test:
    gleam test --target erlang
    gleam test --target javascript

# Format code
format:
    gleam format src test

# Run linter
lint:
    gleam format --check src test

# Remove build artifacts
clean:
    rm -rf build

# Full validation workflow
ci: format lint test build docs

# Build API documentation
docs:
    gleam docs build

alias pr := ci
