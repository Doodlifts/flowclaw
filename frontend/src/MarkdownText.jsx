// Lightweight inline markdown renderer for chat messages
// Handles: **bold**, *italic*, `code`, ```code blocks```, # headers, - bullets, [links](url)

export default function MarkdownText({ children }) {
  if (!children) return null;
  const text = typeof children === "string" ? children : String(children);

  const lines = text.split("\n");
  const elements = [];
  let inCodeBlock = false;
  let codeLines = [];

  const parseInline = (line, key) => {
    const parts = [];
    let remaining = line;
    let partKey = 0;

    while (remaining.length > 0) {
      // Inline code: `text`
      let m = remaining.match(/^(.*?)`(.+?)`/);
      if (m) {
        if (m[1]) parts.push(m[1]);
        parts.push(<code key={`c${partKey++}`} className="bg-zinc-800 text-emerald-300 px-1 py-0.5 rounded text-[0.85em] font-mono">{m[2]}</code>);
        remaining = remaining.slice(m[0].length);
        continue;
      }
      // Bold: **text**
      m = remaining.match(/^(.*?)\*\*(.+?)\*\*/);
      if (m) {
        if (m[1]) parts.push(m[1]);
        parts.push(<strong key={`b${partKey++}`} className="font-semibold text-zinc-100">{m[2]}</strong>);
        remaining = remaining.slice(m[0].length);
        continue;
      }
      // Italic: *text*
      m = remaining.match(/^(.*?)(?<!\w)\*(.+?)\*(?!\w)/);
      if (m) {
        if (m[1]) parts.push(m[1]);
        parts.push(<em key={`i${partKey++}`}>{m[2]}</em>);
        remaining = remaining.slice(m[0].length);
        continue;
      }
      // Link: [text](url)
      m = remaining.match(/^(.*?)\[(.+?)\]\((.+?)\)/);
      if (m) {
        if (m[1]) parts.push(m[1]);
        parts.push(<a key={`a${partKey++}`} href={m[3]} target="_blank" rel="noopener" className="text-emerald-400 underline hover:text-emerald-300">{m[2]}</a>);
        remaining = remaining.slice(m[0].length);
        continue;
      }
      // No more matches
      parts.push(remaining);
      break;
    }
    return <span key={key}>{parts}</span>;
  };

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];

    // Code blocks: ```
    if (line.startsWith("```")) {
      if (inCodeBlock) {
        elements.push(
          <pre key={`code-${i}`} className="bg-zinc-800/80 border border-zinc-700/50 rounded-lg px-3 py-2 my-1 overflow-x-auto">
            <code className="text-[0.85em] font-mono text-zinc-300">{codeLines.join("\n")}</code>
          </pre>
        );
        codeLines = [];
        inCodeBlock = false;
      } else {
        inCodeBlock = true;
      }
      continue;
    }

    if (inCodeBlock) {
      codeLines.push(line);
      continue;
    }

    // Empty line
    if (!line.trim()) {
      elements.push(<br key={`br-${i}`} />);
      continue;
    }

    // Headers
    const hMatch = line.match(/^(#{1,3})\s+(.+)/);
    if (hMatch) {
      const level = hMatch[1].length;
      const cls = level === 1 ? "text-base font-bold text-zinc-100 mt-2 mb-1"
                : level === 2 ? "text-sm font-semibold text-zinc-200 mt-1.5 mb-0.5"
                : "text-sm font-medium text-zinc-300 mt-1 mb-0.5";
      elements.push(<div key={`h-${i}`} className={cls}>{parseInline(hMatch[2], `hi-${i}`)}</div>);
      continue;
    }

    // Bullets
    const bulletMatch = line.match(/^(\s*)[*-]\s+(.+)/);
    if (bulletMatch) {
      const indent = Math.floor((bulletMatch[1] || "").length / 2);
      elements.push(
        <div key={`li-${i}`} className="flex items-start gap-1.5" style={{ paddingLeft: `${indent * 12}px` }}>
          <span className="text-zinc-500 mt-[3px] text-[8px]">●</span>
          <span>{parseInline(bulletMatch[2], `lit-${i}`)}</span>
        </div>
      );
      continue;
    }

    // Regular line
    elements.push(<div key={`p-${i}`}>{parseInline(line, `pl-${i}`)}</div>);
  }

  return <div className="leading-relaxed">{elements}</div>;
}
