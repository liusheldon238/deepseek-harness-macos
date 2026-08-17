# DeepSeek Harness Desktop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a native macOS shell that provisions a compatible Node runtime, launches DeepSeek Harness, and embeds its local Web UI in a WKWebView.

**Architecture:** A Swift Package contains a testable core library for runtime selection, verified downloads, and DSH process coordination, plus an AppKit executable for the window and WKWebView. A packaging script creates an ad-hoc signed `.app` and ZIP without requiring an administrator account.

**Tech Stack:** Swift 6 / AppKit / WebKit / Foundation / XCTest / Node.js 22.23.1 / DeepSeek Harness `@deepseek-ai/dsh@0.1.0-rc.6`.

## Global Constraints

- Require Node >=22.19.0 and a matching host architecture before using an existing installation.
- Download Node 22.23.1 for arm64 or x64 when the existing environment is missing or incompatible.
- Verify downloaded Node archives against the official `SHASUMS256.txt` before extraction.
- Bind DSH to `127.0.0.1` and let the OS select an available port.
- Store runtime/cache data under `~/Library/Application Support/DeepSeek Harness Desktop/`.
- Build an ad-hoc signed app and publish `v0.0.1` to `liusheldon238/deepseek-harness-macos`.

## Tasks

1. Add failing core tests for SemVer, architecture compatibility, Node distribution URLs, and DSH output parsing.
2. Implement the core runtime resolver/downloader and DSH process manager until all unit tests pass.
3. Implement AppKit lifecycle, WKWebView loading, status/error/retry UI, and graceful child-process shutdown.
4. Add packaging, README, MIT license, smoke tests, and release metadata; build and run the app locally.
5. Initialize the public GitHub repository, push the verified commit, and create the `v0.0.1` release asset.
