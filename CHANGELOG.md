# Changelog

All notable changes to Kotoba are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and Kotoba follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Repository and package skeleton for Kotoba 0.1.
- `Kotoba.Document`: reads and writes the stored document (a Lexical 0.51
  editor state in a Kotoba envelope), checks each node, keeps unknown nodes,
  and gives traversal, text, mentions and attachments.
- `Kotoba.Node`: the behaviour and `use Kotoba.Node` for node structs with
  typed fields.
- Built-in nodes under `Kotoba.Nodes` for each Lexical node of the editor,
  and the `attachment` and `mention` nodes.
