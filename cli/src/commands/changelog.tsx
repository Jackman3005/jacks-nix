import React, { useState, useEffect, useMemo } from "react";
import { Box, Text, useInput, useApp } from "ink";
import Spinner from "ink-spinner";
import TextInput from "ink-text-input";
import { Header } from "../components/Header.js";
import { ScrollableView, type ContentLine } from "../components/ScrollableView.js";
import { renderChangelog } from "../lib/changelog-renderer.js";
import { useTerminalSize } from "../hooks/useTerminalSize.js";
import {
  loadChangelog, aggregateChangelogs, type ChangelogEntry,
} from "../lib/changelog.js";
import { getDeclaredPackages } from "../lib/packages.js";
import { readdirSync } from "../lib/fs.js";
import { join } from "node:path";

interface ChangelogCommandProps {
  repoPath: string;
}

type Mode = "list" | "search" | "detail" | "summary-select" | "summary-detail";

/** One-line description for a changelog entry. */
function versionSummaryLine(entry: ChangelogEntry): string {
  const parts: string[] = [];
  const keyUpgrades = entry.packageChanges.upgraded.slice(0, 3).map((u) => u.name);
  if (keyUpgrades.length > 0) parts.push(keyUpgrades.join(", "));
  if (entry.manualCommits.length > 0) {
    parts.push(entry.manualCommits[0].message);
  }
  if (parts.length === 0) parts.push("Package updates");
  return parts.join(" · ");
}

/** Format timestamp as "Mar 24" style. */
function formatDate(timestamp: string): string {
  try {
    const d = new Date(timestamp);
    const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    return `${months[d.getMonth()]} ${String(d.getDate()).padStart(2, " ")}`;
  } catch {
    return "";
  }
}

/** Extract year from timestamp. */
function getYear(timestamp: string): string {
  try {
    return String(new Date(timestamp).getFullYear());
  } catch {
    return "";
  }
}

/** Check if an entry matches a search query. */
function matchesSearch(entry: ChangelogEntry, query: string): boolean {
  const q = query.toLowerCase();
  if (String(entry.version).includes(q)) return true;
  if (entry.timestamp.toLowerCase().includes(q)) return true;
  for (const u of entry.packageChanges.upgraded) {
    if (u.name.toLowerCase().includes(q)) return true;
  }
  for (const c of entry.manualCommits) {
    if (c.message.toLowerCase().includes(q)) return true;
  }
  for (const a of entry.packageChanges.added) {
    if (a.name.toLowerCase().includes(q)) return true;
  }
  return false;
}

/** Render a single changelog entry to ContentLine[] for ScrollableView. */
function renderEntryDetail(entry: ChangelogEntry, declared: Set<string>): ContentLine[] {
  return renderChangelog({
    fromVersion: String(entry.version - 1),
    toVersion: String(entry.version),
    upgrades: new Map(entry.packageChanges.upgraded.map((u) => [u.name, u])),
    added: new Map(entry.packageChanges.added.map((p) => [p.name, p])),
    removed: new Map(entry.packageChanges.removed.map((p) => [p.name, p])),
    commits: entry.manualCommits,
    latestSizes: entry.closureSizes,
    earliestSizes: entry.closureSizes,
    declaredPackages: declared,
    detailed: true,
  });
}

