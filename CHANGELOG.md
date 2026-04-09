# Changelog

All notable changes to Patra will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - Unreleased

### Added

- Project scaffolded
- Architecture defined: sql, table, btree, page, file, where, row, jsonl
- SQL subset specified: CREATE, INSERT, SELECT, UPDATE, DELETE, WHERE, ORDER BY, LIMIT
- .patra file format designed (4KB pages, B-tree index)
- flock concurrency model
