# CLAUDE.md — StremioClient

## Project Overview

StremioClient is a native iOS application built with SwiftUI that provides a Netflix-like interface for the Stremio streaming platform. It integrates with Stremio's addon protocol, Real-Debrid for cached torrent streaming, TMDB for recommendations, and Claude AI for conversational search.

---

## Technology Stack

| Layer | Technology |
|---|---|
| Language | Swift 5.0 |
| UI Framework | SwiftUI |
| Architecture | MVVM with `@Observable` state management |
| Concurrency | Swift async/await + Task groups |
| Networking | URLSession + NWConnection (for redirect resolution) |
| Video Playback | AVKit / AVPlayer |
| Persistence | UserDefaults |
| Build System | Xcode (`.xcodeproj`) |
| Deployment Target | iOS 26.2 |

---

## Repository Structure

```
StremioClient/
├── CLAUDE.md                          # This file
├── README.md                          # Feature overview
├── StremioClient.xcodeproj/           # Xcode project configuration
└── StremioClient/                     # All Swift source files
    ├── StremioClientApp.swift         # @main entry point
    ├── AppState.swift                 # Global auth + API key state
    ├── Assets.xcassets/               # Images, colors, app icon
    ├── Models/                        # Data model structs
    ├── Services/                      # Business logic and API clients
    ├── Utilities/                     # Shared helpers
    └── Views/                         # SwiftUI view hierarchy
```

---

## Architecture

### Entry Point

`StremioClientApp.swift` — The `@main` struct. Initializes top-level state objects as `@State` properties and conditionally shows `LoginView` or `MainTabView` based on authentication status. A 1.8-second splash screen (`SplashView`) is shown on launch.

### State Management

All major state managers are instantiated at the top level and passed into the environment:

| Class | Responsibility |
|---|---|
| `AppState` | Stremio auth token, Real-Debrid key, TMDB key, Claude API key |
| `AddonManager` | Installed addons, syncs with Stremio account |
| `DownloadManager` | Background URLSession downloads with progress tracking |
| `WatchHistoryManager` | Watch events, playback progress, watchlist, feedback ratings |

### Navigation

`MainTabView` defines five tabs:
1. **Discover** — Catalog browsing and recommendations
2. **Search** — Addon search + Claude conversational search
3. **Library** — Watchlist and Continue Watching
4. **Addons** — Addon management and installation
5. **Settings** — API keys and account management

---

## Key Source Files

### Models (`StremioClient/Models/`)

| File | Purpose |
|---|---|
| `Addon.swift` | Stremio addon manifest (resources, catalogs, behaviors) |
| `MetaItem.swift` | Movie/series metadata (title, poster, trailers, episodes) |
| `StreamItem.swift` | Playable stream (direct URL or torrent hash + infoHash) |
| `Download.swift` | Download state enum: queued, downloading, completed, failed |
| `PlaybackProgress.swift` | Continue Watching: resumeSeconds, duration, episode |
| `StremioUser.swift` | User profile from Stremio API |
| `WatchEvent.swift` | Historical watch record |
| `WatchlistItem.swift` | Saved/bookmarked content |

### Services (`StremioClient/Services/`)

| File | Purpose |
|---|---|
| `StremioAPI.swift` | Stremio backend: login, logout, addon collection sync |
| `AddonClient.swift` | Addon protocol: manifest, catalog, meta, streams, search |
| `AddonManager.swift` | Manages installed addons, syncs with Stremio account |
| `RealDebridService.swift` | Real-Debrid API: key validation, stream checking |
| `DownloadManager.swift` | Background URLSession downloads |
| `ClaudeSearchService.swift` | Multi-turn conversational content search via Claude API |
| `ClaudeRecommendationService.swift` | Claude-powered recommendations |
| `RecommendationEngine.swift` | Local scoring engine based on genres, cast, directors |
| `TMDBService.swift` | "Because You Watched" recommendations from TMDB |
| `WatchHistoryManager.swift` | Watch events, progress, feedback, watchlist persistence |

### Utilities (`StremioClient/Utilities/`)

| File | Purpose |
|---|---|
| `Theme.swift` | Dark purple color palette and standard card dimensions |
| `RedirectResolver.swift` | Custom HTTP redirect resolver using `NWConnection` (avoids QUIC/HTTP3 issues with torrentio) |
| `StreamSelector.swift` | Tiered stream selection: RD-cached > MP4 > quality > seeders |

### Views (`StremioClient/Views/`)

| Directory/File | Purpose |
|---|---|
| `MainTabView.swift` | Root 5-tab navigation |
| `SplashView.swift` | Launch splash screen |
| `Home/` | Catalog rows, hero banners, recommendation carousels |
| `Search/` | Text search + Claude conversational search UI |
| `Detail/` | Movie/series detail page, episode picker, stream list |
| `Player/` | AVKit player with custom auto-hide controls |
| `Library/` | Watchlist grid and Continue Watching row |
| `Downloads/` | Download list with progress, speed, retry, delete |
| `Addons/` | Addon browser, install by URL, manage installed |
| `Auth/` | Login screen |

---

## API Integrations

### Stremio API (`https://api.strem.io/api`)

- `POST /login` — Authenticate with email/password
- `POST /logout` — Sign out
- `POST /addonCollectionGet` — Fetch user's installed addons
- `POST /addonCollectionSet` — Sync local addon list to account

### Stremio Addon Protocol (per-addon base URL)

