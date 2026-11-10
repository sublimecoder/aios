---
name: video-transcript-downloader
description: "yt-dlp downloads: video, audio, subtitles, transcripts, clips, playlists."
---

# Video Transcript Downloader

`~/.claude/skills/video-transcript-downloader/scripts/vtd.js` can:
- Print a transcript as a clean paragraph (timestamps optional).
- Download video/audio/subtitles.

Transcript behavior:
- YouTube: fetch via `youtube-transcript-plus` when possible.
- Otherwise: pull subtitles via `yt-dlp`, then clean into a paragraph.

## Setup

```bash
cd ~/.claude/skills/video-transcript-downloader && npm ci
```

CLI syntax:

```bash
~/.claude/skills/video-transcript-downloader/scripts/vtd.js --help
~/.claude/skills/video-transcript-downloader/scripts/vtd.js transcript --help
```

Subcommands support focused help without requiring `--url`.

## Transcript (default: clean paragraph)

```bash
~/.claude/skills/video-transcript-downloader/scripts/vtd.js transcript --url 'https://…'
~/.claude/skills/video-transcript-downloader/scripts/vtd.js transcript --url 'https://…' --lang en
~/.claude/skills/video-transcript-downloader/scripts/vtd.js transcript --url 'https://…' --timestamps
~/.claude/skills/video-transcript-downloader/scripts/vtd.js transcript --url 'https://…' --keep-brackets
```

## Download video / audio / subtitles

```bash
~/.claude/skills/video-transcript-downloader/scripts/vtd.js download --url 'https://…' --output-dir ~/Downloads
~/.claude/skills/video-transcript-downloader/scripts/vtd.js audio --url 'https://…' --output-dir ~/Downloads
~/.claude/skills/video-transcript-downloader/scripts/vtd.js subs --url 'https://…' --output-dir ~/Downloads --lang en
```

## Formats (list + choose)

List available formats (format ids, resolution, container, audio-only, etc):

```bash
~/.claude/skills/video-transcript-downloader/scripts/vtd.js formats --url 'https://…'
```

Download a specific format id (example):

```bash
~/.claude/skills/video-transcript-downloader/scripts/vtd.js download --url 'https://…' --output-dir ~/Downloads -- --format 137+140
```

Prefer MP4 container without re-encoding (remux when possible):

```bash
~/.claude/skills/video-transcript-downloader/scripts/vtd.js download --url 'https://…' --output-dir ~/Downloads -- --remux-video mp4
```

## Notes

- Default transcript output is a single paragraph. Use `--timestamps` only when asked.
- Bracketed cues like `[Music]` are stripped by default; keep them via `--keep-brackets`.
- Pass extra `yt-dlp` args after `--` for `transcript` fallback, `download`, `audio`, `subs`, `formats`.

```bash
~/.claude/skills/video-transcript-downloader/scripts/vtd.js formats --url 'https://…' -- -v
```

## Troubleshooting (only when needed)

- Missing `yt-dlp` / `ffmpeg`:

```bash
brew install yt-dlp ffmpeg
```

- Verify:

```bash
yt-dlp --version
ffmpeg -version | head -n 1
```
