import React, { useState, useEffect, useMemo, useRef } from "react";
import { Box, Text, useInput } from "ink";

/**
 * A line of content with optional ANSI-style color props.
 * Each ContentLine maps to exactly one logical line of content.
 * Long lines are wrapped to fit the terminal width.
 */
export interface ContentLine {
  text: string;
  color?: string;
  dimColor?: boolean;
  bold?: boolean;
}

interface ScrollableViewProps {
  /** Lines of content to display. */
  lines: ContentLine[];
  /** Number of visible rows (excluding footer). */
  height: number;
  /** Available width for text content. */
  width: number;
  /** Whether this view captures keyboard input for scrolling. */
  active?: boolean;
  /** Footer text shown below the scroll area. */
  footer?: string;
}

/**
 * Strip ANSI escape codes to get the visible character count.
 */
function visibleLength(str: string): number {
  // eslint-disable-next-line no-control-regex
  return str.replace(/\x1b\[[0-9;]*m/g, "").length;
}

/**
 * Wrap a single logical line into multiple display lines that fit within `width`.
 * Splits on word boundaries where possible.
 */
function wrapLine(text: string, width: number): string[] {
  if (width <= 0) return [text];
  if (visibleLength(text) <= width) return [text];

  const words = text.split(/(\s+)/); // Keep whitespace as separate tokens
  const lines: string[] = [];
  let current = "";

  for (const word of words) {
    const testLine = current + word;
    if (visibleLength(testLine) > width && current.length > 0) {
      lines.push(current);
      // Continuation indent: align with content start
      current = "  " + word.trimStart();
    } else {
      current = testLine;
    }
  }
  if (current) lines.push(current);

  return lines.length > 0 ? lines : [""];
}

/**
 * A display row: the visible text for one terminal line,
 * with a reference back to the logical line index.
 */
interface DisplayRow {
  text: string;
  lineIndex: number;
  color?: string;
  dimColor?: boolean;
  bold?: boolean;
}

/**
 * Pre-process content lines into display rows, wrapping as needed.
 * Returns the display rows and a mapping from logical line index to first display row index.
 */
function buildDisplayRows(lines: ContentLine[], width: number): {
  rows: DisplayRow[];
  lineToRow: number[]; // lineToRow[logicalIndex] = first display row index
} {
  const rows: DisplayRow[] = [];
  const lineToRow: number[] = [];

  for (let i = 0; i < lines.length; i++) {
    lineToRow.push(rows.length);
    const wrapped = wrapLine(lines[i].text, width);
    for (const text of wrapped) {
      rows.push({
        text,
        lineIndex: i,
        color: lines[i].color,
        dimColor: lines[i].dimColor,
        bold: lines[i].bold,
      });
    }
  }

  return { rows, lineToRow };
}

export function ScrollableView({
  lines,
  height,
  width,
  active = true,
  footer,
}: ScrollableViewProps) {
  const [scrollOffset, setScrollOffset] = useState(0);
  const prevWidthRef = useRef(width);
  const prevRowsRef = useRef<DisplayRow[]>([]);

  // Build wrapped display rows whenever lines or width change
  const { rows, lineToRow } = useMemo(
    () => buildDisplayRows(lines, width),
    [lines, width],
  );

  // On resize: keep the same logical content at the top of the viewport
  useEffect(() => {
    if (prevWidthRef.current !== width && prevRowsRef.current.length > 0) {
      // Find which logical line was at the top before resize
      const oldTopRow = prevRowsRef.current[scrollOffset];
      if (oldTopRow) {
        const newTopRowIndex = lineToRow[oldTopRow.lineIndex] ?? 0;
        setScrollOffset(Math.min(newTopRowIndex, Math.max(0, rows.length - height)));
      }
    }
    prevWidthRef.current = width;
    prevRowsRef.current = rows;
  }, [width, rows, lineToRow, height]);

  // Clamp scroll offset when content changes
  useEffect(() => {
    setScrollOffset((prev) => Math.min(prev, Math.max(0, rows.length - height)));
  }, [rows.length, height]);

  const maxScroll = Math.max(0, rows.length - height);

  useInput((input, key) => {
    if (!active) return;

    if (key.upArrow) {
      setScrollOffset((s) => Math.max(0, s - 1));
    } else if (key.downArrow) {
      setScrollOffset((s) => Math.min(maxScroll, s + 1));
    } else if (key.pageUp) {
      setScrollOffset((s) => Math.max(0, s - height));
    } else if (key.pageDown) {
      setScrollOffset((s) => Math.min(maxScroll, s + height));
    }
  });

  // Visible slice
  const visible = rows.slice(scrollOffset, scrollOffset + height);

  // Scrollbar
  const showScrollbar = rows.length > height;
  const thumbSize = Math.max(1, Math.round((height / rows.length) * height));
  const thumbStart = Math.round((scrollOffset / Math.max(1, rows.length)) * height);

  // Content area width: leave 1 col for scrollbar if needed
  const textWidth = showScrollbar ? width - 1 : width;

  return (
    <Box flexDirection="column">
      <Box flexDirection="column">
        {visible.map((row, i) => {
          const isThumb = showScrollbar && i >= thumbStart && i < thumbStart + thumbSize;

          return (
            <Box key={`${row.lineIndex}-${i}`}>
              <Box width={textWidth}>
                <Text
                  color={row.color as any}
                  dimColor={row.dimColor}
                  bold={row.bold}
                  wrap="truncate"
                >
                  {row.text}
                </Text>
              </Box>
              {showScrollbar && (
                <Text dimColor={!isThumb} color={isThumb ? "gray" : undefined}>
                  {isThumb ? "▐" : " "}
                </Text>
              )}
            </Box>
          );
        })}
      </Box>
      {footer && (
        <Box marginTop={1}>
          <Text dimColor>  {footer}</Text>
        </Box>
      )}
    </Box>
  );
}