- `GET /manifest.json` — Addon capabilities and catalog definitions
- `GET /catalog/{type}/{id}.json` — Browse content (with optional `skip=N` for pagination)
- `GET /catalog/{type}/{id}/search={query}.json` — Search content
- `GET /meta/{type}/{id}.json` — Item metadata
- `GET /stream/{type}/{id}.json` — Available streams

### Real-Debrid API (`https://api.real-debrid.com/rest/1.0`)

- `GET /user` — Validate API key and fetch account info

### TMDB API (`https://api.themoviedb.org/3`)

- `GET /find/{imdb_id}?external_source=imdb_id` — Resolve IMDB ID to TMDB ID
- `GET /{movie|tv}/{tmdb_id}/recommendations` — Get similar content
- `GET /{movie|tv}/{id}/external_ids` — Retrieve IMDB/external IDs

### Claude API (`https://api.anthropic.com/v1/messages`)

- `POST /messages` — Conversational search and AI recommendations
- Model in use: `claude-haiku-4-5-20251001`
- Max tokens: 1024
- Used in: `ClaudeSearchService.swift`, `ClaudeRecommendationService.swift`

---

## Configuration & Persistence

All API keys are entered through the in-app Settings screen. There are no `.env` files. All data is persisted in `UserDefaults` with the following keys:

| Key | Content |
|---|---|
| `authKey` | Stremio auth token (String) |
| `user` | Stremio user profile (JSON-encoded `StremioUser`) |
| `rdKey` | Real-Debrid API key (String) |
| `rdUser` | Real-Debrid user info (JSON-encoded) |
| `tmdbApiKey` | TMDB API key (String) |
| `claudeApiKey` | Claude API key (String) |
| `installed_addons` | Addon list (JSON-encoded `[Addon]`) |
| `downloads` | Active/completed downloads (JSON-encoded `[Download]`) |
| `watchHistory` | Watch events (JSON-encoded) |
| `watchProgress` | Per-item playback progress (JSON-encoded) |
| `watchFeedback` | User ratings: liked/disliked (JSON-encoded) |
| `watchlist` | Saved content (JSON-encoded) |

---

## Development Conventions

### SwiftUI Patterns

- Use `@Observable` (Swift 5.9 macro) for state classes rather than `ObservableObject`/`@Published`.
- Pass state objects via `.environment()` at the root; read them with `@Environment` in child views.
- Prefer `NavigationStack` over `NavigationView`.
- Use `LazyVStack` / `LazyHStack` inside `ScrollView` for large lists.

### Concurrency

- All network calls use `async/await`. Wrap URLSession calls in `async` methods.
- Use `Task { }` in view `.task {}` modifiers to kick off async work.
- Use `TaskGroup` for parallel addon requests (e.g., fetching streams from multiple addons simultaneously).
- Never block the main actor with heavy work — use `Task.detached` or background actor isolation where needed.

### Networking

- Use `URLSession.shared` for standard requests.
- Use `RedirectResolver` (NWConnection-based) when fetching streaming URLs to avoid QUIC/HTTP3 redirect issues specific to torrentio endpoints.
- `StreamSelector` must be consulted before presenting streams to the user — it applies tiered quality selection logic.

### Error Handling

- Services throw typed errors; callers catch and surface errors to the UI as optional state.
- Avoid `fatalError` in production paths; prefer silent failures with fallback UI states.

### Naming Conventions

- Types: `UpperCamelCase`
- Properties and methods: `lowerCamelCase`
- File names match the primary type they define (e.g., `AddonManager.swift` contains `class AddonManager`)
- View files are named after the screen they represent (e.g., `DetailView.swift`, `PlayerView.swift`)

### Theme

All colors and layout constants live in `Theme.swift`. Do not hardcode colors or padding values in views — reference `Theme` constants for consistency with the dark purple visual design.

---

## Build & Run

This is a pure Xcode project. There is no `package.json`, no npm, and no external Swift Package Manager dependencies.

1. Open `StremioClient.xcodeproj` in Xcode.
2. Select a simulator or physical iOS device (iOS 26.2+).
3. Build and run with `Cmd+R`.

There are no automated tests or CI/CD pipelines in this repository.

---

## Git Workflow

- **Main branch**: `main`
- **Active development branch**: Feature branches prefixed with `claude/` for AI-assisted work
- Commit messages are descriptive and in imperative mood (e.g., "Fix trailer duplicate ID issues")
- Co-authored commits with Claude are marked with `Co-authored-by:` trailers

---

## Key Design Decisions

1. **UserDefaults over CoreData** — Simplicity is preferred; the data volume (watch history, addon list) does not require a relational database.
2. **NWConnection for redirect resolution** — `URLSession` follows redirects transparently but fails with QUIC/HTTP3 on certain torrent stream endpoints; `RedirectResolver` uses a lower-level TCP connection to manually follow HTTP 302 responses.
3. **Claude AI for search** — The conversational search feature (`ClaudeSearchService`) allows multi-turn dialog to refine search queries, which is more expressive than simple keyword search across addon catalogs.
4. **Tiered stream selection** — `StreamSelector` always prefers Real-Debrid cached torrents, then direct MP4 links, then quality/seeder ranking — ensuring the best available stream is auto-selected without user intervention.
5. **No SPM dependencies** — The app relies entirely on Apple frameworks (AVKit, Network, Security, SwiftUI) to minimize dependency management overhead.
