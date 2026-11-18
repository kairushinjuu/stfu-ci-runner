# Android CI Runner

A minimal GitHub Actions repository for running automated Android build jobs.

## Overview

This repository contains workflow definitions and lightweight CI configuration. Build inputs and environment-specific settings are managed separately.

## Usage

Authorized maintainers can start supported jobs through the GitHub Actions interface or through configured repository events. Job outcomes are available in the Actions tab.

## Security

Do not commit credentials, private source code, proprietary assets, or sensitive build outputs. Use GitHub Actions secrets for credentials and apply least-privilege access controls.

Review workflows and artifact retention settings before enabling builds.