export function ChangelogCommand({ repoPath }: ChangelogCommandProps) {
  const { exit } = useApp();
  const { width: termWidth, height: termHeight } = useTerminalSize();

  const [loading, setLoading] = useState(true);
  const [entries, setEntries] = useState<ChangelogEntry[]>([]);
  const [declared, setDeclared] = useState<Set<string>>(new Set());
  const [error, setError] = useState("");

  // UI state
  const [mode, setMode] = useState<Mode>("list");
  const [cursor, setCursor] = useState(0);
  const [scrollOffset, setScrollOffset] = useState(0);
  const [searchQuery, setSearchQuery] = useState("");
  const [summaryStart, setSummaryStart] = useState(0);
  const [summaryCursor, setSummaryCursor] = useState(0);
  const [summaryLines, setSummaryLines] = useState<ContentLine[]>([]);
  const [savedListCursor, setSavedListCursor] = useState(0);
  const [savedListScroll, setSavedListScroll] = useState(0);

  // Load all changelogs
  useEffect(() => {
    (async () => {
      try {
        const changelogDir = join(repoPath, "changelogs");
        const files = readdirSync(changelogDir).filter((f: string) => f.endsWith(".json")).sort((a: string, b: string) => {
          return parseInt(b) - parseInt(a); // newest first
        });

        const loaded: ChangelogEntry[] = [];
        for (const file of files) {
          const version = parseInt(file);
          if (isNaN(version)) continue;
          const entry = await loadChangelog(repoPath, version);
          if (entry) loaded.push(entry);
        }

        const packages = await getDeclaredPackages(repoPath).catch(() => []);
        setEntries(loaded);
        setDeclared(new Set(packages));
        setLoading(false);
      } catch (e) {
        setError(String(e));
        setLoading(false);
      }
    })();
  }, []);

  // Filtered entries based on search
  const filtered = useMemo(() => {
    if (!searchQuery) return entries;
    return entries.filter((e) => matchesSearch(e, searchQuery));
  }, [entries, searchQuery]);

  // Visible area for list
  const headerLines = 5; // header box (3) + margin (1) + ink cursor line (1)
  const footerLines = 2; // footer margin (1) + footer text (1)
  const searchBarLines = mode === "search" || searchQuery ? 2 : 0;
  const summaryBarLines = mode === "summary-select" ? 2 : 0;
  const listHeight = Math.max(1, termHeight - headerLines - footerLines - searchBarLines - summaryBarLines);
  const contentWidth = termWidth - 4; // padding

  // Clamp helpers
  const clampCursor = (c: number) => Math.max(0, Math.min(c, filtered.length - 1));

  // Detail view content
  const detailLines = useMemo(() => {
    if (mode !== "detail" || !filtered[cursor]) return [];
    return renderEntryDetail(filtered[cursor], declared);
  }, [mode, cursor, filtered, declared]);

  // Input handling
  useInput((input, key) => {
    if (mode === "list") {
      if (key.upArrow) {
        setCursor((c) => {
          const next = clampCursor(c - 1);
          if (next < scrollOffset) setScrollOffset(next);
          return next;
        });
      } else if (key.downArrow) {
        setCursor((c) => {
          const next = clampCursor(c + 1);
          if (next >= scrollOffset + listHeight) setScrollOffset(next - listHeight + 1);
          return next;
        });
      } else if (key.pageUp) {
        setCursor((c) => {
          const next = clampCursor(c - listHeight);
          setScrollOffset((s) => Math.max(0, s - listHeight));
          return next;
        });
      } else if (key.pageDown) {
        setCursor((c) => {
          const next = clampCursor(c + listHeight);
          setScrollOffset((s) => Math.min(Math.max(0, filtered.length - listHeight), s + listHeight));
          return next;
        });
      } else if (key.return && filtered.length > 0) {
        setMode("detail");
      } else if (input === "s" || input === "S") {
        if (filtered.length > 0) {
          setSummaryStart(filtered[cursor].version);
          setSummaryCursor(0);
          setSavedListCursor(cursor);
          setSavedListScroll(scrollOffset);
          setMode("summary-select");
        }
      } else if (input === "/") {
        setMode("search");
      } else if (input === "q") {
        exit();
      }
    } else if (mode === "search") {
      if (key.escape) {
        setSearchQuery("");
        setMode("list");
        setCursor(0);
        setScrollOffset(0);
      } else if (key.return) {
        setMode("list");
        setCursor(0);
        setScrollOffset(0);
      }
      // TextInput handles all character input including "c"
    } else if (mode === "detail") {
      // ScrollableView handles its own scrolling
      if (key.return || key.escape) {
        setMode("list");
      } else if (input === "s" || input === "S") {
        const startVersion = filtered[cursor].version;
        setSummaryStart(startVersion);
        setSummaryCursor(0);
        setSavedListCursor(cursor);
        setSavedListScroll(scrollOffset);
        setMode("summary-select");
      }
    } else if (mode === "summary-select") {
      if (key.escape) {
        setCursor(savedListCursor);
        setScrollOffset(savedListScroll);
        setMode("list");
      } else if (key.downArrow) {
        setSummaryCursor((c) => {
          const next = c + 1;
          const nextEntry = filtered[next];
          if (!nextEntry || nextEntry.version < summaryStart) return c;
          return next;
        });
      } else if (key.upArrow) {
        setSummaryCursor((c) => Math.max(0, c - 1));
      } else if (key.return || input === "s" || input === "S") {
        const endVersion = filtered[summaryCursor]?.version ?? filtered[0]?.version;
        (async () => {
          const data = await aggregateChangelogs(repoPath, summaryStart, endVersion);
          const lines = renderChangelog({
            fromVersion: String(summaryStart),
            toVersion: String(endVersion),
            upgrades: data.upgrades,
            added: data.added,
            removed: data.removed,
            commits: data.commits,
            latestSizes: data.latestSizes,
            earliestSizes: data.earliestSizes,
            declaredPackages: declared,
            detailed: true,
          });
          setSummaryLines(lines);
          setMode("summary-detail");
        })();
      }
    } else if (mode === "summary-detail") {
      // ScrollableView handles scrolling
      if (key.return || key.escape) {
        setCursor(savedListCursor);
        setScrollOffset(savedListScroll);
        setSummaryLines([]);
        setMode("list");
      }
    }
  });

  if (loading) {
    return <Text>  <Spinner type="dots" /> Loading changelogs...</Text>;
  }

  if (error) {
    return <Text color="red">  Error: {error}</Text>;
  }

  // --- DETAIL MODE ---
  if (mode === "detail" && filtered[cursor]) {
    const entry = filtered[cursor];
    return (
      <Box flexDirection="column">
        <Header icon="📋" title={`v${entry.version} — ${formatDate(entry.timestamp)}`} />
        <ScrollableView
          lines={detailLines}
          height={termHeight - headerLines - footerLines}
          width={contentWidth}
          active={true}
          footer="↑↓/PgUp/PgDn scroll · Enter/Esc close · S summary from here"
        />
      </Box>
    );
  }

  // --- SUMMARY DETAIL MODE ---
  if (mode === "summary-detail" && summaryLines.length > 0) {
    const endVersion = filtered[summaryCursor]?.version ?? filtered[0]?.version;
    return (
      <Box flexDirection="column">
        <Header icon="📊" title={`Summary: v${summaryStart} → v${endVersion}`} />
        <ScrollableView
          lines={summaryLines}
          height={termHeight - headerLines - footerLines}
          width={contentWidth}
          active={true}
          footer="↑↓/PgUp/PgDn scroll · Enter/Esc return to list"
        />
      </Box>
    );
  }

  // --- LIST MODE / SEARCH MODE / SUMMARY SELECT MODE ---
  const visibleEntries = filtered.slice(scrollOffset, scrollOffset + listHeight);

  return (
    <Box flexDirection="column">
      <Header icon="📋" title="jacks-nix changelog" />

      {/* Search bar */}
      {mode === "search" && (
        <Box marginBottom={1}>
          <Text>  / </Text>
          <TextInput
            value={searchQuery}
            onChange={setSearchQuery}
            placeholder="Search versions, packages, commits..."
          />
          <Text dimColor> (Esc clear, Enter keep filter)</Text>
        </Box>
      )}
      {mode !== "search" && searchQuery && (
        <Box marginBottom={1}>
          <Text dimColor>  Filter: "{searchQuery}" ({filtered.length} results) — / to edit</Text>
        </Box>
      )}

      {/* Summary mode indicator */}
      {mode === "summary-select" && (
        <Box marginBottom={1}>
          <Text color="cyan">  Summary: v{summaryStart} → select end version (↑↓ navigate, S/Enter confirm, Esc cancel)</Text>
        </Box>
      )}

      {/* Version list */}
      {filtered.length === 0 ? (
        <Text dimColor>  No matching versions.</Text>
      ) : (
        <Box flexDirection="column">
          {visibleEntries.map((entry, i) => {
            const listIndex = scrollOffset + i;
            const isSelected = mode === "summary-select" ? listIndex === summaryCursor : listIndex === cursor;
            const isInRange = mode === "summary-select" &&
              entry.version >= summaryStart &&
              entry.version <= (filtered[summaryCursor]?.version ?? 0);

            const desc = versionSummaryLine(entry);
            const maxDescLen = Math.max(10, termWidth - 22);
            const truncated = desc.length > maxDescLen ? desc.slice(0, maxDescLen - 3) + "..." : desc;

            // Year separator
            const prevEntry = visibleEntries[i - 1];
            const thisYear = getYear(entry.timestamp);
            const prevYear = prevEntry ? getYear(prevEntry.timestamp) : thisYear;
            const showYearSep = i === 0 || thisYear !== prevYear;

            const rowColor = isSelected ? "cyan" : isInRange ? "magenta" : undefined;

            return (
              <React.Fragment key={entry.version}>
                {showYearSep && (
                  <Box>
                    <Text dimColor>   ── {thisYear} ──────────────────────────────────</Text>
                  </Box>
                )}
                <Box>
                  {rowColor ? (
                    <Text color={rowColor} bold={isSelected}>
                      {isSelected ? " › " : "   "}
                      v{String(entry.version).padEnd(5)}
                      {formatDate(entry.timestamp)}  {truncated}
                    </Text>
                  ) : (
                    <>
                      <Text>{"   "}</Text>
                      <Text dimColor>v{String(entry.version).padEnd(5)}</Text>
                      <Text>{formatDate(entry.timestamp)}  </Text>
                      <Text color="yellowBright">{truncated}</Text>
                    </>
                  )}
                </Box>
              </React.Fragment>
            );
          })}
        </Box>
      )}

      {/* Footer */}
      <Box marginTop={1}>
        {mode === "list" && (
          <Text dimColor>  ↑↓ navigate · Enter detail · S summary · / search · q quit</Text>
        )}
      </Box>
    </Box>
  );
}
